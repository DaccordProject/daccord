extends GutTest

var _pc: AccordPeerConnection


func _make_pc(ice_servers: Array = []) -> AccordPeerConnection:
	if ice_servers.size() == 0:
		ice_servers = [{"urls": ["stun:stun.l.google.com:19302"]}]
	var config = {"ice_servers": ice_servers}
	return AccordStream.create_peer_connection(config)


func before_each():
	_pc = _make_pc()

func after_each():
	if _pc:
		_pc.close()
		_pc = null


# ========================================================================
#  Creation
# ========================================================================

func test_create_peer_connection():
	assert_not_null(_pc, "create_peer_connection should return a valid object")

func test_create_peer_connection_with_empty_config():
	var pc = AccordStream.create_peer_connection({})
	assert_not_null(pc, "Empty config should still create a peer connection")
	pc.close()

func test_create_peer_connection_with_empty_ice_servers():
	var pc = AccordStream.create_peer_connection({"ice_servers": []})
	assert_not_null(pc, "Empty ice_servers array should still work")
	pc.close()

func test_create_peer_connection_with_turn_credentials():
	var pc = _make_pc([{
		"urls": ["stun:stun.l.google.com:19302"],
		"username": "testuser",
		"credential": "testpass",
	}])
	assert_not_null(pc, "Config with TURN credentials should work")
	pc.close()

func test_create_peer_connection_with_multiple_ice_servers():
	var pc = _make_pc([
		{"urls": ["stun:stun.l.google.com:19302"]},
		{"urls": ["stun:stun1.l.google.com:19302"]},
	])
	assert_not_null(pc, "Multiple ICE servers should work")
	pc.close()

func test_create_multiple_peer_connections():
	var pc2 = _make_pc()
	var pc3 = _make_pc()
	assert_not_null(_pc)
	assert_not_null(pc2)
	assert_not_null(pc3)
	pc2.close()
	pc3.close()


# ========================================================================
#  Initial state
# ========================================================================

func test_initial_connection_state_is_new():
	assert_eq(_pc.get_connection_state(), AccordPeerConnection.STATE_NEW,
			  "Initial connection state should be NEW")

func test_initial_signaling_state_is_stable():
	assert_eq(_pc.get_signaling_state(), AccordPeerConnection.SIGNALING_STABLE,
			  "Initial signaling state should be STABLE")

func test_initial_ice_connection_state_is_new():
	assert_eq(_pc.get_ice_connection_state(), AccordPeerConnection.ICE_NEW,
			  "Initial ICE state should be NEW")


# ========================================================================
#  get_stats
# ========================================================================

func test_get_stats_returns_dictionary():
	var stats = _pc.get_stats()
	assert_typeof(stats, TYPE_DICTIONARY, "get_stats() should return a Dictionary")

func test_get_stats_has_required_keys():
	var stats = _pc.get_stats()
	assert_has(stats, "connection_state")
	assert_has(stats, "signaling_state")
	assert_has(stats, "ice_connection_state")

func test_get_stats_values_match_getters():
	var stats = _pc.get_stats()
	assert_eq(stats["connection_state"], _pc.get_connection_state())
	assert_eq(stats["signaling_state"], _pc.get_signaling_state())
	assert_eq(stats["ice_connection_state"], _pc.get_ice_connection_state())


# ========================================================================
#  get_senders
# ========================================================================

func test_get_senders_returns_array():
	var senders = _pc.get_senders()
	assert_typeof(senders, TYPE_ARRAY)

func test_get_senders_empty_initially():
	var senders = _pc.get_senders()
	assert_eq(senders.size(), 0,
			  "No senders should exist before add_track")


# ========================================================================
#  get_receivers
# ========================================================================

func test_get_receivers_returns_array():
	var receivers = _pc.get_receivers()
	assert_typeof(receivers, TYPE_ARRAY)

func test_get_receivers_empty_initially():
	var receivers = _pc.get_receivers()
	assert_eq(receivers.size(), 0,
			  "No receivers should exist before any remote tracks arrive")

func test_get_receivers_after_close():
	_pc.close()
	var receivers = _pc.get_receivers()
	assert_typeof(receivers, TYPE_ARRAY, "get_receivers() after close should return an Array")
	assert_eq(receivers.size(), 0)

func test_get_receivers_after_add_audio_track():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	# Adding a local track creates a transceiver which has a receiver
	var receivers = _pc.get_receivers()
	assert_gt(receivers.size(), 0,
			  "Adding a track should create a transceiver with a receiver")
	track.stop()

func test_receiver_dict_has_audio_level():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	var receivers = _pc.get_receivers()
	if receivers.size() == 0:
		pass_test("No receivers created — skipping")
		track.stop()
		return

	var receiver = receivers[0]
	assert_has(receiver, "audio_level", "Receiver dict should have audio_level key")
	assert_typeof(receiver["audio_level"], TYPE_FLOAT, "audio_level should be a float")
	track.stop()

