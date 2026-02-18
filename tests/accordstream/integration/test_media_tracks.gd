extends GutTest


# --- Helper: get first available device id, or "" ---

func _get_first_camera_id() -> String:
	var cameras = AccordStream.get_cameras()
	return cameras[0]["id"] if cameras.size() > 0 else ""

func _get_first_mic_id() -> String:
	var mics = AccordStream.get_microphones()
	return mics[0]["id"] if mics.size() > 0 else ""

func _get_first_screen_id() -> int:
	var screens = AccordStream.get_screens()
	return screens[0]["id"] if screens.size() > 0 else -1

func _get_first_window_id() -> int:
	var windows = AccordStream.get_windows()
	return windows[0]["id"] if windows.size() > 0 else -1


# ========================================================================
#  Camera tracks
# ========================================================================

func test_create_camera_track_invalid_device_returns_null():
	var track = AccordStream.create_camera_track("nonexistent_device_xyz", 640, 480, 30)
	assert_null(track, "Creating track with bogus device id should return null")

func test_create_camera_track_empty_device_id_returns_null():
	var track = AccordStream.create_camera_track("", 640, 480, 30)
	assert_null(track, "Empty device id should return null")

func test_camera_track_kind():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track, "Should create camera track")
	assert_eq(track.get_kind(), "video", "Camera track kind should be 'video'")
	track.stop()

func test_camera_track_id_is_nonempty():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)
	assert_gt(track.get_id().length(), 0, "Track id should not be empty")
	track.stop()

func test_camera_track_initial_state_is_live():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)
	assert_eq(track.get_state(), AccordMediaTrack.TRACK_STATE_LIVE,
			  "Newly created track should be LIVE")
	track.stop()

func test_camera_track_enabled_by_default():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)
	assert_true(track.is_enabled(), "Track should be enabled by default")
	track.stop()

func test_camera_track_disable_enable_toggle():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)

	track.set_enabled(false)
	assert_false(track.is_enabled(), "Track should be disabled")

	track.set_enabled(true)
	assert_true(track.is_enabled(), "Track should be re-enabled")

	track.set_enabled(false)
	assert_false(track.is_enabled(), "Track should be disabled again")

	track.stop()

func test_camera_track_stop_emits_state_changed():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)

	watch_signals(track)
	track.stop()
	assert_signal_emitted(track, "state_changed")

func test_camera_track_stop_signal_carries_ended_state():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)

	watch_signals(track)
	track.stop()
	assert_signal_emitted_with_parameters(track, "state_changed",
										  [AccordMediaTrack.TRACK_STATE_ENDED])

func test_create_multiple_camera_tracks():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	# Some cameras may not allow >1 simultaneous open, but the calls
	# should not crash regardless.
	var track1 = AccordStream.create_camera_track(cam_id, 320, 240, 15)
	var track2 = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	# At least the first one should have succeeded
	assert_not_null(track1, "First camera track should succeed")
	if track1:
		track1.stop()
	if track2:
		track2.stop()


# ========================================================================
#  Microphone tracks
# ========================================================================

func test_create_microphone_track_does_not_crash_with_invalid_id():
	var track = AccordStream.create_microphone_track("no_such_mic")
	# ADM may fall back to default device, so null is not guaranteed.
	pass_test("create_microphone_track with invalid id did not crash")
	if track:
		track.stop()

func test_microphone_track_kind():
	var mic_id = _get_first_mic_id()
	if mic_id == "":
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mic_id)
	assert_not_null(track, "Should create microphone track")
	assert_eq(track.get_kind(), "audio", "Microphone track kind should be 'audio'")
	track.stop()

func test_microphone_track_id_is_nonempty():
	var mic_id = _get_first_mic_id()
	if mic_id == "":
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mic_id)
	assert_not_null(track)
	assert_gt(track.get_id().length(), 0, "Track id should not be empty")
	track.stop()

