extends GutTest

var _session: AccordVoiceSession


func before_each():
	_session = AccordVoiceSession.new()
	add_child(_session)


func after_each():
	if _session:
		_session.disconnect_voice()
		_session.queue_free()
		_session = null


# ========================================================================
#  Initial state
# ========================================================================

func test_initial_state_is_disconnected():
	assert_eq(_session.get_session_state(), AccordVoiceSession.DISCONNECTED,
			  "Initial session state should be DISCONNECTED")


func test_initial_muted_is_false():
	assert_false(_session.is_muted(), "Should not be muted initially")


func test_initial_deafened_is_false():
	assert_false(_session.is_deafened(), "Should not be deafened initially")


func test_initial_peers_is_empty_array():
	var peers = _session.get_peers()
	assert_typeof(peers, TYPE_ARRAY, "get_peers() should return an Array")
	assert_eq(peers.size(), 0, "No peers initially")


func test_initial_peer_details_is_empty_array():
	var details = _session.get_peer_details()
	assert_typeof(details, TYPE_ARRAY, "get_peer_details() should return an Array")
	assert_eq(details.size(), 0, "No peer details initially")


func test_initial_channel_id_is_empty():
	assert_eq(_session.get_channel_id(), "", "Channel ID should be empty initially")


# ========================================================================
#  Mute / unmute
# ========================================================================

func test_set_muted_true():
	_session.set_muted(true)
	assert_true(_session.is_muted(), "Should be muted after set_muted(true)")


func test_set_muted_false():
	_session.set_muted(true)
	_session.set_muted(false)
	assert_false(_session.is_muted(), "Should be unmuted after set_muted(false)")


func test_muted_property():
	_session.muted = true
	assert_true(_session.muted, "Property 'muted' should reflect set value")
	_session.muted = false
	assert_false(_session.muted, "Property 'muted' should reflect set value")


# ========================================================================
#  Deafen / undeafen
# ========================================================================

func test_set_deafened_true():
	_session.set_deafened(true)
	assert_true(_session.is_deafened(), "Should be deafened after set_deafened(true)")


func test_set_deafened_false():
	_session.set_deafened(true)
	_session.set_deafened(false)
	assert_false(_session.is_deafened(), "Should be undeafened after set_deafened(false)")


func test_deafened_property():
	_session.deafened = true
	assert_true(_session.deafened, "Property 'deafened' should reflect set value")
	_session.deafened = false
	assert_false(_session.deafened, "Property 'deafened' should reflect set value")


# ========================================================================
#  Disconnect when not connected
# ========================================================================

func test_disconnect_when_not_connected_does_not_crash():
	_session.disconnect_voice()
	assert_eq(_session.get_session_state(), AccordVoiceSession.DISCONNECTED,
			  "Should remain DISCONNECTED")
	pass_test("disconnect_voice() when not connected did not crash")


func test_disconnect_is_idempotent():
	_session.disconnect_voice()
	_session.disconnect_voice()
	assert_eq(_session.get_session_state(), AccordVoiceSession.DISCONNECTED)
	pass_test("Double disconnect_voice() did not crash")


# ========================================================================
#  Audio level poll interval
# ========================================================================

func test_default_poll_interval():
	assert_almost_eq(_session.get_audio_level_poll_interval(), 0.05, 0.001,
					 "Default poll interval should be ~50ms")


func test_set_poll_interval():
	_session.set_audio_level_poll_interval(0.1)
	assert_almost_eq(_session.get_audio_level_poll_interval(), 0.1, 0.001,
					 "Poll interval should be 100ms after set")


func test_poll_interval_property():
	_session.audio_level_poll_interval = 0.2
	assert_almost_eq(_session.audio_level_poll_interval, 0.2, 0.001,
					 "Property should reflect set value")


func test_poll_interval_clamps_to_minimum():
	_session.set_audio_level_poll_interval(-1.0)
	assert_gt(_session.get_audio_level_poll_interval(), 0.0,
			  "Poll interval should be clamped to > 0")


# ========================================================================
#  Enum constants accessible
# ========================================================================

func test_session_state_enum_values():
	assert_eq(AccordVoiceSession.DISCONNECTED, 0)
	assert_eq(AccordVoiceSession.CONNECTING, 1)
	assert_eq(AccordVoiceSession.CONNECTED, 2)
	assert_eq(AccordVoiceSession.RECONNECTING, 3)
	assert_eq(AccordVoiceSession.FAILED, 4)


# ========================================================================
#  handle_voice_signal when not connected
# ========================================================================

func test_handle_voice_signal_when_not_connected_does_not_crash():
	_session.handle_voice_signal("user_123", "answer", {"sdp": "v=0\r\n", "type": "answer"})
	pass_test("handle_voice_signal when not connected did not crash")


# ========================================================================
#  LiveKit stub
# ========================================================================

func test_connect_livekit_does_not_crash():
	_session.connect_livekit("wss://example.com", "fake-token")
	# Should print a warning but not crash
	assert_eq(_session.get_session_state(), AccordVoiceSession.DISCONNECTED,
			  "State should remain DISCONNECTED for unimplemented LiveKit backend")
	pass_test("connect_livekit() stub did not crash")


# ========================================================================
#  Signal existence
# ========================================================================

func test_signal_peer_joined_exists():
	assert_true(_session.has_signal("peer_joined"),
				"AccordVoiceSession should have peer_joined signal")


