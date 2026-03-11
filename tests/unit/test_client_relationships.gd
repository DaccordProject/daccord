extends GutTest

## Tests for ClientRelationships methods.
##
## Strategy: mirror the StubRest pattern from test_client_fetch.gd.
## Instantiate Client via load().new() (skipping _ready), manually init
## sub-modules, inject a StubRest into AccordClient, and test
## ClientRelationships methods directly.

var client: Node
var rel_obj: ClientRelationships
var _stub_rest: StubRest
var _accord_clients: Array = []


# ------------------------------------------------------------------
# StubRest
# ------------------------------------------------------------------

class StubRest extends AccordRest:
	var responses: Dictionary = {}
	var calls: Array = []

	func make_request(
		method: String, path: String,
		body = null, query: Dictionary = {},
	) -> RestResult:
		calls.append({"method": method, "path": path, "query": query})
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
	var PermClass = load("res://scripts/autoload/client_permissions.gd")
	client.permissions = PermClass.new(client)
	var RelClass = load("res://scripts/autoload/client_relationships.gd")
	client.relationships = RelClass.new(client)
	client.current_user = {
		"id": "me_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["me_1"] = client.current_user
	rel_obj = client.relationships
	# Clear friend book to isolate tests
	Config.save_friend_book([])
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


func _rel_dict(user_id: String, rel_type: int) -> Dictionary:
	return {
		"id": "rel_" + user_id,
		"type": rel_type,
		"since": "2025-01-01T00:00:00Z",
		"user": {
			"id": user_id,
			"username": "user_" + user_id,
			"display_name": "User " + user_id,
		},
	}


func _seed_cache(entries: Array) -> void:
	## Populate _relationship_cache directly (keyed as "0:user_id").
	for i in entries.size():
		var d: Dictionary = entries[i]
		var uid: String = d["user"].get("id", "")
		client._relationship_cache["0:" + uid] = d


# ==================================================================
# fetch_relationships
# ==================================================================

func test_fetch_relationships_populates_cache() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/relationships"] = \
		RestResult.success(200, [_rel_dict("u_1", 1)])
	await rel_obj.fetch_relationships()
	assert_eq(client._relationship_cache.size(), 1)
	assert_signal_emitted(AppState, "relationships_updated")


func test_fetch_relationships_emits_signal_always() -> void:
	# No connections — still emits
	await rel_obj.fetch_relationships()
	assert_signal_emitted(AppState, "relationships_updated")


func test_fetch_relationships_skips_disconnected() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	client._connections[0]["status"] = "disconnected"
	await rel_obj.fetch_relationships()
	assert_eq(client._relationship_cache.size(), 0)
	assert_signal_emitted(AppState, "relationships_updated")


func test_fetch_relationships_skips_null_client() -> void:
	client._connections = [{
		"space_id": "g_1",
		"cdn_url": "http://cdn",
		"client": null,
		"status": "connected",
	}]
	await rel_obj.fetch_relationships()
	assert_eq(client._relationship_cache.size(), 0)


func test_fetch_relationships_api_failure_no_cache_entry() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/relationships"] = \
		RestResult.failure(500, null)
	await rel_obj.fetch_relationships()
	assert_eq(client._relationship_cache.size(), 0)
	assert_signal_emitted(AppState, "relationships_updated")


func test_fetch_relationships_stores_type() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["GET /users/@me/relationships"] = \
		RestResult.success(200, [
			_rel_dict("u_friend", 1),
			_rel_dict("u_blocked", 2),
		])
	await rel_obj.fetch_relationships()
	assert_eq(client._relationship_cache.size(), 2)
	var found_type1: bool = false
	var found_type2: bool = false
	for d in client._relationship_cache.values():
		if d["type"] == 1:
			found_type1 = true
		if d["type"] == 2:
			found_type2 = true
	assert_true(found_type1)
	assert_true(found_type2)


# ==================================================================
# get_relationship
# ==================================================================

func test_get_relationship_returns_matching_entry() -> void:
	_seed_cache([_rel_dict("u_1", 1)])
	var rel: Variant = rel_obj.get_relationship("u_1")
	assert_not_null(rel)
	assert_eq((rel as Dictionary)["type"], 1)


func test_get_relationship_returns_null_when_not_found() -> void:
	_seed_cache([_rel_dict("u_1", 1)])
	var rel: Variant = rel_obj.get_relationship("u_nonexistent")
	assert_null(rel)


func test_get_relationship_empty_cache_returns_null() -> void:
	var rel: Variant = rel_obj.get_relationship("u_1")
	assert_null(rel)


# ==================================================================
# is_user_blocked
# ==================================================================

func test_is_user_blocked_true_for_type2() -> void:
	_seed_cache([_rel_dict("u_bad", 2)])
	assert_true(rel_obj.is_user_blocked("u_bad"))


func test_is_user_blocked_false_for_type1() -> void:
	_seed_cache([_rel_dict("u_friend", 1)])
	assert_false(rel_obj.is_user_blocked("u_friend"))


func test_is_user_blocked_false_when_not_found() -> void:
	assert_false(rel_obj.is_user_blocked("u_nobody"))


# ==================================================================
# get_friends / get_blocked / get_pending_incoming / get_pending_outgoing
# ==================================================================

func test_get_friends_filters_type1() -> void:
	_seed_cache([
		_rel_dict("u_friend", 1),
		_rel_dict("u_blocked", 2),
		_rel_dict("u_incoming", 3),
	])
	var friends: Array = rel_obj.get_friends()
	assert_eq(friends.size(), 1)
	assert_eq(friends[0]["type"], 1)


func test_get_blocked_filters_type2() -> void:
	_seed_cache([
		_rel_dict("u_friend", 1),
		_rel_dict("u_blocked", 2),
	])
	var blocked: Array = rel_obj.get_blocked()
	assert_eq(blocked.size(), 1)
	assert_eq(blocked[0]["type"], 2)


func test_get_pending_incoming_filters_type3() -> void:
	_seed_cache([
		_rel_dict("u_in", 3),
		_rel_dict("u_out", 4),
	])
	var incoming: Array = rel_obj.get_pending_incoming()
	assert_eq(incoming.size(), 1)
	assert_eq(incoming[0]["type"], 3)


func test_get_pending_outgoing_filters_type4() -> void:
	_seed_cache([
		_rel_dict("u_in", 3),
		_rel_dict("u_out", 4),
	])
	var outgoing: Array = rel_obj.get_pending_outgoing()
	assert_eq(outgoing.size(), 1)
	assert_eq(outgoing[0]["type"], 4)


func test_filter_returns_empty_when_cache_empty() -> void:
	assert_eq(rel_obj.get_friends().size(), 0)
	assert_eq(rel_obj.get_blocked().size(), 0)
	assert_eq(rel_obj.get_pending_incoming().size(), 0)
	assert_eq(rel_obj.get_pending_outgoing().size(), 0)


# ==================================================================
# send_friend_request / block_user / remove_friend / unblock_user
# ==================================================================

func test_send_friend_request_calls_put_relationship() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	# Seed cache so _conn_for_user falls back to _first_connected_conn
	_stub_rest.responses["PUT /users/@me/relationships/u_1"] = \
		RestResult.success(200, null)
	var result: RestResult = await rel_obj.send_friend_request("u_1")
	assert_not_null(result)
	assert_true(result.ok)
	# Verify the PUT call was made
	var put_calls: Array = _stub_rest.calls.filter(
		func(c): return c["method"] == "PUT" and \
			c["path"] == "/users/@me/relationships/u_1"
	)
	assert_eq(put_calls.size(), 1)


func test_send_friend_request_returns_null_when_no_connection() -> void:
	var result: Variant = await rel_obj.send_friend_request("u_1")
	assert_null(result)


func test_block_user_calls_put_relationship_type2() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["PUT /users/@me/relationships/u_bad"] = \
		RestResult.success(200, null)
	var result: RestResult = await rel_obj.block_user("u_bad")
	assert_not_null(result)
	assert_true(result.ok)
	var put_calls: Array = _stub_rest.calls.filter(
		func(c): return c["method"] == "PUT" and \
			c["path"] == "/users/@me/relationships/u_bad"
	)
	assert_eq(put_calls.size(), 1)


func test_remove_friend_calls_delete_relationship() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["DELETE /users/@me/relationships/u_1"] = \
		RestResult.success(204, null)
	var result: RestResult = await rel_obj.remove_friend("u_1")
	assert_not_null(result)
	assert_true(result.ok)
	var del_calls: Array = _stub_rest.calls.filter(
		func(c): return c["method"] == "DELETE" and \
			c["path"] == "/users/@me/relationships/u_1"
	)
	assert_eq(del_calls.size(), 1)


func test_unblock_user_calls_delete_relationship() -> void:
	var ac := _make_accord_client()
	_setup_connection(ac, "g_1")
	_stub_rest.responses["DELETE /users/@me/relationships/u_bad"] = \
		RestResult.success(204, null)
	var result: RestResult = await rel_obj.unblock_user("u_bad")
	assert_not_null(result)
	assert_true(result.ok)
