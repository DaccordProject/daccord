extends GutTest

## End-to-end integration tests that exercise multi-step workflows:
## device enumeration → track creation → peer connection → SDP negotiation.


func _make_pc() -> AccordPeerConnection:
	return AccordStream.create_peer_connection({
		"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]}]
	})


# ========================================================================
#  Full publish flow: mic track → PC → offer → set local desc
# ========================================================================

func test_publish_audio_flow():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return

	# 1. Create track
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	assert_not_null(track, "Step 1: Create mic track")
	if not track:
		return

	assert_eq(track.get_kind(), "audio")
	assert_eq(track.get_state(), AccordMediaTrack.TRACK_STATE_LIVE)

	# 2. Create peer connection
	var pc = _make_pc()
	assert_not_null(pc, "Step 2: Create peer connection")
	if not pc:
		track.stop()
		return

	# 3. Add track
	var err = pc.add_track(track)
	assert_eq(err, OK, "Step 3: Add track to peer connection")

	# 4. Verify sender appeared
	var senders = pc.get_senders()
	assert_eq(senders.size(), 1, "Should have exactly 1 sender")
	assert_eq(senders[0]["track_kind"], "audio")

	# 5. Generate offer
	watch_signals(pc)
	pc.create_offer()
	await get_tree().create_timer(2.0).timeout
	assert_signal_emitted(pc, "offer_created", "Step 5: Offer should be created")

	if get_signal_emit_count(pc, "offer_created") > 0:
		var params = get_signal_parameters(pc, "offer_created")
		var sdp: String = params[0]
		var type: String = params[1]

		assert_eq(type, "offer")
		assert_true(sdp.contains("m=audio"), "SDP should contain audio media line")

		# 6. Set local description
		err = pc.set_local_description(type, sdp)
		assert_eq(err, OK, "Step 6: Set local description")

	# Cleanup
	track.stop()
	pc.close()


# ========================================================================
#  Full publish flow: camera track → PC → offer → set local desc
# ========================================================================

func test_publish_video_flow():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No camera available — skipping")
		return

	var track = AccordStream.create_camera_track(cameras[0]["id"], 640, 480, 30)
	assert_not_null(track, "Create camera track")
	if not track:
		return

	assert_eq(track.get_kind(), "video")

	var pc = _make_pc()
	assert_not_null(pc)
	if not pc:
		track.stop()
		return

	pc.add_track(track)

	watch_signals(pc)
	pc.create_offer()
	await get_tree().create_timer(2.0).timeout

	if assert_signal_emitted(pc, "offer_created"):
		var params = get_signal_parameters(pc, "offer_created")
		assert_true(params[0].contains("m=video"), "SDP should contain video media line")

		var err = pc.set_local_description(params[1], params[0])
		assert_eq(err, OK)

	track.stop()
	pc.close()


# ========================================================================
#  Publish both audio + video
# ========================================================================

func test_publish_audio_and_video_flow():
	var mics = AccordStream.get_microphones()
	var cameras = AccordStream.get_cameras()

	if mics.size() == 0 and cameras.size() == 0:
		pass_test("No devices available — skipping")
		return

	var pc = _make_pc()
	assert_not_null(pc)
	if not pc:
		return

	var tracks := []

	if mics.size() > 0:
		var mic_track = AccordStream.create_microphone_track(mics[0]["id"])
		if mic_track:
			pc.add_track(mic_track)
			tracks.append(mic_track)

	if cameras.size() > 0:
		var cam_track = AccordStream.create_camera_track(cameras[0]["id"], 640, 480, 30)
		if cam_track:
			pc.add_track(cam_track)
			tracks.append(cam_track)

	assert_gt(tracks.size(), 0, "At least one track should have been added")

	# Senders should match
	var senders = pc.get_senders()
	assert_eq(senders.size(), tracks.size(),
			  "Sender count should match added tracks")

	# Offer
	watch_signals(pc)
	pc.create_offer()
	await get_tree().create_timer(2.0).timeout

	if assert_signal_emitted(pc, "offer_created"):
		var sdp: String = get_signal_parameters(pc, "offer_created")[0]

		for t in tracks:
			if t.get_kind() == "audio":
				assert_true(sdp.contains("m=audio"), "SDP should have audio section")
			elif t.get_kind() == "video":
				assert_true(sdp.contains("m=video"), "SDP should have video section")

	for t in tracks:
		t.stop()
	pc.close()


# ========================================================================
#  Screen share flow
# ========================================================================

func test_publish_screen_share_flow():
	var screens = AccordStream.get_screens()
	if screens.size() == 0:
		pass_test("No screens available — skipping")
		return

	var track = AccordStream.create_screen_track(screens[0]["id"], 15)
	assert_not_null(track, "Create screen track")
	if not track:
		return

	assert_eq(track.get_kind(), "video")

	var pc = _make_pc()
	assert_not_null(pc)
	if not pc:
		track.stop()
		return

	pc.add_track(track)

	watch_signals(pc)
	pc.create_offer()
	await get_tree().create_timer(2.0).timeout

	if assert_signal_emitted(pc, "offer_created"):
		var sdp: String = get_signal_parameters(pc, "offer_created")[0]
		assert_true(sdp.contains("m=video"), "Screen share SDP should contain video")

	track.stop()
	pc.close()


