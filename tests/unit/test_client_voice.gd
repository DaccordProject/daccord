extends GutTest

## Unit tests for ClientVoice.join_voice_channel() signal behaviour.
##
## Verifies that AppState.voice_joined is emitted only after a successful
## _connect_voice_backend() call, and is NOT emitted when _voice_session
## is null (DAC-79 fix).
##
## Strategy: mirrors test_client_fetch.gd — create a bare Client node via
## load().new() (skipping _ready), manually wire sub-modules, and inject a
## StubRest into AccordClient.  A StubVoiceSession is used in place of
## LiveKitAdapter / WebVoiceSession.

var client: Node
var _stub_rest: StubRest
var _accord_clients: Array = []


# ------------------------------------------------------------------
# StubRest — avoids real HTTP; same pattern as test_client_fetch.gd
# ------------------------------------------------------------------

class StubRest extends AccordRest:
	var responses: Dictionary = {}
	var calls: Array = []

	func make_request(
		method: String, path: String,
		body = null, query: Dictionary = {},
	) -> RestResult:
		calls.append({"method": method, "path": path})
		var key: String = method + " " + path
		if responses.has(key):
			return responses[key]
		return RestResult.failure(404, null)


# ------------------------------------------------------------------
# StubVoiceSession — minimal stand-in with connect_to_room()
# ------------------------------------------------------------------

class StubVoiceSession extends Node:
	signal session_state_changed(state: int)
	signal peer_joined(user_id: String)
	signal peer_left(user_id: String)
	signal track_received(user_id: String, stream)
	signal track_removed(user_id: String)
	signal audio_level_changed(user_id: String, level: float)

	var connect_to_room_called: bool = false
	var last_url: String = ""
	var last_token: String = ""

	func connect_to_room(url: String, token: String) -> void:
		connect_to_room_called = true
		last_url = url
		last_token = token

	func disconnect_voice() -> void:
		pass

	func set_muted(_muted: bool) -> void:
		pass

	func set_deafened(_deafened: bool) -> void:
		pass

	func is_muted() -> bool:
		return false

	func is_deafened() -> bool:
		return false


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func _make_accord_client() -> AccordClient:
	var ac := AccordClient.new()
	_stub_rest = StubRest.new()
	ac.users = UsersApi.new(_stub_rest)
	ac.spaces = SpacesApi.new(_stub_rest)
	ac.messages = MessagesApi.new(_stub_rest)
	ac.members = MembersApi.new(_stub_rest)
	ac.roles = RolesApi.new(_stub_rest)
	ac.voice = VoiceApi.new(_stub_rest)
	_accord_clients.append(ac)
	return ac


func _setup_connection(
	ac: AccordClient,
	space_id: String = "g_1",
	cdn_url: String = "http://cdn",
) -> void:
	client._connections = [{
		"space_id": space_id,
		"cdn_url": cdn_url,
		"client": ac,
		"status": "connected",
		"config": {"base_url": "http://test"},
		"user": client.current_user,
		"user_id": "me_1",
	}]
	client._space_to_conn = {space_id: 0}


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	# Skip _ready to avoid GDExtension deps; manually init sub-modules.
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.voice = ClientVoice.new(client)
	client.mutations = ClientMutations.new(client)
	var UnreadClass = load("res://scripts/autoload/client_unread.gd")
	client.unread = UnreadClass.new(client)
	client.emoji = ClientEmoji.new(client)
	var PermClass = load(
		"res://scripts/autoload/client_permissions.gd"
	)
	client.permissions = PermClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["me_1"] = client.current_user
	# Default: no voice session (tests override as needed).
	client._voice_session = null
	watch_signals(AppState)


func after_each() -> void:
	# Clean up AppState voice state so tests don't bleed.
	AppState.voice_channel_id = ""
	AppState.voice_space_id = ""
	for ac in _accord_clients:
		if is_instance_valid(ac):
			ac.free()
	_accord_clients.clear()
	if _stub_rest != null and is_instance_valid(_stub_rest):
		_stub_rest.free()
		_stub_rest = null
	client.free()


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _setup_voice_join_stub(channel_id: String = "c_1") -> void:
	## Configures the stub REST to return a valid AccordVoiceServerUpdate
	## for the voice join endpoint, plus an empty voice-status response so
	## the follow-up fetch_voice_states() call does not push_error.
	_stub_rest.responses[
		"POST /channels/%s/voice/join" % channel_id
	] = RestResult.success(
		200,
		{
			"space_id": "g_1",
			"channel_id": channel_id,
			"backend": "livekit",
			"livekit_url": "ws://livekit.example.com",
			"token": "test-livekit-token",
		},
	)
	_stub_rest.responses[
		"GET /channels/%s/voice-status" % channel_id
	] = RestResult.success(200, [])


