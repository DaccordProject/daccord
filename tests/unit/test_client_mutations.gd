extends GutTest

## Tests for ClientMutations: send_message_to_channel,
## update_message_content, remove_message, update_presence.

var client: Node
var mutations: ClientMutations
var _stub_rest: StubRest
var _accord_clients: Array = []


# ------------------------------------------------------------------
# StubRest -- replaces AccordRest to avoid real HTTP
# ------------------------------------------------------------------

class StubRest extends AccordRest:
	## Maps "METHOD /path" -> RestResult.
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


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.mutations = ClientMutations.new(client)
	var UnreadClass = load("res://scripts/autoload/client_unread.gd")
	client.unread = UnreadClass.new(client)
	client.emoji = ClientEmoji.new(client)
	var PermClass = load(
		"res://scripts/autoload/client_permissions.gd"
	)
	client.permissions = PermClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me",
		"status": ClientModels.UserStatus.ONLINE,
	}
	client._user_cache["me_1"] = client.current_user
	mutations = client.mutations
	watch_signals(AppState)


func after_each() -> void:
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

func _setup_connection(
	ac: AccordClient,
	space_id: String = "g_1",
) -> void:
	client._connections = [{
		"space_id": space_id,
		"cdn_url": "http://cdn",
		"client": ac,
		"status": "connected",
		"config": {"base_url": "http://test"},
		"user": client.current_user,
		"user_id": "me_1",
	}]
	client._space_to_conn = {space_id: 0}


func _setup_channel(
	channel_id: String, space_id: String = "g_1",
) -> void:
	client._channel_to_space[channel_id] = space_id
	client._channel_cache[channel_id] = {
		"id": channel_id, "space_id": space_id,
	}


func _seed_message(
	channel_id: String, message_id: String,
) -> void:
	if not client._message_cache.has(channel_id):
		client._message_cache[channel_id] = []
	client._message_cache[channel_id].append({
		"id": message_id,
		"content": "hello",
		"author": {"id": "me_1"},
	})
	client._message_id_index[message_id] = channel_id


# ==================================================================
# send_message_to_channel — null client guard
# ==================================================================

func test_send_message_null_client_emits_failed() -> void:
	# No connection registered → _client_for_channel returns null
	await mutations.send_message_to_channel("c_x", "hi")
	assert_signal_emitted(AppState, "message_send_failed")


func test_send_message_null_client_returns_false() -> void:
	var ok: bool = await mutations.send_message_to_channel(
		"c_x", "hi"
	)
	assert_false(ok)


# ==================================================================
# send_message_to_channel — REST error path
# ==================================================================

func test_send_message_rest_error_emits_failed() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac)
	_setup_channel("c_1")
	_stub_rest.responses["POST /channels/c_1/messages"] = \
		RestResult.failure(500, null)
	await mutations.send_message_to_channel("c_1", "hello")
	assert_signal_emitted(AppState, "message_send_failed")


func test_send_message_rest_error_signal_has_channel_id() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac)
	_setup_channel("c_1")
	_stub_rest.responses["POST /channels/c_1/messages"] = \
		RestResult.failure(500, null)
	await mutations.send_message_to_channel("c_1", "hello")
	assert_signal_emitted_with_parameters(
		AppState, "message_send_failed",
		["c_1", "hello", "unknown"]
	)


func test_send_message_rest_error_returns_false() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac)
	_setup_channel("c_1")
	_stub_rest.responses["POST /channels/c_1/messages"] = \
		RestResult.failure(500, null)
	var ok: bool = await mutations.send_message_to_channel(
		"c_1", "hello"
	)
	assert_false(ok)


# ==================================================================
# update_message_content — null client guard
# ==================================================================

func test_update_message_no_channel_emits_edit_failed() -> void:
	# Message not in any cache → _find_channel_for_message returns ""
	await mutations.update_message_content("m_x", "new")
	assert_signal_emitted(AppState, "message_edit_failed")


func test_update_message_null_client_emits_edit_failed() -> void:
	# Channel routed but no connection → _client_for_channel null
	_seed_message("c_orphan", "m_1")
	# Don't set up a connection → client is null for c_orphan
	await mutations.update_message_content("m_1", "new")
	assert_signal_emitted(AppState, "message_edit_failed")


func test_update_message_null_client_returns_false() -> void:
	_seed_message("c_orphan", "m_1")
	var ok: bool = await mutations.update_message_content(
		"m_1", "new"
	)
	assert_false(ok)


# ==================================================================
# remove_message — null client guard
# ==================================================================

func test_remove_message_no_channel_emits_delete_failed() -> void:
	await mutations.remove_message("m_missing")
	assert_signal_emitted(AppState, "message_delete_failed")


func test_remove_message_null_client_emits_delete_failed() -> void:
	_seed_message("c_orphan", "m_2")
	await mutations.remove_message("m_2")
	assert_signal_emitted(AppState, "message_delete_failed")


func test_remove_message_null_client_returns_false() -> void:
	_seed_message("c_orphan", "m_2")
	var ok: bool = await mutations.remove_message("m_2")
	assert_false(ok)


# ==================================================================
# update_presence
# ==================================================================

func test_update_presence_sets_current_user_status() -> void:
	mutations.update_presence(ClientModels.UserStatus.DND)
	assert_eq(
		client.current_user["status"],
		ClientModels.UserStatus.DND
	)


func test_update_presence_emits_user_updated() -> void:
	mutations.update_presence(ClientModels.UserStatus.IDLE)
	assert_signal_emitted_with_parameters(
		AppState, "user_updated", ["me_1"]
	)


func test_update_presence_updates_user_cache() -> void:
	mutations.update_presence(ClientModels.UserStatus.OFFLINE)
	assert_eq(
		client._user_cache["me_1"]["status"],
		ClientModels.UserStatus.OFFLINE
	)