func test_receiver_dict_has_track_info():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	var receivers = _pc.get_receivers()
	if receivers.size() == 0:
		pass_test("No receivers created — skipping")
		track.stop()
		return

	var receiver = receivers[0]
	assert_has(receiver, "track_kind", "Receiver dict should have track_kind")
	assert_eq(receiver["track_kind"], "audio")
	track.stop()


# ========================================================================
#  add_track / remove_track
# ========================================================================

func test_add_track_with_null_returns_error():
	var err = _pc.add_track(null)
	assert_ne(err, OK, "add_track(null) should return an error")

func test_add_microphone_track():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	var err = _pc.add_track(track)
	assert_eq(err, OK, "add_track should succeed")
	track.stop()

func test_add_camera_track():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cameras[0]["id"], 640, 480, 30)
	if not track:
		pass_test("Could not create camera track — skipping")
		return

	var err = _pc.add_track(track)
	assert_eq(err, OK, "add_track should succeed for video track")
	track.stop()

func test_senders_count_after_add_track():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	var senders = _pc.get_senders()
	assert_gt(senders.size(), 0, "Should have at least one sender after add_track")
	track.stop()

func test_sender_dict_has_track_info():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	var senders = _pc.get_senders()
	assert_gt(senders.size(), 0)
	var sender = senders[0]
	assert_has(sender, "track_id", "Sender dict should have track_id")
	assert_has(sender, "track_kind", "Sender dict should have track_kind")
	assert_eq(sender["track_kind"], "audio")
	track.stop()

func test_add_multiple_tracks():
	var mics = AccordStream.get_microphones()
	var cameras = AccordStream.get_cameras()
	var added := 0

	if mics.size() > 0:
		var mic_track = AccordStream.create_microphone_track(mics[0]["id"])
		if mic_track:
			_pc.add_track(mic_track)
			added += 1
			mic_track.stop()

	if cameras.size() > 0:
		var cam_track = AccordStream.create_camera_track(cameras[0]["id"], 640, 480, 30)
		if cam_track:
			_pc.add_track(cam_track)
			added += 1
			cam_track.stop()

	if added == 0:
		pass_test("No devices available — skipping")
		return

	var senders = _pc.get_senders()
	assert_eq(senders.size(), added,
			  "Sender count should match number of added tracks")

func test_remove_track():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)
	var err = _pc.remove_track(track)
	assert_eq(err, OK, "remove_track should succeed")
	track.stop()

func test_remove_track_with_null_returns_error():
	var err = _pc.remove_track(null)
	assert_ne(err, OK, "remove_track(null) should return an error")

func test_remove_track_not_added_returns_error():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	# Remove without adding first
	var err = _pc.remove_track(track)
	assert_ne(err, OK, "Removing a track that was never added should fail")
	track.stop()


# ========================================================================
#  SDP: create_offer
# ========================================================================

func test_create_offer_emits_signal():
	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	assert_signal_emitted(_pc, "offer_created",
						  "create_offer should emit offer_created")

func test_offer_sdp_is_nonempty_string():
	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if assert_signal_emitted(_pc, "offer_created"):
		var params = get_signal_parameters(_pc, "offer_created")
		var sdp: String = params[0]
		assert_typeof(sdp, TYPE_STRING)
		assert_gt(sdp.length(), 0, "SDP should not be empty")

func test_offer_type_is_offer():
	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if assert_signal_emitted(_pc, "offer_created"):
		var params = get_signal_parameters(_pc, "offer_created")
		assert_eq(params[1], "offer", "Type should be 'offer'")

func test_offer_sdp_contains_v_line():
	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if assert_signal_emitted(_pc, "offer_created"):
		var sdp: String = get_signal_parameters(_pc, "offer_created")[0]
		assert_true(sdp.begins_with("v=0"), "SDP should start with v=0")

func test_offer_with_audio_track_has_audio_media():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.add_track(track)

	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if assert_signal_emitted(_pc, "offer_created"):
		var sdp: String = get_signal_parameters(_pc, "offer_created")[0]
		assert_true(sdp.contains("m=audio"),
					"Offer SDP should contain an audio media section")
	track.stop()

func test_offer_with_video_track_has_video_media():
	var cameras = AccordStream.get_cameras()
	if cameras.size() == 0:
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cameras[0]["id"], 640, 480, 30)
	if not track:
		pass_test("Could not create camera track — skipping")
		return

	_pc.add_track(track)

	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if assert_signal_emitted(_pc, "offer_created"):
		var sdp: String = get_signal_parameters(_pc, "offer_created")[0]
		assert_true(sdp.contains("m=video"),
					"Offer SDP should contain a video media section")
	track.stop()


# ========================================================================
#  SDP: set_local_description / set_remote_description
# ========================================================================

func test_set_local_description_invalid_type_returns_error():
	var err = _pc.set_local_description("garbage", "v=0\r\n")
	assert_ne(err, OK, "Invalid SDP type should return an error")

func test_set_remote_description_invalid_type_returns_error():
	var err = _pc.set_remote_description("garbage", "v=0\r\n")
	assert_ne(err, OK, "Invalid SDP type should return an error")

