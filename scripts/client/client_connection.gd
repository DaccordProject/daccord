class_name ClientConnection
extends RefCounted

## Manages server connection lifecycle (connect, disconnect, reconnect).
## Extracted from Client to keep that file focused on data access and delegation.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func connect_server(
	index: int, invite_code: String = ""
) -> Dictionary:
	var servers := Config.get_servers()
	if index < 0 or index >= servers.size():
		return {"error": "Invalid server index"}

	var cfg: Dictionary = servers[index]
	var base_url: String = cfg["base_url"]
	var token: String = cfg["token"]
	var space_name: String = cfg["space_name"]
	var gw_url: String = _c._derive_gateway_url(base_url)
	var cdn_url: String = _c._derive_cdn_url(base_url)

	# Preserve reconnection state from previous connection
	var was_disconnected := false
	var old_space_id := ""
	if index < _c._connections.size() and _c._connections[index] is Dictionary:
		was_disconnected = _c._connections[index].get("_was_disconnected", false)
		old_space_id = _c._connections[index].get("space_id", "")

	var conn := {
		"config": cfg, "client": null,
		"space_id": old_space_id, "cdn_url": cdn_url,
		"status": "connecting",
		"_was_disconnected": was_disconnected,
	}
	while _c._connections.size() <= index:
		_c._connections.append(null)
	_c._connections[index] = conn

	var client := _make_client(
		token, base_url, gw_url, cdn_url
	)
	conn["client"] = client

	# Fetch current user
	AppState.connection_step.emit("Authenticating...")
	var me_result: RestResult = await client.users.get_me()
	if not me_result.ok:
		var err_msg: String = (
			me_result.error.message
			if me_result.error
			else "Failed to authenticate"
		)
		push_error(
			"[Client] Auth failed for ", base_url,
			": ", err_msg
		)
		# Prompt re-auth for auth failures (401/403) regardless
		# of whether stored credentials exist -- they may be stale.
		# For non-auth errors (server down, etc.) only show retry.
		var is_auth_error: bool = me_result.status_code in [401, 403]
		if is_auth_error:
			AppState.reauth_needed.emit(index, base_url, cfg.get("username", ""))
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_space_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(
		me_user, ClientModels.UserStatus.ONLINE, cdn_url
	)
	_c._user_cache[me_user.id] = me_dict
	conn["user_id"] = me_user.id
	conn["user"] = me_dict
	if _c.current_user.is_empty():
		_c.current_user = me_dict

	# Accept invite if provided (non-fatal)
	if not invite_code.is_empty():
		AppState.connection_step.emit("Accepting invite...")
		var inv: RestResult = await client.invites.accept(invite_code)
		if not inv.ok:
			var inv_err: String = (
				inv.error.message
				if inv.error else "unknown"
			)
			push_warning(
				"[Client] Invite accept failed: ", inv_err
			)

	# Find the space matching space_name
	AppState.connection_step.emit("Fetching spaces...")
	var spaces_result: RestResult = await client.users.list_spaces()
	if not spaces_result.ok:
		var err_msg: String = (
			spaces_result.error.message
			if spaces_result.error
			else "Failed to list spaces"
		)
		push_error(
			"[Client] Failed to list spaces on ",
			base_url, ": ", err_msg
		)
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_space_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var found_space_id := ""
	for space in spaces_result.data:
		var s: AccordSpace = space
		if s.slug == space_name:
			found_space_id = s.id
			break

	if found_space_id.is_empty():
		var err_msg := "Space '%s' not found on %s" % [
			space_name, base_url
		]
		push_error("[Client] ", err_msg)
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_space_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var sp: RestResult = await client.spaces.fetch(found_space_id)
	if sp.ok:
		var d := ClientModels.space_to_dict(
			sp.data, cdn_url
		)
		d["folder"] = Config.get_space_folder(d["id"])
		_c._space_cache[d["id"]] = d
	else:
		for space in spaces_result.data:
			var s: AccordSpace = space
			if s.id == found_space_id:
				var d := ClientModels.space_to_dict(
					s, cdn_url
				)
				d["folder"] = Config.get_space_folder(d["id"])
				_c._space_cache[d["id"]] = d
				break

	conn["space_id"] = found_space_id
	_c._space_to_conn[found_space_id] = index
	_c._gw.connect_signals(client, index)
	AppState.connection_step.emit("Connecting to gateway...")
	client.login()
	await client.connected

	conn["status"] = "connected"
	_c._auto_reconnect_attempted.erase(index)
	var was_connecting: bool = int(_c.mode) == Client.Mode.CONNECTING
	_c.mode = Client.Mode.LIVE
	AppState.spaces_updated.emit()
	# Fetch plugins for this space
	_c.plugins.fetch_plugins(index, found_space_id)
	# Restore saved status on first connection
	if was_connecting:
		var saved_status: int = Config.get_user_status()
		if saved_status != ClientModels.UserStatus.ONLINE:
			_c.update_presence(saved_status)
	return {"space_id": found_space_id}

