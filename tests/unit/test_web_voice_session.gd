extends GutTest

## Unit tests for WebVoiceSession.
##
## JavaScriptBridge is unavailable in the GUT test runner (non-web build),
## so we test the public API on the non-web code paths directly and drive
## state-machine transitions by calling the internal JS-callback handlers,
## which are ordinary GDScript functions despite the underscore prefix.

var wvs: WebVoiceSession


func before_each() -> void:
	wvs = WebVoiceSession.new()
	add_child(wvs)
	watch_signals(wvs)


func after_each() -> void:
	if is_instance_valid(wvs):
		remove_child(wvs)
		wvs.queue_free()


# -----------------------------------------------------------------------
# Signal declarations
# -----------------------------------------------------------------------

func test_signal_session_state_changed_declared() -> void:
	assert_true(wvs.has_signal("session_state_changed"))


func test_signal_peer_joined_declared() -> void:
	assert_true(wvs.has_signal("peer_joined"))


func test_signal_peer_left_declared() -> void:
	assert_true(wvs.has_signal("peer_left"))


func test_signal_track_received_declared() -> void:
	assert_true(wvs.has_signal("track_received"))


func test_signal_audio_level_changed_declared() -> void:
	assert_true(wvs.has_signal("audio_level_changed"))


# -----------------------------------------------------------------------
# Initial state
# -----------------------------------------------------------------------

func test_initial_state_is_disconnected() -> void:
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.DISCONNECTED
	)


func test_initial_is_muted_false() -> void:
	assert_false(wvs.is_muted())


func test_initial_is_deafened_false() -> void:
	assert_false(wvs.is_deafened())


# -----------------------------------------------------------------------
# Mute API
# -----------------------------------------------------------------------

func test_set_muted_true_returns_true_from_is_muted() -> void:
	wvs.set_muted(true)
	assert_true(wvs.is_muted())


func test_set_muted_false_returns_false_from_is_muted() -> void:
	wvs.set_muted(true)
	wvs.set_muted(false)
	assert_false(wvs.is_muted())


func test_set_muted_toggle_multiple_times() -> void:
	wvs.set_muted(true)
	wvs.set_muted(true)
	assert_true(wvs.is_muted())
	wvs.set_muted(false)
	assert_false(wvs.is_muted())


# -----------------------------------------------------------------------
# Deafen API
# -----------------------------------------------------------------------

func test_set_deafened_true_returns_true_from_is_deafened() -> void:
	wvs.set_deafened(true)
	assert_true(wvs.is_deafened())


func test_set_deafened_false_returns_false_from_is_deafened() -> void:
	wvs.set_deafened(true)
	wvs.set_deafened(false)
	assert_false(wvs.is_deafened())


# -----------------------------------------------------------------------
# Non-web: connect_to_room exits cleanly
# -----------------------------------------------------------------------

func test_connect_to_room_non_web_does_not_change_state() -> void:
	# In the GUT runner OS.get_name() != "Web", so _is_web is false.
	assert_false(wvs._is_web, "Test must run in non-web environment")
	wvs.connect_to_room("ws://example.com", "token")
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.DISCONNECTED
	)


func test_connect_to_room_non_web_emits_no_signal() -> void:
	assert_false(wvs._is_web, "Test must run in non-web environment")
	wvs.connect_to_room("ws://example.com", "token")
	assert_signal_not_emitted(wvs, "session_state_changed")


# -----------------------------------------------------------------------
# Screen share: no-ops
# -----------------------------------------------------------------------

func test_publish_screen_returns_null() -> void:
	var result = wvs.publish_screen({})
	assert_null(result)


func test_publish_screen_with_source_returns_null() -> void:
	var result = wvs.publish_screen({"id": "screen:0", "name": "Screen"})
	assert_null(result)


func test_unpublish_screen_does_not_crash() -> void:
	wvs.unpublish_screen()
	# No assertion needed — test passes if no error is thrown.
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.DISCONNECTED
	)


# -----------------------------------------------------------------------
# State machine transitions (via internal JS-callback handlers)
#
# We call _on_* directly to simulate LiveKit JS events without needing a
# real JavaScriptBridge.  _room is left null so the room-access branches
# inside the callbacks are skipped safely.
# -----------------------------------------------------------------------

func test_on_connected_sets_state_connected() -> void:
	wvs._state = WebVoiceSession.State.CONNECTING
	wvs._on_connected(null)
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.CONNECTED
	)


func test_on_connected_emits_session_state_changed() -> void:
	wvs._state = WebVoiceSession.State.CONNECTING
	wvs._on_connected(null)
	assert_signal_emitted_with_parameters(
		wvs, "session_state_changed",
		[WebVoiceSession.State.CONNECTED]
	)


func test_on_disconnected_sets_state_disconnected() -> void:
	wvs._state = WebVoiceSession.State.CONNECTED
	wvs._on_disconnected(null)
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.DISCONNECTED
	)


func test_on_disconnected_emits_session_state_changed() -> void:
	wvs._state = WebVoiceSession.State.CONNECTED
	wvs._on_disconnected(null)
	assert_signal_emitted_with_parameters(
		wvs, "session_state_changed",
		[WebVoiceSession.State.DISCONNECTED]
	)


func test_on_reconnecting_sets_state_reconnecting() -> void:
	wvs._state = WebVoiceSession.State.CONNECTED
	wvs._on_reconnecting(null)
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.RECONNECTING
	)


func test_on_reconnected_sets_state_connected() -> void:
	wvs._state = WebVoiceSession.State.RECONNECTING
	wvs._on_reconnected(null)
	assert_eq(
		wvs.get_session_state(),
		WebVoiceSession.State.CONNECTED
	)


func test_state_machine_full_sequence() -> void:
	# DISCONNECTED -> CONNECTING (simulated) -> CONNECTED -> RECONNECTING -> CONNECTED
	assert_eq(wvs.get_session_state(), WebVoiceSession.State.DISCONNECTED)
	wvs._state = WebVoiceSession.State.CONNECTING
	wvs._on_connected(null)
	assert_eq(wvs.get_session_state(), WebVoiceSession.State.CONNECTED)
	wvs._on_reconnecting(null)
	assert_eq(wvs.get_session_state(), WebVoiceSession.State.RECONNECTING)
	wvs._on_reconnected(null)
	assert_eq(wvs.get_session_state(), WebVoiceSession.State.CONNECTED)
	wvs._on_disconnected(null)
	assert_eq(wvs.get_session_state(), WebVoiceSession.State.DISCONNECTED)
