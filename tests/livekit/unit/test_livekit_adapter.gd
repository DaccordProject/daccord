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
