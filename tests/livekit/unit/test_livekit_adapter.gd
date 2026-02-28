extends GutTest

## Unit tests for LiveKitAdapter.
## These test the adapter's state machine, mute/deafen logic,
## and signal surface without requiring a real LiveKit server.

var _adapter: LiveKitAdapter


func before_each() -> void:
	_adapter = LiveKitAdapter.new()
	add_child_autofree(_adapter)


func test_initial_state_is_disconnected() -> void:
	assert_eq(
		_adapter.get_session_state(),
		LiveKitAdapter.State.DISCONNECTED,
		"Initial state should be DISCONNECTED",
	)


func test_is_muted_default_false() -> void:
	assert_false(
		_adapter.is_muted(),
		"Should not be muted by default",
	)


func test_is_deafened_default_false() -> void:
	assert_false(
		_adapter.is_deafened(),
		"Should not be deafened by default",
	)


func test_set_muted_updates_state() -> void:
	_adapter.set_muted(true)
	assert_true(
		_adapter.is_muted(),
		"Should be muted after set_muted(true)",
	)
	_adapter.set_muted(false)
	assert_false(
		_adapter.is_muted(),
		"Should not be muted after set_muted(false)",
	)


func test_set_deafened_updates_state() -> void:
	_adapter.set_deafened(true)
	assert_true(
		_adapter.is_deafened(),
		"Should be deafened after set_deafened(true)",
	)
	_adapter.set_deafened(false)
	assert_false(
		_adapter.is_deafened(),
		"Should not be deafened after set_deafened(false)",
	)


func test_disconnect_voice_from_disconnected() -> void:
	# Should not error when called while already disconnected
	_adapter.disconnect_voice()
	assert_eq(
		_adapter.get_session_state(),
		LiveKitAdapter.State.DISCONNECTED,
		"Should remain DISCONNECTED",
	)


func test_has_required_signals() -> void:
	assert_true(
		_adapter.has_signal("session_state_changed"),
		"Missing session_state_changed signal",
	)
	assert_true(
		_adapter.has_signal("peer_joined"),
		"Missing peer_joined signal",
	)
	assert_true(
		_adapter.has_signal("peer_left"),
		"Missing peer_left signal",
	)
	assert_true(
		_adapter.has_signal("track_received"),
		"Missing track_received signal",
	)
	assert_true(
		_adapter.has_signal("track_removed"),
		"Missing track_removed signal",
	)
	assert_true(
		_adapter.has_signal("audio_level_changed"),
		"Missing audio_level_changed signal",
	)


func test_disconnect_emits_state_signal() -> void:
	var states: Array = []
	_adapter.session_state_changed.connect(func(s: int) -> void:
		states.append(s)
	)
	_adapter.disconnect_voice()
	assert_true(
		states.has(LiveKitAdapter.State.DISCONNECTED),
		"disconnect_voice should emit DISCONNECTED state",
	)


func test_unpublish_camera_without_room() -> void:
	# Should not error when no room is active
	_adapter.unpublish_camera()
	assert_eq(
		_adapter.get_session_state(),
		LiveKitAdapter.State.DISCONNECTED,
		"Should remain DISCONNECTED after unpublish_camera with no room",
	)


func test_unpublish_screen_without_room() -> void:
	# Should not error when no room is active
	_adapter.unpublish_screen()
	assert_eq(
		_adapter.get_session_state(),
		LiveKitAdapter.State.DISCONNECTED,
		"Should remain DISCONNECTED after unpublish_screen with no room",
	)


func test_connect_to_room_preserves_screen_capture() -> void:
	# Reproduces the bug where starting a screen share triggers a
	# voice_server_update from the gateway, which calls connect_to_room(),
	# which calls disconnect_voice(), destroying the screen capture.
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	if monitors.is_empty():
		pending("No monitor available — skipping")
		return

	var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitors[0])
	var preview := LiveKitAdapter.LocalVideoPreview.new()
	assert_not_null(capture, "capture should be created")

	# Simulate an active screen share by setting the adapter's internal state.
	_adapter._screen_capture = capture
	_adapter._screen_preview = preview

	# First connect_to_room creates the room (no prior room to disconnect).
	_adapter.connect_to_room("ws://127.0.0.1:1/noop", "dummy")
	assert_same(
		_adapter._screen_capture, capture,
		"Screen capture should survive first connect_to_room",
	)
	assert_same(
		_adapter._screen_preview, preview,
		"Screen preview should survive first connect_to_room",
	)

	# Second connect_to_room triggers disconnect_voice() on the existing room.
	# This is the path that was destroying screen capture before the fix.
	_adapter.connect_to_room("ws://127.0.0.1:1/noop", "dummy2")
	assert_same(
		_adapter._screen_capture, capture,
		"Screen capture should survive reconnection",
	)
	assert_same(
		_adapter._screen_preview, preview,
		"Screen preview should survive reconnection",
	)

	# Clean up
	_adapter.disconnect_voice()
	capture.close()


func test_disconnect_voice_destroys_screen_capture() -> void:
	# Explicit disconnect_voice() (leaving voice) SHOULD destroy screen
	# resources — only connect_to_room (reconnection) should preserve them.
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	if monitors.is_empty():
		pending("No monitor available — skipping")
		return

	var capture: LiveKitScreenCapture = LiveKitScreenCapture.create_for_monitor(monitors[0])
	var preview := LiveKitAdapter.LocalVideoPreview.new()
	_adapter._screen_capture = capture
	_adapter._screen_preview = preview

	_adapter.disconnect_voice()
	assert_null(
		_adapter._screen_capture,
		"disconnect_voice should destroy screen capture",
	)
	assert_null(
		_adapter._screen_preview,
		"disconnect_voice should destroy screen preview",
	)
