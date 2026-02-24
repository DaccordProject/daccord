extends GutTest

## Smoke tests for the Client autoload _ready() startup path.
##
## These tests exercise the full startup path to catch:
## - LiveKitAdapter instantiation failures
## - Signal wiring errors between voice session and ClientVoice
## - Sub-module construction failures in _ready()


# ClientVoice is the sub-module most likely to break when
# voice-related code changes.
func test_client_voice_instantiates() -> void:
	var mock := Node.new()
	add_child_autofree(mock)
	var voice := ClientVoice.new(mock)
	assert_not_null(
		voice, "ClientVoice failed to instantiate"
	)


# Core smoke test: add_child triggers _ready() which creates
# all sub-modules and wires up LiveKitAdapter signals.
func test_client_ready_creates_sub_modules() -> void:
	var client = load(
		"res://scripts/autoload/client.gd"
	).new()
	add_child_autofree(client)
	assert_not_null(
		client._gw, "ClientGateway not created"
	)
	assert_not_null(
		client.fetch, "ClientFetch not created"
	)
	assert_not_null(
		client.admin, "ClientAdmin not created"
	)
	assert_not_null(
		client.voice, "ClientVoice not created"
	)
	assert_not_null(
		client.mutations, "ClientMutations not created"
	)


# Verify LiveKitAdapter is created and attached as child.
func test_client_ready_creates_voice_session() -> void:
	var client = load(
		"res://scripts/autoload/client.gd"
	).new()
	add_child_autofree(client)
	assert_not_null(
		client._voice_session,
		"Voice session is null",
	)
	assert_true(
		client._voice_session is LiveKitAdapter,
		"Voice session is wrong type",
	)
	assert_true(
		client._voice_session.get_parent() == client,
		"Voice session not a child of Client",
	)


# Verify voice session signals are connected to ClientVoice.
func test_client_ready_wires_voice_signals() -> void:
	var client = load(
		"res://scripts/autoload/client.gd"
	).new()
	add_child_autofree(client)
	var session: LiveKitAdapter = client._voice_session
	assert_true(
		session.session_state_changed.is_connected(
			client.voice.on_session_state_changed
		),
		"session_state_changed not connected",
	)
	assert_true(
		session.peer_joined.is_connected(
			client.voice.on_peer_joined
		),
		"peer_joined not connected",
	)
	assert_true(
		session.peer_left.is_connected(
			client.voice.on_peer_left
		),
		"peer_left not connected",
	)
	assert_true(
		session.track_received.is_connected(
			client.voice.on_track_received
		),
		"track_received not connected",
	)
	assert_true(
		session.audio_level_changed.is_connected(
			client.voice.on_audio_level_changed
		),
		"audio_level_changed not connected",
	)


# Verify AppState.channel_selected is connected.
func test_client_ready_connects_app_state() -> void:
	var client = load(
		"res://scripts/autoload/client.gd"
	).new()
	add_child_autofree(client)
	assert_true(
		AppState.channel_selected.is_connected(
			client._on_channel_selected_clear_unread
		),
		"channel_selected not connected",
	)


# Verify post-_ready() initial state.
func test_client_ready_initial_state() -> void:
	var client = load(
		"res://scripts/autoload/client.gd"
	).new()
	add_child_autofree(client)
	assert_eq(
		client.mode,
		client.Mode.CONNECTING,
		"Initial mode should be CONNECTING",
	)
	assert_true(
		client.current_user.is_empty(),
		"current_user should be empty before login",
	)