func test_set_remote_description_does_not_crash_with_bad_sdp():
	var err = _pc.set_remote_description("offer", "this is not valid sdp")
	# May fail parsing, but must not crash
	pass_test("set_remote_description with bad SDP did not crash")

func test_set_local_description_with_generated_offer():
	watch_signals(_pc)
	_pc.create_offer()

	await get_tree().create_timer(2.0).timeout
	if not assert_signal_emitted(_pc, "offer_created"):
		return

	var params = get_signal_parameters(_pc, "offer_created")
	var sdp: String = params[0]
	var type: String = params[1]

	var err = _pc.set_local_description(type, sdp)
	assert_eq(err, OK, "Setting local description with our own offer should succeed")


# ========================================================================
#  ICE candidates
# ========================================================================

func test_add_ice_candidate_does_not_crash():
	# Without a remote description set, this will likely fail, but must not crash
	_pc.add_ice_candidate("audio", 0,
						  "candidate:1 1 udp 2122260223 192.168.1.1 12345 typ host")
	pass_test("add_ice_candidate did not crash")

func test_ice_candidate_signal_emitted_after_offer():
	watch_signals(_pc)
	_pc.create_offer()

	# ICE gathering can take time; wait a bit
	await get_tree().create_timer(3.0).timeout

	# ICE candidates may or may not be generated in headless mode
	# (depends on network config). We verify the signal exists but
	# don't require it to fire.
	var emitted = get_signal_emit_count(_pc, "ice_candidate_generated")
	gut.p("ICE candidates generated: %d" % emitted)
	pass_test("ice_candidate_generated check completed (count=%d)" % emitted)


# ========================================================================
#  Lifecycle: close
# ========================================================================

func test_close_sets_state_to_closed():
	_pc.close()
	assert_eq(_pc.get_connection_state(), AccordPeerConnection.STATE_CLOSED,
			  "State should be CLOSED after close()")

func test_close_is_idempotent():
	_pc.close()
	_pc.close()
	assert_eq(_pc.get_connection_state(), AccordPeerConnection.STATE_CLOSED)
	pass_test("Double close() did not crash")

func test_get_senders_after_close():
	_pc.close()
	var senders = _pc.get_senders()
	assert_typeof(senders, TYPE_ARRAY, "get_senders() after close should return an Array")

func test_get_stats_after_close():
	_pc.close()
	var stats = _pc.get_stats()
	assert_typeof(stats, TYPE_DICTIONARY, "get_stats() after close should return a Dictionary")

func test_create_offer_after_close_does_not_crash():
	_pc.close()
	_pc.create_offer()
	pass_test("create_offer after close did not crash")

func test_add_track_after_close_returns_error():
	var mics = AccordStream.get_microphones()
	if mics.size() == 0:
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mics[0]["id"])
	if not track:
		pass_test("Could not create mic track — skipping")
		return

	_pc.close()
	var err = _pc.add_track(track)
	assert_ne(err, OK, "add_track after close should fail")
	track.stop()


# ========================================================================
#  Enum constants accessible
# ========================================================================

func test_connection_state_enum_values():
	assert_eq(AccordPeerConnection.STATE_NEW, 0)
	assert_eq(AccordPeerConnection.STATE_CONNECTING, 1)
	assert_eq(AccordPeerConnection.STATE_CONNECTED, 2)
	assert_eq(AccordPeerConnection.STATE_DISCONNECTED, 3)
	assert_eq(AccordPeerConnection.STATE_FAILED, 4)
	assert_eq(AccordPeerConnection.STATE_CLOSED, 5)

func test_signaling_state_enum_values():
	assert_eq(AccordPeerConnection.SIGNALING_STABLE, 0)
	assert_eq(AccordPeerConnection.SIGNALING_HAVE_LOCAL_OFFER, 1)
	assert_eq(AccordPeerConnection.SIGNALING_HAVE_LOCAL_PRANSWER, 2)
	assert_eq(AccordPeerConnection.SIGNALING_HAVE_REMOTE_OFFER, 3)
	assert_eq(AccordPeerConnection.SIGNALING_HAVE_REMOTE_PRANSWER, 4)
	assert_eq(AccordPeerConnection.SIGNALING_CLOSED, 5)

func test_ice_connection_state_enum_values():
	assert_eq(AccordPeerConnection.ICE_NEW, 0)
	assert_eq(AccordPeerConnection.ICE_CHECKING, 1)
	assert_eq(AccordPeerConnection.ICE_CONNECTED, 2)
	assert_eq(AccordPeerConnection.ICE_COMPLETED, 3)
	assert_eq(AccordPeerConnection.ICE_FAILED, 4)
	assert_eq(AccordPeerConnection.ICE_DISCONNECTED, 5)
	assert_eq(AccordPeerConnection.ICE_CLOSED, 6)

func test_media_track_state_enum_values():
	assert_eq(AccordMediaTrack.TRACK_STATE_LIVE, 0)
	assert_eq(AccordMediaTrack.TRACK_STATE_ENDED, 1)