func test_microphone_track_initial_state_is_live():
	var mic_id = _get_first_mic_id()
	if mic_id == "":
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mic_id)
	assert_not_null(track)
	assert_eq(track.get_state(), AccordMediaTrack.TRACK_STATE_LIVE,
			  "Newly created audio track should be LIVE")
	track.stop()

func test_microphone_track_enable_disable():
	var mic_id = _get_first_mic_id()
	if mic_id == "":
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mic_id)
	assert_not_null(track)
	assert_true(track.is_enabled())

	track.set_enabled(false)
	assert_false(track.is_enabled())

	track.set_enabled(true)
	assert_true(track.is_enabled())
	track.stop()

func test_microphone_track_stop_emits_state_changed():
	var mic_id = _get_first_mic_id()
	if mic_id == "":
		pass_test("No microphone available — skipping")
		return
	var track = AccordStream.create_microphone_track(mic_id)
	assert_not_null(track)

	watch_signals(track)
	track.stop()
	assert_signal_emitted_with_parameters(track, "state_changed",
										  [AccordMediaTrack.TRACK_STATE_ENDED])


# ========================================================================
#  Screen tracks
# ========================================================================

func test_create_screen_track_invalid_id():
	var track = AccordStream.create_screen_track(-9999, 15)
	# Should either return null or a valid track depending on platform
	pass_test("create_screen_track with invalid id did not crash")
	if track:
		track.stop()

func test_screen_track_kind():
	var screen_id = _get_first_screen_id()
	if screen_id == -1:
		pass_test("No screens available — skipping")
		return
	var track = AccordStream.create_screen_track(screen_id, 15)
	assert_not_null(track, "Should create screen track")
	assert_eq(track.get_kind(), "video", "Screen track kind should be 'video'")
	track.stop()

func test_screen_track_initial_state_is_live():
	var screen_id = _get_first_screen_id()
	if screen_id == -1:
		pass_test("No screens available — skipping")
		return
	var track = AccordStream.create_screen_track(screen_id, 15)
	assert_not_null(track)
	assert_eq(track.get_state(), AccordMediaTrack.TRACK_STATE_LIVE)
	track.stop()

func test_screen_track_enable_disable():
	var screen_id = _get_first_screen_id()
	if screen_id == -1:
		pass_test("No screens available — skipping")
		return
	var track = AccordStream.create_screen_track(screen_id, 15)
	assert_not_null(track)

	track.set_enabled(false)
	assert_false(track.is_enabled())
	track.set_enabled(true)
	assert_true(track.is_enabled())
	track.stop()


# ========================================================================
#  Window tracks
# ========================================================================

func test_create_window_track_invalid_id():
	var track = AccordStream.create_window_track(-9999, 15)
	pass_test("create_window_track with invalid id did not crash")
	if track:
		track.stop()

func test_window_track_kind():
	var window_id = _get_first_window_id()
	if window_id == -1:
		pass_test("No windows available — skipping")
		return
	var track = AccordStream.create_window_track(window_id, 15)
	assert_not_null(track, "Should create window track")
	assert_eq(track.get_kind(), "video", "Window track kind should be 'video'")
	track.stop()

func test_window_track_initial_state_is_live():
	var window_id = _get_first_window_id()
	if window_id == -1:
		pass_test("No windows available — skipping")
		return
	var track = AccordStream.create_window_track(window_id, 15)
	assert_not_null(track)
	assert_eq(track.get_state(), AccordMediaTrack.TRACK_STATE_LIVE)
	track.stop()


# ========================================================================
#  Edge cases
# ========================================================================

func test_stop_idempotent():
	# Calling stop() twice should not crash
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)
	track.stop()
	track.stop()
	pass_test("Double stop() did not crash")

func test_set_enabled_after_stop():
	var cam_id = _get_first_camera_id()
	if cam_id == "":
		pass_test("No camera available — skipping")
		return
	var track = AccordStream.create_camera_track(cam_id, 640, 480, 30)
	assert_not_null(track)
	track.stop()
	track.set_enabled(true)
	track.set_enabled(false)
	pass_test("set_enabled after stop() did not crash")
