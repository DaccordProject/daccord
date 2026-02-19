extends Node

enum Mode { LIVE, CONNECTING }

# Dimension constants
const GUILD_ICON_SIZE := 48
const AVATAR_SIZE := 42
const CHANNEL_ICON_SIZE := 32
const CHANNEL_PANEL_WIDTH := 240
const GUILD_BAR_WIDTH := 68
const MESSAGE_CAP := 50
const MAX_CHANNEL_MESSAGES := 200
const TOUCH_TARGET_MIN := 44
const USER_CACHE_CAP := 500

var app_version: String = ProjectSettings.get_setting(
	"application/config/version", "0.0.0"
)

var mode: Mode = Mode.CONNECTING
var current_user: Dictionary = {}
var fetch: ClientFetch
var admin: ClientAdmin
var voice: ClientVoice
var mutations: ClientMutations
var emoji # ClientEmoji (typed reference causes circular dep)
var connection: ClientConnection

# --- Data access API (properties) ---

var guilds: Array:
	get: return _guild_cache.values()

var channels: Array:
	get: return _channel_cache.values()

var dm_channels: Array:
	get: return _dm_channel_cache.values()

var pending_servers: Array:
	get:
		var result: Array = []
		var servers := Config.get_servers()
		for i in servers.size():
			if i < _connections.size() and _connections[i] != null:
				var conn: Dictionary = _connections[i]
				if conn["status"] == "connected":
					continue
				if conn["status"] == "error" \
						or conn["status"] == "connecting":
					result.append({
						"id": "__pending_%d" % i,
						"name": servers[i].get(
							"guild_name", "Unknown"
						),
						"icon": "",
						"disconnected": true,
						"server_index": i,
					})
			else:
				result.append({
					"id": "__pending_%d" % i,
					"name": servers[i].get(
						"guild_name", "Unknown"
					),
					"icon": "",
					"disconnected": true,
					"server_index": i,
				})
		return result

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

# Member ID index: guild_id -> { user_id -> array_index }
var _member_id_index: Dictionary = {}

# Routing maps
var _guild_to_conn: Dictionary = {}
var _channel_to_guild: Dictionary = {}
var _dm_to_conn: Dictionary = {}  # dm_channel_id -> conn index

# Tracks whether auto-reconnect (with re-auth) has been attempted
# per connection index, to prevent infinite loops.
var _auto_reconnect_attempted: Dictionary = {}

# Custom emoji download queue to avoid duplicate requests
var _emoji_download_pending: Dictionary = {} # emoji_id -> true

var _gw: ClientGateway
var _voice_session: AccordVoiceSession
var _idle_timer: Timer
var _is_auto_idle: bool = false
var _last_input_time: float = 0.0
var _camera_track: AccordMediaTrack
var _screen_track: AccordMediaTrack
var _remote_tracks: Dictionary = {} # user_id -> AccordMediaTrack

func _ready() -> void:
	_gw = ClientGateway.new(self)
	fetch = ClientFetch.new(self)
	admin = ClientAdmin.new(self)
	voice = ClientVoice.new(self)
	mutations = ClientMutations.new(self)
	var ClientEmojiClass = load("res://scripts/autoload/client_emoji.gd")
	emoji = ClientEmojiClass.new(self)
	connection = ClientConnection.new(self)
	if ClassDB.class_exists(&"AccordVoiceSession"):
		_voice_session = AccordVoiceSession.new()
	if _voice_session != null:
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
		if _voice_session.has_signal("track_received"):
			_voice_session.track_received.connect(
				voice.on_track_received
			)
	else:
		push_warning(
			"AccordVoiceSession unavailable — voice disabled"
		)
	AppState.channel_selected.connect(_on_channel_selected_clear_unread)
	# Idle timer setup
	_last_input_time = Time.get_ticks_msec() / 1000.0
	_idle_timer = Timer.new()
	_idle_timer.wait_time = 10.0
	_idle_timer.timeout.connect(_check_idle)
	add_child(_idle_timer)
	_idle_timer.start()
	if Config.has_servers():
		for i in Config.get_servers().size():
			connect_server(i)

