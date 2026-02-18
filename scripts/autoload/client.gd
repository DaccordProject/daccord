extends Node

enum Mode { LIVE, CONNECTING }

# Dimension constants
const GUILD_ICON_SIZE := 48
const AVATAR_SIZE := 42
const CHANNEL_ICON_SIZE := 32
const CHANNEL_PANEL_WIDTH := 240
const GUILD_BAR_WIDTH := 68
const MESSAGE_CAP := 50
const TOUCH_TARGET_MIN := 44
const USER_CACHE_CAP := 500

var mode: Mode = Mode.CONNECTING
var current_user: Dictionary = {}
var fetch: ClientFetch
var admin: ClientAdmin
var voice: ClientVoice
var mutations: ClientMutations

# --- Data access API (properties) ---

var guilds: Array:
	get: return _guild_cache.values()

var channels: Array:
	get: return _channel_cache.values()

var dm_channels: Array:
	get: return _dm_channel_cache.values()

# Per-server connection state
var _connections: Array = []

# Caches (keyed by ID)
var _user_cache: Dictionary = {}
var _guild_cache: Dictionary = {}
var _channel_cache: Dictionary = {}
var _dm_channel_cache: Dictionary = {}
var _message_cache: Dictionary = {}
var _member_cache: Dictionary = {}
var _role_cache: Dictionary = {}
var _voice_state_cache: Dictionary = {} # channel_id -> Array of voice state dicts
var _voice_server_info: Dictionary = {} # stored for Phase 4

# Unread / mention tracking
var _unread_channels: Dictionary = {}       # channel_id -> true
var _channel_mention_counts: Dictionary = {} # channel_id -> int

# Message ID -> channel_id index for O(1) lookup
var _message_id_index: Dictionary = {}

# Routing maps
var _guild_to_conn: Dictionary = {}
var _channel_to_guild: Dictionary = {}
var _dm_to_conn: Dictionary = {}  # dm_channel_id -> conn index

# Tracks whether auto-reconnect (with re-auth) has been attempted
# per connection index, to prevent infinite loops.
var _auto_reconnect_attempted: Dictionary = {}

var _gw: ClientGateway
var _voice_session: AccordVoiceSession
var _camera_track: AccordMediaTrack
var _screen_track: AccordMediaTrack

func _ready() -> void:
	_gw = ClientGateway.new(self)
	fetch = ClientFetch.new(self)
	admin = ClientAdmin.new(self)
	voice = ClientVoice.new(self)
	mutations = ClientMutations.new(self)
	_voice_session = AccordVoiceSession.new()
	add_child(_voice_session)
	set_meta("_voice_session", _voice_session)
	_voice_session.session_state_changed.connect(
		voice.on_session_state_changed
	)
	_voice_session.peer_joined.connect(
		voice.on_peer_joined
	)
	_voice_session.peer_left.connect(
		voice.on_peer_left
	)
	_voice_session.signal_outgoing.connect(
		voice.on_signal_outgoing
	)
	AppState.channel_selected.connect(_on_channel_selected_clear_unread)
	if Config.has_servers():
		for i in Config.get_servers().size():
			connect_server(i)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		for conn in _connections:
			if conn != null and conn["client"] != null:
				conn["client"].logout()
		get_tree().quit()

func _derive_gateway_url(base_url: String) -> String:
	var gw := base_url.replace(
		"https://", "wss://"
	).replace("http://", "ws://")
	return gw + "/ws"

func _derive_cdn_url(base_url: String) -> String:
	return base_url + "/cdn"

