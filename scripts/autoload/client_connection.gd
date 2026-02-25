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
	AppState.server_connecting.emit(
		space_name, index, servers.size()
	)
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

	print("[Client] Connecting to server: ", base_url)

	var client := _make_client(
		token, base_url, gw_url, cdn_url
	)
	conn["client"] = client

	# Fetch current user
	AppState.connection_step.emit("Authenticating...")
	var me_result: RestResult = await client.users.get_me()
	if not me_result.ok and base_url.begins_with("https://"):
		print(
			"[Client] HTTPS failed for ", base_url,
			", falling back to HTTP"
		)
		client.queue_free()
		base_url = base_url.replace("https://", "http://")
		gw_url = str(_c._derive_gateway_url(base_url))
		cdn_url = str(_c._derive_cdn_url(base_url))
		conn["cdn_url"] = cdn_url
		client = _make_client(
			token, base_url, gw_url, cdn_url
		)
		conn["client"] = client
		me_result = await client.users.get_me()

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

	if base_url != cfg["base_url"]:
		Config.update_server_url(index, base_url)

	# Check server version compatibility (non-blocking)
	var ver_result: RestResult = await client.rest.make_request(
		"GET", "/version"
	)
	if ver_result.ok and ver_result.data is Dictionary:
		conn["server_version"] = ver_result.data.get("version", "")
		conn["server_git_sha"] = ver_result.data.get("git_sha", "")
		var srv_ver: String = conn["server_version"]
		# Compare major version (first digit before the dot)
		var client_major: String = AccordConfig.CLIENT_VERSION.split(".")[0]
		var server_major: String = srv_ver.split(".")[0] if not srv_ver.is_empty() else ""
		if not server_major.is_empty() and server_major != client_major:
			AppState.server_version_warning.emit(
				old_space_id, srv_ver,
				AccordConfig.CLIENT_VERSION
			)

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(
		me_user, ClientModels.UserStatus.ONLINE, cdn_url
	)
	_c._user_cache[me_user.id] = me_dict
	conn["user_id"] = me_user.id
	conn["user"] = me_dict
	if _c.current_user.is_empty():
		_c.current_user = me_dict

	var dn: String = me_dict["display_name"]
	print(
		"[Client] Logged in as: ", dn,
		" on ", base_url,
		" is_admin=", me_user.is_admin
	)

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
	# Restore saved status on first connection
	if was_connecting:
		var saved_status: int = Config.get_user_status()
		if saved_status != ClientModels.UserStatus.ONLINE:
			_c.update_presence(saved_status)
	return {"space_id": found_space_id}

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
		if conn != null and conn["client"] != null:
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
	var conn = _c._connections[idx]
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
	print(
		"[Client] Gateway reconnect exhausted, "
		+ "attempting full reconnect with re-auth"
	)
	reconnect_server(conn_index)