# ==================================================================
# join_voice_channel — null session (DAC-79 fix)
# ==================================================================

func test_join_voice_channel_null_session_does_not_emit_voice_joined() -> void:
	## When _voice_session is null, _connect_voice_backend returns false
	## and AppState.join_voice() must never be called.
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_setup_voice_join_stub("c_1")
	client._voice_session = null

	var result: bool = await client.voice.join_voice_channel("c_1")

	assert_false(result, "Expected join to return false with null session")
	assert_signal_not_emitted(AppState, "voice_joined")


func test_join_voice_channel_null_session_leaves_voice_channel_id_empty() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_setup_voice_join_stub("c_1")
	client._voice_session = null

	await client.voice.join_voice_channel("c_1")

	assert_eq(AppState.voice_channel_id, "")


# ==================================================================
# join_voice_channel — valid session
# ==================================================================

func test_join_voice_channel_valid_session_emits_voice_joined() -> void:
	## When a StubVoiceSession is present, _connect_voice_backend succeeds
	## and AppState.join_voice() must emit voice_joined.
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_setup_voice_join_stub("c_1")

	var stub_session := StubVoiceSession.new()
	add_child(stub_session)
	client._voice_session = stub_session

	var result: bool = await client.voice.join_voice_channel("c_1")

	assert_true(result, "Expected join to return true with valid session")
	assert_signal_emitted_with_parameters(
		AppState, "voice_joined", ["c_1"]
	)

	remove_child(stub_session)
	stub_session.queue_free()


func test_join_voice_channel_valid_session_calls_connect_to_room() -> void:
	## connect_to_room is called with the LiveKit URL and token from the
	## server response.
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_setup_voice_join_stub("c_1")

	var stub_session := StubVoiceSession.new()
	add_child(stub_session)
	client._voice_session = stub_session

	await client.voice.join_voice_channel("c_1")

	assert_true(stub_session.connect_to_room_called)
	assert_eq(stub_session.last_url, "ws://livekit.example.com")
	assert_eq(stub_session.last_token, "test-livekit-token")

	remove_child(stub_session)
	stub_session.queue_free()


func test_join_voice_channel_valid_session_sets_voice_channel_id() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_setup_voice_join_stub("c_1")

	var stub_session := StubVoiceSession.new()
	add_child(stub_session)
	client._voice_session = stub_session

	await client.voice.join_voice_channel("c_1")

	assert_eq(AppState.voice_channel_id, "c_1")

	remove_child(stub_session)
	stub_session.queue_free()


# ==================================================================
# join_voice_channel — REST failure
# ==================================================================

func test_join_voice_channel_rest_failure_does_not_emit_voice_joined() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._channel_to_space["c_1"] = "g_1"
	_stub_rest.responses["POST /channels/c_1/voice/join"] = (
		RestResult.failure(500, null)
	)
	var stub_session := StubVoiceSession.new()
	add_child(stub_session)
	client._voice_session = stub_session

	var result: bool = await client.voice.join_voice_channel("c_1")

	assert_false(result)
	assert_signal_not_emitted(AppState, "voice_joined")

	remove_child(stub_session)
	stub_session.queue_free()


func test_join_voice_channel_no_connection_does_not_emit_voice_joined() -> void:
	## No connections set up → _client_for_channel returns null.
	client._channel_to_space["c_1"] = "g_1"
	var stub_session := StubVoiceSession.new()
	add_child(stub_session)
	client._voice_session = stub_session

	var result: bool = await client.voice.join_voice_channel("c_1")

	assert_false(result)
	assert_signal_not_emitted(AppState, "voice_joined")

	remove_child(stub_session)
	stub_session.queue_free()