# --- Multi-server connection ---

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
	var gw_url := _derive_gateway_url(base_url)
	var cdn_url := _derive_cdn_url(base_url)

	var conn := {
		"config": cfg, "client": null,
		"guild_id": "", "cdn_url": cdn_url,
		"status": "connecting",
	}
	while _connections.size() <= index:
		_connections.append(null)
	_connections[index] = conn

	print("[Client] Connecting to server: ", base_url)

	var client := _make_client(
		token, base_url, gw_url, cdn_url
	)
	conn["client"] = client

	# Fetch current user
	var me_result := await client.users.get_me()
	if not me_result.ok and base_url.begins_with("https://"):
		print(
			"[Client] HTTPS failed for ", base_url,
			", falling back to HTTP"
		)
		client.queue_free()
		base_url = base_url.replace("https://", "http://")
		gw_url = _derive_gateway_url(base_url)
		cdn_url = _derive_cdn_url(base_url)
		conn["cdn_url"] = cdn_url
		client = _make_client(
			token, base_url, gw_url, cdn_url
		)
		conn["client"] = client
		me_result = await client.users.get_me()

	# Token expired/invalid -- try re-auth with stored credentials
	if not me_result.ok:
		var new_token := await _try_reauth(
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
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	if base_url != cfg["base_url"]:
		Config.update_server_url(index, base_url)

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(
		me_user, ClientModels.UserStatus.ONLINE, cdn_url
	)
	_user_cache[me_user.id] = me_dict
	if current_user.is_empty():
		current_user = me_dict

	var dn: String = me_dict["display_name"]
	print(
		"[Client] Logged in as: ", dn,
		" on ", base_url,
		" is_admin=", me_user.is_admin
	)

	# Accept invite if provided (non-fatal)
	if not invite_code.is_empty():
		var inv := await client.invites.accept(invite_code)
		if not inv.ok:
			var inv_err: String = (
				inv.error.message
				if inv.error else "unknown"
			)
			push_warning(
				"[Client] Invite accept failed: ", inv_err
			)

	# Find the guild matching guild_name
	var spaces_result := await client.users.list_spaces()
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
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var sp := await client.spaces.fetch(found_guild_id)
	if sp.ok:
		var d := ClientModels.space_to_guild_dict(
			sp.data, cdn_url
		)
		_guild_cache[d["id"]] = d
	else:
		for space in spaces_result.data:
			var s: AccordSpace = space
			if s.id == found_guild_id:
				var d := ClientModels.space_to_guild_dict(
					s, cdn_url
				)
				_guild_cache[d["id"]] = d
				break

	conn["guild_id"] = found_guild_id
	_guild_to_conn[found_guild_id] = index
	_connect_gateway_signals(client, index)
	client.login()

	conn["status"] = "connected"
	_auto_reconnect_attempted.erase(index)
	mode = Mode.LIVE
	AppState.guilds_updated.emit()
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
	add_child(c)
	return c

func _connect_gateway_signals(
	client: AccordClient, idx: int
) -> void:
	var g := _gw
	client.ready_received.connect(
		g.on_gateway_ready.bind(idx))
	client.message_create.connect(
		g.on_message_create.bind(idx))
	client.message_update.connect(
		g.on_message_update.bind(idx))
	client.message_delete.connect(g.on_message_delete)
	client.typing_start.connect(g.on_typing_start)
	client.presence_update.connect(
		g.on_presence_update.bind(idx))
	client.member_join.connect(
		g.on_member_join.bind(idx))
	client.member_leave.connect(
		g.on_member_leave.bind(idx))
	client.member_update.connect(
		g.on_member_update.bind(idx))
	client.space_create.connect(
		g.on_space_create.bind(idx))
	client.space_update.connect(g.on_space_update)
	client.space_delete.connect(g.on_space_delete)
	client.channel_create.connect(
		g.on_channel_create.bind(idx))
	client.channel_update.connect(
		g.on_channel_update.bind(idx))
	client.channel_delete.connect(g.on_channel_delete)
	client.role_create.connect(
		g.on_role_create.bind(idx))
	client.role_update.connect(
		g.on_role_update.bind(idx))
	client.role_delete.connect(
		g.on_role_delete.bind(idx))
	client.ban_create.connect(g.on_ban_create.bind(idx))
	client.ban_delete.connect(g.on_ban_delete.bind(idx))
	client.invite_create.connect(
		g.on_invite_create.bind(idx))
	client.invite_delete.connect(
		g.on_invite_delete.bind(idx))
	client.emoji_update.connect(
		g.on_emoji_update.bind(idx))
	client.soundboard_create.connect(
		g.on_soundboard_create.bind(idx))
	client.soundboard_update.connect(
		g.on_soundboard_update.bind(idx))
	client.soundboard_delete.connect(
		g.on_soundboard_delete.bind(idx))
	client.soundboard_play.connect(
		g.on_soundboard_play.bind(idx))
	client.reaction_add.connect(g.on_reaction_add)
	client.reaction_remove.connect(g.on_reaction_remove)
	client.reaction_clear.connect(g.on_reaction_clear)
	client.reaction_clear_emoji.connect(
		g.on_reaction_clear_emoji)
	client.voice_state_update.connect(
		g.on_voice_state_update.bind(idx))
	client.voice_server_update.connect(
		g.on_voice_server_update.bind(idx))
	client.voice_signal.connect(
		g.on_voice_signal.bind(idx))
	client.disconnected.connect(
		g.on_gateway_disconnected.bind(idx))
	client.reconnecting.connect(
		g.on_gateway_reconnecting.bind(idx))
	client.resumed.connect(
		g.on_gateway_reconnected.bind(idx))

# --- Client routing ---

func _conn_for_guild(guild_id: String):
	var idx = _guild_to_conn.get(guild_id, -1)
	if idx == -1 or idx >= _connections.size():
		return null
	return _connections[idx]

func _client_for_guild(gid: String) -> AccordClient:
	var conn = _conn_for_guild(gid)
	if conn == null: return null
	return conn["client"]

func _client_for_channel(cid: String) -> AccordClient:
	var gid: String = _channel_to_guild.get(cid, "")
	if not gid.is_empty():
		return _client_for_guild(gid)
	# DM channels aren't in _channel_to_guild — route via
	# _dm_to_conn if available, else first connected client
	if _dm_channel_cache.has(cid):
		var conn_idx: int = _dm_to_conn.get(cid, -1)
		if conn_idx != -1 and conn_idx < _connections.size():
			var conn = _connections[conn_idx]
			if conn != null and conn["client"] != null:
				return conn["client"]
		return _first_connected_client()
	return null

func _cdn_for_guild(guild_id: String) -> String:
	var conn = _conn_for_guild(guild_id)
	if conn == null: return ""
	return conn["cdn_url"]

func _cdn_for_channel(channel_id: String) -> String:
	var gid: String = _channel_to_guild.get(channel_id, "")
	if not gid.is_empty():
		return _cdn_for_guild(gid)
	# DM channels — route via _dm_to_conn or first connected CDN
	if _dm_channel_cache.has(channel_id):
		var conn_idx: int = _dm_to_conn.get(channel_id, -1)
		if conn_idx != -1 and conn_idx < _connections.size():
			var conn = _connections[conn_idx]
			if conn != null:
				return conn["cdn_url"]
		return _first_connected_cdn()
	return ""

func is_server_connected(index: int) -> bool:
	if index < 0 or index >= _connections.size():
		return false
	var conn = _connections[index]
	return conn != null and conn["status"] == "connected"

func _all_failed() -> bool:
	for c in _connections:
		if c != null and c["status"] != "error":
			return false
	return true

func _first_connected_client() -> AccordClient:
	for conn in _connections:
		if conn != null \
				and conn["status"] == "connected" \
				and conn["client"] != null:
			return conn["client"]
	return null

func _first_connected_cdn() -> String:
	for conn in _connections:
		if conn != null and conn["status"] == "connected":
			return conn["cdn_url"]
	return ""

# --- Data access API ---

func get_channels_for_guild(gid: String) -> Array:
	var result: Array = []
	for ch in _channel_cache.values():
		if ch.get("guild_id", "") == gid:
			result.append(ch)
	return result

func get_messages_for_channel(cid: String) -> Array:
	return _message_cache.get(cid, [])

func get_user_by_id(uid: String) -> Dictionary:
	return _user_cache.get(uid, {})

func get_guild_by_id(gid: String) -> Dictionary:
	return _guild_cache.get(gid, {})

func get_members_for_guild(gid: String) -> Array:
	return _member_cache.get(gid, [])

func get_roles_for_guild(gid: String) -> Array:
	return _role_cache.get(gid, [])

func get_message_by_id(mid: String) -> Dictionary:
	var cid: String = _message_id_index.get(mid, "")
	if not cid.is_empty() and _message_cache.has(cid):
		for msg in _message_cache[cid]:
			if msg.get("id", "") == mid:
				return msg
	# Fallback: linear search (index may be stale)
	for ch_msgs in _message_cache.values():
		for msg in ch_msgs:
			if msg.get("id", "") == mid:
				return msg
	return {}

# --- Voice data access (delegates to ClientVoice) ---

func get_voice_users(ch_id: String) -> Array:
	return voice.get_voice_users(ch_id)

func get_voice_user_count(ch_id: String) -> int:
	return voice.get_voice_user_count(ch_id)

# --- Search (delegates to ClientMutations) ---

func search_messages(
	gid: String, q: String, filters: Dictionary = {},
) -> Dictionary:
	return await mutations.search_messages(
		gid, q, filters
	)

# --- Mutation API (delegates to ClientMutations) ---

func send_message_to_channel(
	cid: String, content: String, reply_to: String = ""
) -> bool:
	return await mutations.send_message_to_channel(
		cid, content, reply_to
	)

func update_message_content(
	mid: String, new_content: String
) -> bool:
	return await mutations.update_message_content(
		mid, new_content
	)

func remove_message(mid: String) -> bool:
	return await mutations.remove_message(mid)

func add_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	await mutations.add_reaction(cid, mid, emoji)

func remove_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	await mutations.remove_reaction(cid, mid, emoji)

func update_presence(status: int) -> void:
	mutations.update_presence(status)

func send_typing(cid: String) -> void:
	mutations.send_typing(cid)

# --- Voice API (delegates to ClientVoice) ---

func join_voice_channel(ch_id: String) -> bool:
	return await voice.join_voice_channel(ch_id)

func leave_voice_channel() -> bool:
	return await voice.leave_voice_channel()

func set_voice_muted(muted: bool) -> void:
	voice.set_voice_muted(muted)

func set_voice_deafened(deafened: bool) -> void:
	voice.set_voice_deafened(deafened)

func toggle_video() -> void:
	voice.toggle_video()

func start_screen_share(
	source_type: String, source_id: int,
) -> void:
	voice.start_screen_share(source_type, source_id)

func stop_screen_share() -> void:
	voice.stop_screen_share()

func create_dm(user_id: String) -> void:
	await mutations.create_dm(user_id)

func close_dm(channel_id: String) -> void:
	await mutations.close_dm(channel_id)

# --- Permission helpers ---

func has_permission(gid: String, perm: String) -> bool:
	var my_id: String = current_user.get("id", "")
	if current_user.get("is_admin", false):
		return true
	var guild: Dictionary = _guild_cache.get(gid, {})
	if guild.get("owner_id", "") == my_id:
		return true
	var members: Array = _member_cache.get(gid, [])
	var my_roles: Array = []
	for m in members:
		if m.get("id", "") == my_id:
			my_roles = m.get("roles", [])
			break
	var roles: Array = _role_cache.get(gid, [])
	var all_perms: Array = []
	for role in roles:
		var in_role: bool = role.get("id", "") in my_roles
		if role.get("position", 0) == 0 or in_role:
			for p in role.get("permissions", []):
				if p not in all_perms:
					all_perms.append(p)
	return AccordPermission.has(all_perms, perm)

func is_space_owner(gid: String) -> bool:
	var guild: Dictionary = _guild_cache.get(gid, {})
	return guild.get("owner_id", "") == current_user.get(
		"id", ""
	)

# --- Unread / mention tracking ---

func _on_channel_selected_clear_unread(cid: String) -> void:
	if not _unread_channels.has(cid):
		return
	_unread_channels.erase(cid)
	_channel_mention_counts.erase(cid)
	# Update the cached channel dict
	if _channel_cache.has(cid):
		_channel_cache[cid]["unread"] = false
		var gid: String = _channel_cache[cid].get("guild_id", "")
		_update_guild_unread(gid)
		AppState.channels_updated.emit(gid)
	elif _dm_channel_cache.has(cid):
		_dm_channel_cache[cid]["unread"] = false
		AppState.dm_channels_updated.emit()

func mark_channel_unread(
	cid: String, is_mention: bool = false,
) -> void:
	_unread_channels[cid] = true
	if is_mention:
		var cur: int = _channel_mention_counts.get(cid, 0)
		_channel_mention_counts[cid] = cur + 1
	# Update channel dict
	if _channel_cache.has(cid):
		_channel_cache[cid]["unread"] = true
		var gid: String = _channel_cache[cid].get("guild_id", "")
		_update_guild_unread(gid)
		AppState.channels_updated.emit(gid)
		AppState.guilds_updated.emit()
	elif _dm_channel_cache.has(cid):
		_dm_channel_cache[cid]["unread"] = true
		AppState.dm_channels_updated.emit()

func _update_guild_unread(gid: String) -> void:
	if gid.is_empty() or not _guild_cache.has(gid):
		return
	var has_unread := false
	var total_mentions := 0
	for ch_id in _channel_cache:
		var ch: Dictionary = _channel_cache[ch_id]
		if ch.get("guild_id", "") != gid:
			continue
		if _unread_channels.has(ch_id):
			has_unread = true
		total_mentions += _channel_mention_counts.get(ch_id, 0)
	_guild_cache[gid]["unread"] = has_unread
	_guild_cache[gid]["mentions"] = total_mentions

# --- Server management ---

func disconnect_server(guild_id: String) -> void:
	var idx: int = _guild_to_conn.get(guild_id, -1)
	if idx == -1:
		return
	# If user is in voice on this server, leave
	if AppState.voice_guild_id == guild_id:
		AppState.leave_voice()
	var conn = _connections[idx]
	if conn != null and conn["client"] != null:
		conn["client"].logout()
		conn["client"].queue_free()
	_guild_cache.erase(guild_id)
	_role_cache.erase(guild_id)
	_member_cache.erase(guild_id)
	var to_remove: Array = []
	for ch_id in _channel_cache:
		if _channel_cache[ch_id].get("guild_id", "") == guild_id:
			to_remove.append(ch_id)
	for ch_id in to_remove:
		_channel_cache.erase(ch_id)
		_channel_to_guild.erase(ch_id)
		_unread_channels.erase(ch_id)
		_channel_mention_counts.erase(ch_id)
		_voice_state_cache.erase(ch_id)
		if _message_cache.has(ch_id):
			for msg in _message_cache[ch_id]:
				_message_id_index.erase(msg.get("id", ""))
			_message_cache.erase(ch_id)
	_guild_to_conn.erase(guild_id)
	_connections[idx] = null
	Config.remove_server(idx)
	_guild_to_conn.clear()
	for i in _connections.size():
		if _connections[i] != null:
			_guild_to_conn[_connections[i]["guild_id"]] = i
	if _all_failed() or _connections.is_empty():
		mode = Mode.CONNECTING
	AppState.guilds_updated.emit()

# --- Connection status helpers ---

func is_guild_connected(gid: String) -> bool:
	var conn = _conn_for_guild(gid)
	return conn != null and conn["status"] == "connected"

func get_guild_connection_status(gid: String) -> String:
	var conn = _conn_for_guild(gid)
	if conn == null: return "none"
	return conn.get("status", "none")

func get_conn_index_for_guild(gid: String) -> int:
	return _guild_to_conn.get(gid, -1)

func reconnect_server(index: int) -> void:
	if index < 0 or index >= _connections.size():
		return
	var conn = _connections[index]
	if conn == null:
		return
	if conn["client"] != null:
		conn["client"].logout()
		conn["client"].queue_free()
	conn["status"] = "connecting"
	conn["client"] = null
	connect_server(index)

## Called (deferred) by ClientGateway when gateway reconnection
## is exhausted or hits a fatal auth error.  Performs a full
## reconnect_server() -- which includes _try_reauth() -- but
## only once per disconnect cycle to avoid looping.
func _handle_gateway_reconnect_failed(
	conn_index: int,
) -> void:
	if _auto_reconnect_attempted.get(conn_index, false):
		# Already tried once this cycle -- give up
		if conn_index < _connections.size() \
				and _connections[conn_index] != null:
			var conn: Dictionary = _connections[conn_index]
			conn["status"] = "error"
			conn["_was_disconnected"] = false
			var gid: String = conn.get("guild_id", "")
			AppState.server_connection_failed.emit(
				gid, "Reconnection failed"
			)
		return
	_auto_reconnect_attempted[conn_index] = true
	print(
		"[Client] Gateway reconnect exhausted, "
		+ "attempting full reconnect with re-auth"
	)
	reconnect_server(conn_index)

# --- Helpers ---

func _find_channel_for_message(mid: String) -> String:
	var cid: String = _message_id_index.get(mid, "")
	if not cid.is_empty() and _message_cache.has(cid):
		return cid
	# Fallback: linear search
	for ch_id in _message_cache:
		for msg in _message_cache[ch_id]:
			if msg.get("id", "") == mid:
				return ch_id
	return ""

func _try_reauth(
	base_url: String, username: String, password: String,
) -> String:
	if username.is_empty() or password.is_empty():
		return ""
	var api_url := base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	add_child(rest)
	var auth := AuthApi.new(rest)
	var result := await auth.login(
		{"username": username, "password": password}
	)
	rest.queue_free()
	if result.ok and result.data is Dictionary:
		return result.data.get("token", "")
	return ""

## Trims the user cache if it exceeds USER_CACHE_CAP.
## Preserves the current user and users referenced by current
## guild members; evicts the rest.
func trim_user_cache() -> void:
	if _user_cache.size() <= USER_CACHE_CAP:
		return
	var keep: Dictionary = {}
	var my_id: String = current_user.get("id", "")
	if not my_id.is_empty():
		keep[my_id] = true
	# Keep users referenced by current guild's members
	var gid := AppState.current_guild_id
	if _member_cache.has(gid):
		for m in _member_cache[gid]:
			keep[m.get("id", "")] = true
	# Keep users in current channel's messages
	var cid := AppState.current_channel_id
	if _message_cache.has(cid):
		for msg in _message_cache[cid]:
			var author: Dictionary = msg.get("author", {})
			keep[author.get("id", "")] = true
	var to_erase: Array = []
	for uid in _user_cache:
		if not keep.has(uid):
			to_erase.append(uid)
	for uid in to_erase:
		_user_cache.erase(uid)