## Connects to a server as an anonymous guest (read-only, transient).
## Does not persist the connection to Config.
func connect_guest(
	base_url: String, token: String, space_id: String,
	expires_at: String = "",
) -> Dictionary:
	var gw_url: String = _c._derive_gateway_url(base_url)
	var cdn_url: String = _c._derive_cdn_url(base_url)

	var index: int = _c._connections.size()
	var conn := {
		"config": {"base_url": base_url, "token": token},
		"client": null,
		"space_id": "",
		"cdn_url": cdn_url,
		"status": "connecting",
		"guest": true,
		"guest_expires_at": expires_at,
	}
	_c._connections.append(conn)

	var client := _make_guest_client(token, base_url, gw_url, cdn_url)
	conn["client"] = client

	# Fetch current user (server returns a synthetic guest user)
	AppState.connection_step.emit("Connecting as guest...")
	var me_result: RestResult = await client.users.get_me()
	if not me_result.ok:
		var err_msg: String = (
			me_result.error.message
			if me_result.error
			else "Failed to connect as guest"
		)
		push_error("[Client] Guest auth failed for ", base_url, ": ", err_msg)
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(
		me_user, ClientModels.UserStatus.ONLINE, cdn_url
	)
	_c._user_cache[me_user.id] = me_dict
	conn["user_id"] = me_user.id
	conn["user"] = me_dict
	if _c.current_user.is_empty():
		_c.current_user = me_dict

	# Fetch the specific space
	AppState.connection_step.emit("Fetching space...")
	var sp: RestResult = await client.spaces.fetch(space_id)
	if not sp.ok:
		var err_msg: String = (
			sp.error.message if sp.error else "Space not found"
		)
		push_error("[Client] Guest space fetch failed: ", err_msg)
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var d := ClientModels.space_to_dict(sp.data, cdn_url)
	_c._space_cache[d["id"]] = d

	conn["space_id"] = space_id
	_c._space_to_conn[space_id] = index
	_c._gw.connect_signals(client, index)
	AppState.connection_step.emit("Connecting to gateway...")
	client.login()
	await client.connected

	conn["status"] = "connected"
	_c.mode = Client.Mode.LIVE
	AppState.spaces_updated.emit()
	AppState.enter_guest_mode(base_url)
	_start_guest_refresh_timer(index)
	return {"space_id": space_id}

## Upgrades a guest connection to an authenticated one.
## Replaces the transient guest token with real credentials and persists
## the connection to Config.
func upgrade_guest_connection(
	base_url: String, token: String,
	space_name: String, username: String,
	display_name: String = "",
) -> Dictionary:
	# Find and disconnect the guest connection
	var guest_idx: int = -1
	for i in _c._connections.size():
		var conn = _c._connections[i]
		if conn != null and conn.get("guest", false):
			var cfg: Dictionary = conn.get("config", {})
			if cfg.get("base_url", "") == base_url:
				guest_idx = i
				break

	if guest_idx != -1:
		var conn = _c._connections[guest_idx]
		# Stop guest token refresh timer
		var timer = conn.get("_guest_refresh_timer")
		if timer is Timer and is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		if conn["client"] != null:
			conn["client"].logout()
			conn["client"].queue_free()
		# Clean up caches for the guest space
		var sid: String = conn.get("space_id", "")
		if not sid.is_empty():
			_c._space_cache.erase(sid)
			_c._space_to_conn.erase(sid)
		_c._connections[guest_idx] = null

	AppState.exit_guest_mode()

	# Add as a real server and connect
	Config.add_server(base_url, token, space_name, username, display_name)
	var server_index: int = Config.get_servers().size() - 1
	return await connect_server(server_index)

func _make_guest_client(
	token: String, base_url: String,
	gw_url: String, cdn_url: String
) -> AccordClient:
	var c := AccordClient.new()
	c.token = token
	c.token_type = "Bearer"
	c.base_url = base_url
	c.gateway_url = gw_url
	c.cdn_url = cdn_url
	c.intents = GatewayIntents.guest()
	_c.add_child(c)
	return c

