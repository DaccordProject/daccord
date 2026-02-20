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
	var guild_name: String = cfg["guild_name"]
	AppState.server_connecting.emit(
		guild_name, index, servers.size()
	)
	var gw_url: String = _c._derive_gateway_url(base_url)
	var cdn_url: String = _c._derive_cdn_url(base_url)

	# Preserve reconnection state from previous connection
	var was_disconnected := false
	var old_guild_id := ""
	if index < _c._connections.size() and _c._connections[index] is Dictionary:
		was_disconnected = _c._connections[index].get("_was_disconnected", false)
		old_guild_id = _c._connections[index].get("guild_id", "")

	var conn := {
		"config": cfg, "client": null,
		"guild_id": old_guild_id, "cdn_url": cdn_url,
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

	# Token expired/invalid -- try re-auth with stored credentials
	if not me_result.ok:
		AppState.connection_step.emit("Re-authenticating...")
		var new_token: String = await _c.mutations.try_reauth(
			base_url, cfg.get("username", ""),
			cfg.get("password", ""),
		)
		if not new_token.is_empty():
			print("[Client] Re-authenticated on ", base_url)
			token = new_token
			Config.update_server_token(index, new_token)
			client.queue_free()
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
		# Emit reauth_needed for token-only connections
		var uname: String = cfg.get("username", "")
		var pwd: String = cfg.get("password", "")
		if uname.is_empty() or pwd.is_empty():
			AppState.reauth_needed.emit(index, base_url)
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_guild_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	if base_url != cfg["base_url"]:
		Config.update_server_url(index, base_url)

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(
		me_user, ClientModels.UserStatus.ONLINE, cdn_url
	)
	_c._user_cache[me_user.id] = me_dict
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

	# Find the guild matching guild_name
	AppState.connection_step.emit("Fetching spaces...")
	var spaces_result: RestResult = await client.users.list_spaces()
	if not spaces_result.ok:
		var err_msg: String = (
			spaces_result.error.message
			if spaces_result.error
			else "Failed to list guilds"
		)
		push_error(
			"[Client] Failed to list guilds on ",
			base_url, ": ", err_msg
		)
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_guild_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var found_guild_id := ""
	for space in spaces_result.data:
		var s: AccordSpace = space
		if s.slug == guild_name:
			found_guild_id = s.id
			break

	if found_guild_id.is_empty():
		var err_msg := "Guild '%s' not found on %s" % [
			guild_name, base_url
		]
		push_error("[Client] ", err_msg)
		conn["status"] = "error"
		AppState.server_connection_failed.emit(old_guild_id, err_msg)
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var sp: RestResult = await client.spaces.fetch(found_guild_id)
	if sp.ok:
		var d := ClientModels.space_to_guild_dict(
			sp.data, cdn_url
		)
		d["folder"] = Config.get_guild_folder(d["id"])
		_c._guild_cache[d["id"]] = d
	else:
		for space in spaces_result.data:
			var s: AccordSpace = space
			if s.id == found_guild_id:
				var d := ClientModels.space_to_guild_dict(
					s, cdn_url
				)
				d["folder"] = Config.get_guild_folder(d["id"])
				_c._guild_cache[d["id"]] = d
				break

	conn["guild_id"] = found_guild_id
	_c._guild_to_conn[found_guild_id] = index
	_c._gw.connect_signals(client, index)
	AppState.connection_step.emit("Connecting to gateway...")
	client.login()

	conn["status"] = "connected"
	_c._auto_reconnect_attempted.erase(index)
	var was_connecting: bool = int(_c.mode) == Client.Mode.CONNECTING
	_c.mode = Client.Mode.LIVE
	AppState.guilds_updated.emit()
	# Restore saved status on first connection
	if was_connecting:
		var saved_status: int = Config.get_user_status()
		if saved_status != ClientModels.UserStatus.ONLINE:
			_c.update_presence(saved_status)
	return {"guild_id": found_guild_id}

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
	_c._guild_cache.clear()
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
	_c._guild_to_conn.clear()
	_c._channel_to_guild.clear()
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

func disconnect_server(guild_id: String) -> void:
	var idx: int = _c._guild_to_conn.get(guild_id, -1)
	if idx == -1:
		return
	# If user is in voice on this server, leave
	if AppState.voice_guild_id == guild_id:
		AppState.leave_voice()
	var conn = _c._connections[idx]
	if conn != null and conn["client"] != null:
		conn["client"].logout()
		conn["client"].queue_free()
	_c._guild_cache.erase(guild_id)
	_c._role_cache.erase(guild_id)
	_c._member_cache.erase(guild_id)
	_c._member_id_index.erase(guild_id)
	var to_remove: Array = []
	for ch_id in _c._channel_cache:
		if _c._channel_cache[ch_id].get("guild_id", "") == guild_id:
			to_remove.append(ch_id)
	for ch_id in to_remove:
		_c._channel_cache.erase(ch_id)
		_c._channel_to_guild.erase(ch_id)
		_c._unread_channels.erase(ch_id)
		_c._channel_mention_counts.erase(ch_id)
		_c._voice_state_cache.erase(ch_id)
		if _c._message_cache.has(ch_id):
			for msg in _c._message_cache[ch_id]:
				_c._message_id_index.erase(msg.get("id", ""))
			_c._message_cache.erase(ch_id)
	_c._guild_to_conn.erase(guild_id)
	_c._connections[idx] = null
	Config.remove_server(idx)
	_c._guild_to_conn.clear()
	for i in _c._connections.size():
		if _c._connections[i] != null:
			_c._guild_to_conn[_c._connections[i]["guild_id"]] = i
	if _c._all_failed() or _c._connections.is_empty():
		_c.set("mode", Client.Mode.CONNECTING)
	AppState.server_removed.emit(guild_id)
	AppState.guilds_updated.emit()

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
			var gid: String = conn.get("guild_id", "")
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