func test_signal_peer_left_exists():
	assert_true(_session.has_signal("peer_left"),
				"AccordVoiceSession should have peer_left signal")


func test_signal_audio_level_changed_exists():
	assert_true(_session.has_signal("audio_level_changed"),
				"AccordVoiceSession should have audio_level_changed signal")


func test_signal_session_state_changed_exists():
	assert_true(_session.has_signal("session_state_changed"),
				"AccordVoiceSession should have session_state_changed signal")


func test_signal_outgoing_exists():
	assert_true(_session.has_signal("signal_outgoing"),
				"AccordVoiceSession should have signal_outgoing signal")


# ========================================================================
#  Mute / deafen interaction
# ========================================================================

func test_deafen_while_unmuted_then_undeafen_stays_unmuted():
	_session.set_muted(false)
	_session.set_deafened(true)
	assert_true(_session.is_deafened())
	assert_false(_session.is_muted(), "Deafening should not change muted property")

	_session.set_deafened(false)
	assert_false(_session.is_muted(), "Undeafening should leave mute state unchanged")


func test_deafen_while_muted_then_undeafen_stays_muted():
	_session.set_muted(true)
	_session.set_deafened(true)
	assert_true(_session.is_deafened())
	assert_true(_session.is_muted(), "Muted state should persist through deafen")

	_session.set_deafened(false)
	assert_true(_session.is_muted(), "Should still be muted after undeafening")


func test_mute_unmute_while_deafened():
	_session.set_deafened(true)
	_session.set_muted(true)
	assert_true(_session.is_muted())
	_session.set_muted(false)
	assert_false(_session.is_muted())
	assert_true(_session.is_deafened(), "Deafen state should be independent of mute toggle")


# ========================================================================
#  handle_voice_signal with different signal types
# ========================================================================

func test_handle_voice_signal_answer_when_not_connected():
	_session.handle_voice_signal("user_1", "answer",
		{"sdp": "v=0\r\n", "type": "answer"})
	pass_test("handle_voice_signal 'answer' when not connected did not crash")


func test_handle_voice_signal_ice_candidate_when_not_connected():
	_session.handle_voice_signal("user_1", "ice_candidate",
		{"mid": "audio", "index": 0, "sdp": "candidate:1 1 udp 2122260223 192.168.1.1 12345 typ host"})
	pass_test("handle_voice_signal 'ice_candidate' when not connected did not crash")


func test_handle_voice_signal_peer_joined_when_not_connected():
	_session.handle_voice_signal("user_42", "peer_joined", {})
	pass_test("handle_voice_signal 'peer_joined' when not connected did not crash")


func test_handle_voice_signal_peer_left_when_not_connected():
	_session.handle_voice_signal("user_42", "peer_left", {})
	pass_test("handle_voice_signal 'peer_left' when not connected did not crash")


func test_handle_voice_signal_unknown_type_when_not_connected():
	_session.handle_voice_signal("user_1", "unknown_type", {"foo": "bar"})
	pass_test("handle_voice_signal unknown type when not connected did not crash")


# ========================================================================
#  connect_custom_sfu
# ========================================================================

func test_connect_custom_sfu_transitions_state():
	var ice_config = {"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
	var mics = AccordStream.get_microphones()
	var mic_id = mics[0]["id"] if mics.size() > 0 else ""

	_session.connect_custom_sfu("test-endpoint", ice_config, mic_id)

	# State should no longer be DISCONNECTED (either CONNECTING or FAILED
	# depending on whether WebRTC context is available)
	var state = _session.get_session_state()
	assert_ne(state, AccordVoiceSession.DISCONNECTED,
			  "State should change after connect_custom_sfu()")


func test_connect_custom_sfu_sets_channel_id():
	var ice_config = {"ice_servers": []}
	var mics = AccordStream.get_microphones()
	var mic_id = mics[0]["id"] if mics.size() > 0 else ""

	_session.connect_custom_sfu("my-channel-endpoint", ice_config, mic_id)
	assert_eq(_session.get_channel_id(), "my-channel-endpoint",
			  "Channel ID should be set to the endpoint")


func test_connect_custom_sfu_while_already_connected_does_not_crash():
	var ice_config = {"ice_servers": []}
	_session.connect_custom_sfu("endpoint-1", ice_config, "")
	# Calling again while already connecting/connected should be safe
	_session.connect_custom_sfu("endpoint-2", ice_config, "")
	pass_test("Double connect_custom_sfu did not crash")


func test_disconnect_after_connect_custom_sfu():
	var ice_config = {"ice_servers": []}
	_session.connect_custom_sfu("test-endpoint", ice_config, "")
	_session.disconnect_voice()
	assert_eq(_session.get_session_state(), AccordVoiceSession.DISCONNECTED,
			  "State should be DISCONNECTED after disconnect")
	assert_eq(_session.get_channel_id(), "",
			  "Channel ID should be empty after disconnect")


func test_connect_custom_sfu_emits_session_state_changed():
	watch_signals(_session)
	var ice_config = {"ice_servers": [{"urls": ["stun:stun.l.google.com:19302"]}]}
	var mics = AccordStream.get_microphones()
	var mic_id = mics[0]["id"] if mics.size() > 0 else ""

	_session.connect_custom_sfu("test-endpoint", ice_config, mic_id)

	# Wait for deferred signal emission
	await get_tree().create_timer(1.0).timeout
	assert_signal_emitted(_session, "session_state_changed",
						  "connect_custom_sfu should emit session_state_changed")
