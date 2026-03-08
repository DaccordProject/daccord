class_name ClientRelationships
extends RefCounted

## Handles friend/relationship operations for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and emit AppState signals.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func fetch_relationships() -> void:
	for i in _c._connections.size():
		var conn: Dictionary = _c._connections[i]
		if conn == null or conn.get("status", "") != "connected":
			continue
		var client: AccordClient = conn.get("client")
		if client == null:
			continue
		var cdn: String = conn.get("cdn_url", "")
		var result: RestResult = await client.users.list_relationships()
		if result.ok and result.data is Array:
			for rel in result.data:
				if rel is AccordRelationship:
					var d: Dictionary = ClientModels.relationship_to_dict(rel, cdn)
					var key: String = str(i) + ":" + d["user"].get("id", "")
					_c._relationship_cache[key] = d
	AppState.relationships_updated.emit()

func get_relationship(user_id: String) -> Variant:
	for key in _c._relationship_cache:
		var rel: Dictionary = _c._relationship_cache[key]
		if rel["user"].get("id", "") == user_id:
			return rel
	return null

func get_friends() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 1)

func get_blocked() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 2)

func get_pending_incoming() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 3)

func get_pending_outgoing() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 4)

func send_friend_request(user_id: String) -> void:
	var conn = _c._first_connected_conn()
	if conn == null:
		return
	var client: AccordClient = conn["client"]
	await client.users.put_relationship(user_id, {"type": 1})

func accept_friend_request(user_id: String) -> void:
	await send_friend_request(user_id)

func decline_friend_request(user_id: String) -> void:
	var conn = _c._first_connected_conn()
	if conn == null:
		return
	var client: AccordClient = conn["client"]
	await client.users.delete_relationship(user_id)

func block_user(user_id: String) -> void:
	var conn = _c._first_connected_conn()
	if conn == null:
		return
	var client: AccordClient = conn["client"]
	await client.users.put_relationship(user_id, {"type": 2})

func unblock_user(user_id: String) -> void:
	await decline_friend_request(user_id)

func remove_friend(user_id: String) -> void:
	await decline_friend_request(user_id)