## Starts a timer that silently refreshes the guest token before it expires.
## If expires_at is empty or unparseable, defaults to refreshing every 45 minutes.
func _start_guest_refresh_timer(conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	if not conn.get("guest", false):
		return
	var wait_sec: float = 45.0 * 60.0 # default: 45 minutes
	var expires_str: String = conn.get("guest_expires_at", "")
	if not expires_str.is_empty():
		var expires_unix: float = _parse_iso_to_unix(expires_str)
		if expires_unix > 0.0:
			var now: float = Time.get_unix_time_from_system()
			# Refresh 5 minutes before expiry, minimum 30 seconds
			wait_sec = maxf(expires_unix - now - 300.0, 30.0)
	var timer := Timer.new()
	timer.wait_time = wait_sec
	timer.one_shot = true
	timer.timeout.connect(_refresh_guest_token.bind(conn_index))
	_c.add_child(timer)
	timer.start()
	conn["_guest_refresh_timer"] = timer

## Silently refreshes the guest token for a connection.
func _refresh_guest_token(conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	if not conn.get("guest", false) or conn.get("status", "") != "connected":
		return
	var base_url: String = conn["config"].get("base_url", "")
	if base_url.is_empty():
		return
	var api_url: String = base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	_c.add_child(rest)
	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.guest()
	rest.queue_free()
	if not result.ok or not result.data is Dictionary:
		push_warning("[Client] Guest token refresh failed; connection may expire")
		return
	var new_token: String = result.data.get("token", "")
	if new_token.is_empty():
		return
	# Update the token on the AccordClient's REST layer
	var client: AccordClient = conn.get("client")
	if client != null and client.rest != null:
		client.rest.token = new_token
		client.token = new_token
	conn["config"]["token"] = new_token
	conn["guest_expires_at"] = str(result.data.get("expires_at", ""))
	# Schedule next refresh
	_start_guest_refresh_timer(conn_index)

## Parses an ISO 8601 timestamp to Unix time. Returns 0.0 on failure.
static func _parse_iso_to_unix(iso: String) -> float:
	var t_idx: int = iso.find("T")
	if t_idx == -1:
		return 0.0
	var date_part: String = iso.substr(0, t_idx)
	var date_parts: PackedStringArray = date_part.split("-")
	if date_parts.size() < 3:
		return 0.0
	var time_part: String = iso.substr(t_idx + 1)
	# Strip timezone suffix (keep only HH:MM:SS)
	for suffix in ["Z", "+"]:
		var s_idx: int = time_part.find(suffix)
		if s_idx != -1:
			time_part = time_part.substr(0, s_idx)
	# Handle negative timezone offset (but not the leading minus in date)
	var dash_idx: int = time_part.rfind("-")
	if dash_idx > 0:
		time_part = time_part.substr(0, dash_idx)
	# Strip milliseconds
	var dot_idx: int = time_part.find(".")
	if dot_idx != -1:
		time_part = time_part.substr(0, dot_idx)
	var time_parts: PackedStringArray = time_part.split(":")
	if time_parts.size() < 2:
		return 0.0
	var dt := {
		"year": date_parts[0].to_int(),
		"month": date_parts[1].to_int(),
		"day": date_parts[2].to_int(),
		"hour": time_parts[0].to_int(),
		"minute": time_parts[1].to_int(),
		"second": time_parts[2].to_int() if time_parts.size() > 2 else 0,
	}
	return Time.get_unix_time_from_datetime_dict(dt)

func _make_client(
	token: String, base_url: String,
	gw_url: String, cdn_url: String
) -> AccordClient:
	var c := AccordClient.new()
	c.token = token
	c.token_type = "Bearer"
	c.base_url = base_url
	c.gateway_url = gw_url
	c.cdn_url = cdn_url
	c.intents = GatewayIntents.all()
	_c.add_child(c)
	return c

func disconnect_all() -> void:
	# Leave voice if active
	if not AppState.voice_channel_id.is_empty():
		AppState.leave_voice()
	# Logout and free all clients
	for conn in _c._connections:
		if conn != null:
			var timer = conn.get("_guest_refresh_timer")
			if timer is Timer and is_instance_valid(timer):
				timer.stop()
				timer.queue_free()
			if conn["client"] != null:
				conn["client"].logout()
				conn["client"].queue_free()
	# Clear all caches
	_c._connections.clear()
	_c._user_cache.clear()
	_c._space_cache.clear()
	_c._channel_cache.clear()
	_c._dm_channel_cache.clear()
	_c._message_cache.clear()
	_c._member_cache.clear()
	_c._role_cache.clear()
	_c._voice_state_cache.clear()
	_c._voice_server_info.clear()
	_c._muted_channels.clear()
	_c._unread_channels.clear()
	_c._channel_mention_counts.clear()
	_c._message_id_index.clear()
	_c._member_id_index.clear()
	_c._space_to_conn.clear()
	_c._channel_to_space.clear()
	_c._dm_to_conn.clear()
	_c._auto_reconnect_attempted.clear()
	_c._emoji_download_pending.clear()
	_c._remote_tracks.clear()
	# Reset state
	_c.current_user = {}
	_c.mode = Client.Mode.CONNECTING
	# Clear custom emoji caches
	ClientModels.custom_emoji_paths.clear()
	ClientModels.custom_emoji_textures.clear()

func disconnect_server(space_id: String) -> void:
	var idx: int = _c._space_to_conn.get(space_id, -1)
	if idx == -1:
		return
	# If user is in voice on this server, leave
	if AppState.voice_space_id == space_id:
		AppState.leave_voice()
	# Sync friend book before losing the connection data
	if _c.relationships != null:
		_c.relationships._sync_to_friend_book()
	var conn = _c._connections[idx]
	# Clean up relationship cache entries for this connection
	var rel_keys_to_remove: Array = []
	for key in _c._relationship_cache:
		if key.begins_with(str(idx) + ":"):
			rel_keys_to_remove.append(key)
	for key in rel_keys_to_remove:
		_c._relationship_cache.erase(key)
	# Null the slot first so gateway disconnect handlers see null and
	# bail out instead of triggering reconnection / banner signals.
	_c._connections[idx] = null
	if conn != null and conn["client"] != null:
		conn["client"].logout()
		conn["client"].queue_free()
	_c._space_cache.erase(space_id)
	_c._role_cache.erase(space_id)
	_c._member_cache.erase(space_id)
	_c._member_id_index.erase(space_id)
	var to_remove: Array = []
	for ch_id in _c._channel_cache:
		if _c._channel_cache[ch_id].get("space_id", "") == space_id:
			to_remove.append(ch_id)
	for ch_id in to_remove:
		_c._channel_cache.erase(ch_id)
		_c._channel_to_space.erase(ch_id)
		_c._unread_channels.erase(ch_id)
		_c._channel_mention_counts.erase(ch_id)
		_c._voice_state_cache.erase(ch_id)
		if _c._message_cache.has(ch_id):
			for msg in _c._message_cache[ch_id]:
				_c._message_id_index.erase(msg.get("id", ""))
			_c._message_cache.erase(ch_id)
	_c._space_to_conn.erase(space_id)
	# Guest connections are transient -- don't touch Config
	var is_guest: bool = conn.get("guest", false) if conn != null else false
	if not is_guest:
		Config.remove_server(idx)
	_c._space_to_conn.clear()
	for i in _c._connections.size():
		if _c._connections[i] != null:
			_c._space_to_conn[_c._connections[i]["space_id"]] = i
	if _c._all_failed() or _c._connections.is_empty():
		_c.set("mode", Client.Mode.CONNECTING)
	AppState.server_removed.emit(space_id)
	AppState.spaces_updated.emit()

func reconnect_server(index: int) -> void:
	var servers := Config.get_servers()
	if index < 0 or index >= servers.size():
		return
	if index < _c._connections.size():
		var conn = _c._connections[index]
		if conn != null:
			if conn["client"] != null:
				conn["client"].logout()
				conn["client"].queue_free()
			conn["status"] = "connecting"
			conn["client"] = null
	connect_server(index)

## Called (deferred) by ClientGateway when gateway reconnection
## is exhausted or hits a fatal auth error.  Performs a full
## reconnect_server() -- which includes try_reauth() -- but
## only once per disconnect cycle to avoid looping.
func handle_gateway_reconnect_failed(
	conn_index: int,
) -> void:
	if _c.is_shutting_down:
		return
	if _c._auto_reconnect_attempted.get(conn_index, false):
		# Already tried once this cycle -- give up
		if conn_index < _c._connections.size() \
				and _c._connections[conn_index] != null:
			var conn: Dictionary = _c._connections[conn_index]
			conn["status"] = "error"
			conn["_was_disconnected"] = false
			var gid: String = conn.get("space_id", "")
			AppState.server_connection_failed.emit(
				gid, "Reconnection failed"
			)
		return
	_c._auto_reconnect_attempted[conn_index] = true
	reconnect_server(conn_index)

func flush_message_queue(space_id: String) -> void:
	var to_send: Array = []
	var remaining: Array = []
	for entry in _c._message_queue:
		var gid: String = _c._channel_to_space.get(
			entry["channel_id"], ""
		)
		if gid == space_id:
			to_send.append(entry)
		else:
			remaining.append(entry)
	_c._message_queue = remaining
	for entry in to_send:
		await _c.send_message_to_channel(
			entry["channel_id"], entry["content"],
			entry.get("reply_to", ""),
			entry.get("attachments", [])
		)

func on_profile_switched() -> void:
	disconnect_all()
	_c._forum_post_cache.clear()
	_c._muted_channels.clear()
	AppState.current_space_id = ""
	AppState.current_channel_id = ""
	AppState.is_dm_mode = false
	AppState.replying_to_message_id = ""
	AppState.editing_message_id = ""
	if Config.has_servers():
		for i in Config.get_servers().size():
			connect_server(i)