func _input(_event: InputEvent) -> void:
	_last_input_time = Time.get_ticks_msec() / 1000.0
	if _is_auto_idle:
		_is_auto_idle = false
		var saved_status: int = Config.get_user_status()
		if saved_status == ClientModels.UserStatus.IDLE:
			saved_status = ClientModels.UserStatus.ONLINE
		update_presence(saved_status)

func _check_idle() -> void:
	var timeout: int = Config.get_idle_timeout()
	if timeout <= 0:
		return
	if _is_auto_idle:
		return
	var status: int = current_user.get(
		"status", ClientModels.UserStatus.OFFLINE
	)
	if status != ClientModels.UserStatus.ONLINE:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_input_time >= timeout:
		_is_auto_idle = true
		update_presence(ClientModels.UserStatus.IDLE)

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
	return await connection.connect_server(index, invite_code)

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
	cid: String, content: String, reply_to: String = "",
	attachments: Array = []
) -> bool:
	return await mutations.send_message_to_channel(
		cid, content, reply_to, attachments
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

func remove_all_reactions(
	cid: String, mid: String,
) -> void:
	await mutations.remove_all_reactions(cid, mid)

func update_presence(
	status: int, activity: Dictionary = {},
) -> void:
	mutations.update_presence(status, activity)

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

func get_camera_track() -> AccordMediaTrack:
	return _camera_track

func get_screen_track() -> AccordMediaTrack:
	return _screen_track

func get_remote_track(
	user_id: String,
) -> AccordMediaTrack:
	return _remote_tracks.get(user_id)

func update_profile(data: Dictionary) -> bool:
	return await mutations.update_profile(data)

func change_password(
	current_pw: String, new_pw: String,
) -> Dictionary:
	return await mutations.change_password(
		current_pw, new_pw
	)

func delete_account(password: String) -> Dictionary:
	return await mutations.delete_account(password)

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
	var my_roles: Array = []
	var mi: int = _member_index_for(gid, my_id)
	if mi != -1:
		my_roles = _member_cache.get(gid, [])[mi].get("roles", [])
	var roles: Array = _role_cache.get(gid, [])
	var all_perms: Array = []
	for role in roles:
		var in_role: bool = role.get("id", "") in my_roles
		if role.get("position", 0) == 0 or in_role:
			for p in role.get("permissions", []):
				if p not in all_perms:
					all_perms.append(p)
	return AccordPermission.has(all_perms, perm)

func update_guild_folder(gid: String, folder_name: String) -> void:
	if _guild_cache.has(gid):
		_guild_cache[gid]["folder"] = folder_name
		AppState.guilds_updated.emit()

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
	connection.disconnect_server(guild_id)

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

func pending_server_index(pending_id: String) -> int:
	if not pending_id.begins_with("__pending_"):
		return -1
	return int(pending_id.trim_prefix("__pending_"))

func reconnect_server(index: int) -> void:
	connection.reconnect_server(index)

## Forwarding method for deferred calls from ClientGateway.
func _handle_gateway_reconnect_failed(
	conn_index: int,
) -> void:
	connection.handle_gateway_reconnect_failed(conn_index)

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

# --- Custom emoji caching (delegates to ClientEmoji) ---

func register_custom_emoji(
	guild_id: String, emoji_id: String,
	emoji_name: String,
) -> void:
	emoji.register(guild_id, emoji_id, emoji_name)

func register_custom_emoji_texture(
	emoji_name: String, texture: Texture2D,
) -> void:
	emoji.register_texture(emoji_name, texture)

func trim_user_cache() -> void:
	emoji.trim_user_cache()

# --- Member index helpers ---

func _rebuild_member_index(guild_id: String) -> void:
	var index: Dictionary = {}
	var members: Array = _member_cache.get(guild_id, [])
	for i in members.size():
		index[members[i].get("id", "")] = i
	_member_id_index[guild_id] = index

func _member_index_for(guild_id: String, user_id: String) -> int:
	var index: Dictionary = _member_id_index.get(guild_id, {})
	return index.get(user_id, -1)
