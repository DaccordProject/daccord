extends GutTest

## Tests for ClientConnection: is_space_connected,
## get_space_connection_status, _all_failed, disconnect_server.

var client: Node
var connection: ClientConnection


# ------------------------------------------------------------------
# Setup / teardown
# ------------------------------------------------------------------

func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client._gw = ClientGateway.new(client)
	client.fetch = ClientFetch.new(client)
	client.admin = ClientAdmin.new(client)
	client.mutations = ClientMutations.new(client)
	var UnreadClass = load("res://scripts/client/client_unread.gd")
	client.unread = UnreadClass.new(client)
	client.emoji = ClientEmoji.new(client)
	var PermClass = load(
		"res://scripts/client/client_permissions.gd"
	)
	client.permissions = PermClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me",
	}
	connection = ClientConnection.new(client)
	watch_signals(AppState)


func after_each() -> void:
	client.free()


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

func _add_connection(
	space_id: String, status: String = "connected",
) -> void:
	var idx: int = client._connections.size()
	client._connections.append({
		"space_id": space_id,
		"cdn_url": "http://cdn",
		"client": null,
		"status": status,
		"config": {"base_url": "http://test"},
		"user": client.current_user,
		"user_id": "me_1",
	})
	client._space_to_conn[space_id] = idx


func _add_channel(
	channel_id: String, space_id: String,
) -> void:
	client._channel_cache[channel_id] = {
		"id": channel_id, "space_id": space_id,
	}
	client._channel_to_space[channel_id] = space_id
	if not client._message_cache.has(channel_id):
		client._message_cache[channel_id] = []


# ==================================================================
# is_space_connected
# ==================================================================

func test_is_space_connected_true_when_connected() -> void:
	_add_connection("g_1", "connected")
	assert_true(client.is_space_connected("g_1"))


func test_is_space_connected_false_when_error() -> void:
	_add_connection("g_1", "error")
	assert_false(client.is_space_connected("g_1"))


func test_is_space_connected_false_when_connecting() -> void:
	_add_connection("g_1", "connecting")
	assert_false(client.is_space_connected("g_1"))


func test_is_space_connected_false_for_unknown_space() -> void:
	assert_false(client.is_space_connected("g_unknown"))


# ==================================================================
# get_space_connection_status
# ==================================================================

func test_get_status_returns_connected() -> void:
	_add_connection("g_1", "connected")
	assert_eq(
		client.get_space_connection_status("g_1"), "connected"
	)


func test_get_status_returns_error() -> void:
	_add_connection("g_1", "error")
	assert_eq(
		client.get_space_connection_status("g_1"), "error"
	)


func test_get_status_returns_none_for_unknown() -> void:
	assert_eq(
		client.get_space_connection_status("g_x"), "none"
	)


# ==================================================================
# _all_failed
# ==================================================================

func test_all_failed_true_when_all_error() -> void:
	_add_connection("g_1", "error")
	_add_connection("g_2", "error")
	assert_true(client._all_failed())


func test_all_failed_false_when_one_connected() -> void:
	_add_connection("g_1", "error")
	_add_connection("g_2", "connected")
	assert_false(client._all_failed())


func test_all_failed_true_when_empty() -> void:
	# No connections → all (vacuously) failed
	assert_true(client._all_failed())


func test_all_failed_true_when_null_slots() -> void:
	client._connections = [null, null]
	assert_true(client._all_failed())


# ==================================================================
# disconnect_server — cache cleanup
# ==================================================================

func test_disconnect_server_removes_space_cache() -> void:
	_add_connection("g_1")
	client._space_cache["g_1"] = {"id": "g_1"}
	connection.disconnect_server("g_1")
	assert_false(client._space_cache.has("g_1"))


func test_disconnect_server_removes_space_to_conn() -> void:
	_add_connection("g_1")
	connection.disconnect_server("g_1")
	assert_false(client._space_to_conn.has("g_1"))


func test_disconnect_server_removes_channel_cache() -> void:
	_add_connection("g_1")
	_add_channel("c_1", "g_1")
	connection.disconnect_server("g_1")
	assert_false(client._channel_cache.has("c_1"))
	assert_false(client._channel_to_space.has("c_1"))


func test_disconnect_server_removes_message_cache() -> void:
	_add_connection("g_1")
	_add_channel("c_1", "g_1")
	client._message_cache["c_1"] = [{"id": "m_1"}]
	client._message_id_index["m_1"] = "c_1"
	connection.disconnect_server("g_1")
	assert_false(client._message_cache.has("c_1"))
	assert_false(client._message_id_index.has("m_1"))


func test_disconnect_server_removes_member_cache() -> void:
	_add_connection("g_1")
	client._member_cache["g_1"] = [{"id": "u_1"}]
	connection.disconnect_server("g_1")
	assert_false(client._member_cache.has("g_1"))


func test_disconnect_server_removes_role_cache() -> void:
	_add_connection("g_1")
	client._role_cache["g_1"] = [{"id": "r_1"}]
	connection.disconnect_server("g_1")
	assert_false(client._role_cache.has("g_1"))


func test_disconnect_server_unknown_space_no_crash() -> void:
	connection.disconnect_server("g_nonexistent")
	# Should not crash — nothing to do


func test_disconnect_server_emits_spaces_updated() -> void:
	_add_connection("g_1")
	connection.disconnect_server("g_1")
	assert_signal_emitted(AppState, "spaces_updated")


func test_disconnect_server_emits_server_removed() -> void:
	_add_connection("g_1")
	connection.disconnect_server("g_1")
	assert_signal_emitted_with_parameters(
		AppState, "server_removed", ["g_1"]
	)
