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

func is_user_blocked(user_id: String) -> bool:
	for key in _c._relationship_cache:
		var rel: Dictionary = _c._relationship_cache[key]
		if rel["user"].get("id", "") == user_id and rel["type"] == 2:
			return true
	return false

func get_friends() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 1)

func get_blocked() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 2)

func get_pending_incoming() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 3)

func get_pending_outgoing() -> Array:
	return _c._relationship_cache.values().filter(func(r): return r["type"] == 4)

func _conn_for_user(user_id: String):
	for key in _c._relationship_cache:
		var parts: PackedStringArray = key.split(":")
		if parts.size() == 2 and parts[1] == user_id:
			var idx: int = int(parts[0])
			if idx < _c._connections.size():
				var conn = _c._connections[idx]
				if conn != null and conn.get("status", "") == "connected":
					return conn
	return _c._first_connected_conn()

func get_mutual_friends(user_id: String) -> Array:
	var conn = _conn_for_user(user_id)
	if conn == null:
		conn = _c._first_connected_conn()
	if conn == null:
		return []
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.users.get_mutual_friends(user_id)
	if result.ok and result.data is Array:
		return result.data
	return []

func search_user_by_username(username: String) -> String:
	# Try local cache first
	var local_id: String = _c.find_user_id_by_username(username)
	if not local_id.is_empty():
		return local_id
	# Fall back to server search
	var conn = _c._first_connected_conn()
	if conn == null:
		return ""
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.users.search_users(username, 5)
	if result.ok and result.data is Array:
		var lower: String = username.to_lower()
		for user in result.data:
			if user is AccordUser:
				if user.username.to_lower() == lower:
					return user.id
				if user.display_name != null \
						and str(user.display_name).to_lower() == lower:
					return user.id
	return ""

func send_friend_request(user_id: String) -> RestResult:
	var conn = _conn_for_user(user_id)
	if conn == null:
		return null
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.users.put_relationship(user_id, {"type": 1})
	return result

func accept_friend_request(user_id: String) -> RestResult:
	return await send_friend_request(user_id)

func decline_friend_request(user_id: String) -> RestResult:
	var conn = _conn_for_user(user_id)
	if conn == null:
		return null
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.users.delete_relationship(user_id)
	return result

func block_user(user_id: String) -> RestResult:
	var conn = _conn_for_user(user_id)
	if conn == null:
		return null
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.users.put_relationship(user_id, {"type": 2})
	return result

func unblock_user(user_id: String) -> RestResult:
	return await decline_friend_request(user_id)

func remove_friend(user_id: String) -> RestResult:
	return await decline_friend_request(user_id)