# ========================================================================
#  Two peer connections (simulating local loopback offer/answer)
# ========================================================================

func test_two_peer_connections_offer_answer():
	var pc_offer = _make_pc()
	var pc_answer = _make_pc()
	assert_not_null(pc_offer)
	assert_not_null(pc_answer)

	if not pc_offer or not pc_answer:
		if pc_offer:
			pc_offer.close()
		if pc_answer:
			pc_answer.close()
		return

	# Add a mic track to the offerer (if available)
	var mics = AccordStream.get_microphones()
	var track: AccordMediaTrack = null
	if mics.size() > 0:
		track = AccordStream.create_microphone_track(mics[0]["id"])
		if track:
			pc_offer.add_track(track)

	# Step 1: Offerer creates offer
	watch_signals(pc_offer)
	pc_offer.create_offer()
	await get_tree().create_timer(2.0).timeout

	if not assert_signal_emitted(pc_offer, "offer_created"):
		pc_offer.close()
		pc_answer.close()
		return

	var offer_params = get_signal_parameters(pc_offer, "offer_created")
	var offer_sdp: String = offer_params[0]
	var offer_type: String = offer_params[1]

	# Step 2: Offerer sets local description
	var err = pc_offer.set_local_description(offer_type, offer_sdp)
	assert_eq(err, OK, "Offerer: set local description")

	# Step 3: Answerer sets remote description (the offer)
	err = pc_answer.set_remote_description(offer_type, offer_sdp)
	assert_eq(err, OK, "Answerer: set remote description with offer")

	# Step 4: Answerer creates answer
	watch_signals(pc_answer)
	pc_answer.create_answer()
	await get_tree().create_timer(2.0).timeout

	if assert_signal_emitted(pc_answer, "answer_created"):
		var answer_params = get_signal_parameters(pc_answer, "answer_created")
		var answer_sdp: String = answer_params[0]
		var answer_type: String = answer_params[1]

		assert_eq(answer_type, "answer")
		assert_gt(answer_sdp.length(), 0, "Answer SDP should not be empty")

		# Step 5: Answerer sets local description
		err = pc_answer.set_local_description(answer_type, answer_sdp)
		assert_eq(err, OK, "Answerer: set local description")

		# Step 6: Offerer sets remote description (the answer)
		err = pc_offer.set_remote_description(answer_type, answer_sdp)
		assert_eq(err, OK, "Offerer: set remote description with answer")

	if track:
		track.stop()
	pc_offer.close()
	pc_answer.close()


# ========================================================================
#  Cleanup after track removal
# ========================================================================

func test_add_remove_add_track_cycle():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return

	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	var pc = _make_pc()
	assert_not_null(pc)

	# Add
	var err = pc.add_track(track)
	assert_eq(err, OK, "First add_track should succeed")
	assert_eq(pc.get_senders().size(), 1)

	# Remove
	err = pc.remove_track(track)
	assert_eq(err, OK, "remove_track should succeed")

	# Re-add the same track
	err = pc.add_track(track)
	assert_eq(err, OK, "Re-adding the same track should succeed")

	track.stop()
	pc.close()


# ========================================================================
#  Rapid create/close cycle (stress-light)
# ========================================================================

func test_rapid_create_close_cycle():
	for i in range(10):
		var pc = _make_pc()
		assert_not_null(pc, "Iteration %d: PC should be created" % i)
		pc.close()
	pass_test("10× create/close cycle completed without crashing")


# ========================================================================
#  All enumeration → all track types → offer (kitchen-sink)
# ========================================================================

func test_kitchen_sink():
	# Enumerate everything
	var cameras = AccordStream.get_cameras()
	var mics = AccordStream.get_microphones()
	var screens = AccordStream.get_screens()
	var windows = AccordStream.get_windows()

	gut.p("Devices: cameras=%d mics=%d screens=%d windows=%d" % [
		cameras.size(), mics.size(), screens.size(), windows.size()
	])

	# Create one track of each type that's available
	var tracks := []

	if cameras.size() > 0:
		var t = AccordStream.create_camera_track(cameras[0]["id"], 320, 240, 15)
		if t:
			tracks.append(t)

	if mics.size() > 0:
		var t = AccordStream.create_microphone_track(mics[0]["id"])
		if t:
			tracks.append(t)

	if screens.size() > 0:
		var t = AccordStream.create_screen_track(screens[0]["id"], 10)
		if t:
			tracks.append(t)

	if windows.size() > 0:
		var t = AccordStream.create_window_track(windows[0]["id"], 10)
		if t:
			tracks.append(t)

	gut.p("Created %d tracks" % tracks.size())

	if tracks.size() == 0:
		pass_test("No devices available — skipping kitchen-sink test")
		return

	# Add all tracks to a PC and generate offer
	var pc = _make_pc()
	assert_not_null(pc)

	for t in tracks:
		pc.add_track(t)

	watch_signals(pc)
	pc.create_offer()
	await get_tree().create_timer(3.0).timeout

	if assert_signal_emitted(pc, "offer_created"):
		var sdp: String = get_signal_parameters(pc, "offer_created")[0]
		assert_gt(sdp.length(), 100,
				  "Kitchen-sink SDP should be substantial")
		gut.p("Kitchen-sink SDP: %d bytes" % sdp.length())

	# Cleanup
	for t in tracks:
		t.stop()
	pc.close()
