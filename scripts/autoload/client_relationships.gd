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
		var cfg: Dictionary = conn.get("config", {})
		var srv_url: String = cfg.get("base_url", "")
		var sp_name: String = cfg.get("space_name", "")
		var result: RestResult = await client.users.list_relationships()
		if result.ok and result.data is Array:
			for rel in result.data:
				if rel is AccordRelationship:
					var d: Dictionary = ClientModels.relationship_to_dict(
						rel, cdn, srv_url, sp_name
					)
					var key: String = str(i) + ":" + d["user"].get("id", "")
					_c._relationship_cache[key] = d
	_sync_to_friend_book()
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
	var live: Array = _c._relationship_cache.values().filter(
		func(r): return r["type"] == 1
	)
	# Build set of live friend keys (server_url:user_id)
	var live_keys: Dictionary = {}
	for rel in live:
		var key: String = rel.get("server_url", "") + ":" + rel["user"].get("id", "")
		live_keys[key] = true
	# Merge unavailable friends from the local book
	var book: Array = Config.friend_book.get_entries()
	for entry in book:
		if entry.get("type", 1) != 1:
			continue
		var key: String = entry["server_url"] + ":" + entry["user_id"]
		if live_keys.has(key):
			continue
		# Server still connected means friend was removed server-side
		if _is_server_connected(entry["server_url"]):
			continue
		live.append(ClientModels.friend_book_entry_to_dict(entry))
	return live

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

## Sync live type-1 relationships into the local friend book.
## Entries for connected servers are upserted; entries for
## disconnected servers are left untouched.
func _sync_to_friend_book() -> void:
	var book: Array = Config.friend_book.get_entries()
	# Index existing book by composite key
	var book_index: Dictionary = {}
	for i in book.size():
		var e: Dictionary = book[i]
		book_index[e["server_url"] + ":" + e["user_id"]] = i
	# Collect connected server URLs
	var connected_urls: Dictionary = {}
	for conn in _c._connections:
		if conn != null and conn.get("status", "") == "connected":
			var url: String = conn.get("config", {}).get("base_url", "")
			if not url.is_empty():
				connected_urls[url] = true
	# Upsert live friends
	var live_keys: Dictionary = {}
	var now: String = Time.get_datetime_string_from_system(true)
	for rel in _c._relationship_cache.values():
		if rel.get("type", 0) != 1:
			continue
		var srv: String = rel.get("server_url", "")
		var uid: String = rel["user"].get("id", "")
		if srv.is_empty() or uid.is_empty():
			continue
		var key: String = srv + ":" + uid
		live_keys[key] = true
		var entry := {
			"user_id": uid,
			"display_name": rel["user"].get("display_name", ""),
			"username": rel["user"].get("username", ""),
			"avatar_hash": _extract_avatar_hash(rel["user"].get("avatar")),
			"server_url": srv,
			"space_name": rel.get("space_name", ""),
			"since": rel.get("since", ""),
			"type": 1,
			"last_synced": now,
		}
		if book_index.has(key):
			book[book_index[key]] = entry
		else:
			book.append(entry)
			book_index[key] = book.size() - 1
	# Remove entries whose server IS connected but are no longer live
	# (i.e. the user was unfriended on the server)
	var filtered: Array = []
	for entry in book:
		var key: String = entry["server_url"] + ":" + entry["user_id"]
		var server_connected: bool = connected_urls.has(entry["server_url"])
		if server_connected and not live_keys.has(key):
			continue # unfriended
		filtered.append(entry)
	Config.friend_book.save_entries(filtered)

static func _extract_avatar_hash(avatar_value) -> String:
	if avatar_value == null:
		return ""
	var s: String = str(avatar_value)
	# If it's a full URL, extract just the hash/filename
	var slash_idx: int = s.rfind("/")
	if slash_idx != -1:
		s = s.substr(slash_idx + 1)
	var dot_idx: int = s.rfind(".")
	if dot_idx != -1:
		s = s.substr(0, dot_idx)
	return s

func _is_server_connected(server_url: String) -> bool:
	for conn in _c._connections:
		if conn != null and conn.get("status", "") == "connected":
			if conn.get("config", {}).get("base_url", "") == server_url:
				return true
	return false

func get_friends_count_for_server(server_url: String) -> int:
	var count: int = 0
	for rel in _c._relationship_cache.values():
		if rel.get("type", 0) == 1 and rel.get("server_url", "") == server_url:
			count += 1
	# Also count book entries for this server (in case already disconnected)
	if not _is_server_connected(server_url):
		for entry in Config.friend_book.get_for_server(server_url):
			if entry.get("type", 1) == 1:
				count += 1
	return count

func remove_unavailable_friend(server_url: String, user_id: String) -> void:
	Config.friend_book.remove_entry(server_url, user_id)
	AppState.relationships_updated.emit()
