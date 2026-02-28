extends Node

enum Mode { LIVE, CONNECTING }

# Voice debug logging (configurable via settings, default off).
const VOICE_LOG_PATH := "user://voice_debug.log"
const VOICE_LOG_MAX_SIZE := 1048576 # 1 MB

# Dimension constants
const SPACE_ICON_SIZE := 48
const AVATAR_SIZE := 42
const CHANNEL_ICON_SIZE := 32
const CHANNEL_PANEL_WIDTH := 240
const SPACE_BAR_WIDTH := 68
const MESSAGE_CAP := 50
const MAX_CHANNEL_MESSAGES := 200
const MESSAGE_QUEUE_CAP := 20
const TOUCH_TARGET_MIN := 44
const USER_CACHE_CAP := 500

var app_version: String = ProjectSettings.get_setting(
	"application/config/version", "0.0.0"
)
var debug_voice_logs: bool = false

var mode: Mode = Mode.CONNECTING
var is_shutting_down: bool = false
var current_user: Dictionary = {}
var fetch: ClientFetch
var admin: ClientAdmin
var voice: ClientVoice
var mutations: ClientMutations
var emoji # ClientEmoji (typed reference causes circular dep)
var permissions: RefCounted
var connection: ClientConnection

# --- Data access API (properties) ---

var spaces: Array:
	get: return _space_cache.values()

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
				# Skip if the space is already in the cache (connection
				# in progress but space data already fetched).
				var sid: String = conn.get("space_id", "")
				if not sid.is_empty() and _space_cache.has(sid):
					continue
				if conn["status"] == "error" \
						or conn["status"] == "connecting":
					result.append({
						"id": "__pending_%d" % i,
						"name": servers[i].get(
							"space_name", "Unknown"
						),
						"icon": "",
						"disconnected": true,
						"server_index": i,
					})
			else:
				result.append({
					"id": "__pending_%d" % i,
					"name": servers[i].get(
						"space_name", "Unknown"
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
var _space_cache: Dictionary = {}
var _channel_cache: Dictionary = {}
var _dm_channel_cache: Dictionary = {}
var _message_cache: Dictionary = {}
var _member_cache: Dictionary = {}
var _role_cache: Dictionary = {}
var _voice_state_cache: Dictionary = {} # channel_id -> Array of voice state dicts
var _voice_server_info: Dictionary = {} # stored for Phase 4
var _thread_message_cache: Dictionary = {} # parent_message_id -> Array of message dicts
var _thread_unread: Dictionary = {} # parent_message_id -> true
var _forum_post_cache: Dictionary = {} # channel_id -> Array of post dicts

# Unread / mention tracking
var _unread_channels: Dictionary = {}       # channel_id -> true
var _channel_mention_counts: Dictionary = {} # channel_id -> int

# Message ID -> channel_id index for O(1) lookup
var _message_id_index: Dictionary = {}

# Member ID index: space_id -> { user_id -> array_index }
var _member_id_index: Dictionary = {}

# Routing maps
var _space_to_conn: Dictionary = {}
var _channel_to_space: Dictionary = {}
var _dm_to_conn: Dictionary = {}  # dm_channel_id -> conn index

# Tracks whether auto-reconnect (with re-auth) has been attempted
# per connection index, to prevent infinite loops.
var _auto_reconnect_attempted: Dictionary = {}

# Offline message queue (sent on reconnect)
var _message_queue: Array = []

# Custom emoji download queue to avoid duplicate requests
var _emoji_download_pending: Dictionary = {} # emoji_id -> true

var _gw: ClientGateway
var _voice_session: LiveKitAdapter
var _idle_timer: Timer
var _is_auto_idle: bool = false
var _last_input_time: float = 0.0
var _camera_track  # LiveKitVideoStream (local preview)
var _screen_track  # LiveKitVideoStream (local preview)
var _remote_tracks: Dictionary = {} # user_id -> LiveKitVideoStream
var _speaking_users: Dictionary = {} # user_id -> last_active timestamp (float)
var _speaking_timer: Timer

func _ready() -> void:
	debug_voice_logs = Config.voice.get_debug_logging()
	if debug_voice_logs:
		_rotate_voice_log()
		var f := FileAccess.open(VOICE_LOG_PATH, FileAccess.WRITE)
		if f:
			f.store_line("=== Voice debug start ===")
			f.close()
		_voice_log("voice logger initialized")
		_voice_log(
			"ClassDB.class_exists(LiveKitRoom)=%s" % [
				str(ClassDB.class_exists(&"LiveKitRoom"))
			]
		)
	_gw = ClientGateway.new(self)
	fetch = ClientFetch.new(self)
	admin = ClientAdmin.new(self)
	voice = ClientVoice.new(self)
	mutations = ClientMutations.new(self)
	var PermClass = load(
		"res://scripts/autoload/client_permissions.gd"
	)
	permissions = PermClass.new(self)
	var ClientEmojiClass = load("res://scripts/autoload/client_emoji.gd")
	emoji = ClientEmojiClass.new(self)
	connection = ClientConnection.new(self)
	_voice_session = LiveKitAdapter.new()
	add_child(_voice_session)
	_voice_session.session_state_changed.connect(
		voice.on_session_state_changed
	)
	_voice_session.peer_joined.connect(
		voice.on_peer_joined
	)
	_voice_session.peer_left.connect(
		voice.on_peer_left
	)
	_voice_session.track_received.connect(
		voice.on_track_received
	)
	_voice_session.track_removed.connect(
		voice.on_track_removed
	)
	_voice_session.audio_level_changed.connect(
		voice.on_audio_level_changed
	)
	if debug_voice_logs:
		_voice_log("LiveKitAdapter ready")
	# Speaking debounce timer (checks every 200ms for 300ms silence)
	_speaking_timer = Timer.new()
	_speaking_timer.wait_time = 0.2
	_speaking_timer.timeout.connect(_check_speaking_timeouts)
	add_child(_speaking_timer)
	_speaking_timer.start()
	AppState.channel_selected.connect(_on_channel_selected_clear_unread)
	AppState.profile_switched.connect(_on_profile_switched)
	AppState.server_reconnected.connect(_flush_message_queue)
	AppState.config_changed.connect(voice.on_voice_config_changed)
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
		is_shutting_down = true
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

func _conn_for_space(space_id: String):
	var idx = _space_to_conn.get(space_id, -1)
	if idx == -1 or idx >= _connections.size():
		return null
	return _connections[idx]

func _first_connected_conn():
	for conn in _connections:
		if conn != null \
				and conn.get("status", "") == "connected":
			return conn
	return null

func _conn_for_active_view():
	if AppState.is_dm_mode:
		var cid: String = AppState.current_channel_id
		if not cid.is_empty():
			var conn_idx: int = _dm_to_conn.get(cid, -1)
			if conn_idx != -1 and conn_idx < _connections.size():
				var dm_conn = _connections[conn_idx]
				if dm_conn != null:
					return dm_conn
	var gid: String = AppState.current_space_id
	if not gid.is_empty():
		var space_conn = _conn_for_space(gid)
		if space_conn != null:
			return space_conn
	return _first_connected_conn()

func _client_for_space(gid: String) -> AccordClient:
	var conn = _conn_for_space(gid)
	if conn == null: return null
	return conn["client"]

func _client_for_active_view() -> AccordClient:
	var conn = _conn_for_active_view()
	if conn == null:
		return null
	return conn.get("client", null)

func _client_for_channel(cid: String) -> AccordClient:
	var gid: String = _channel_to_space.get(cid, "")
	if not gid.is_empty():
		return _client_for_space(gid)
	# DM channels aren't in _channel_to_space — route via
	# _dm_to_conn if available, else first connected client
	if _dm_channel_cache.has(cid):
		var conn_idx: int = _dm_to_conn.get(cid, -1)
		if conn_idx != -1 and conn_idx < _connections.size():
			var conn = _connections[conn_idx]
			if conn != null and conn["client"] != null:
				return conn["client"]
		return _first_connected_client()
	return null

func _cdn_for_space(space_id: String) -> String:
	var conn = _conn_for_space(space_id)
	if conn == null: return ""
	return conn["cdn_url"]

func _cdn_for_active_view() -> String:
	var conn = _conn_for_active_view()
	if conn == null:
		return ""
	return conn.get("cdn_url", "")

func _cdn_for_channel(channel_id: String) -> String:
	var gid: String = _channel_to_space.get(channel_id, "")
	if not gid.is_empty():
		return _cdn_for_space(gid)
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

func get_channels_for_space(gid: String) -> Array:
	var result: Array = []
	for ch in _channel_cache.values():
		if ch.get("space_id", "") == gid:
			result.append(ch)
	return result

func get_messages_for_channel(cid: String) -> Array:
	return _message_cache.get(cid, [])

func get_user_by_id(uid: String) -> Dictionary:
	return _user_cache.get(uid, {})

func get_active_user() -> Dictionary:
	var conn = _conn_for_active_view()
	if conn != null:
		var uid: String = conn.get("user_id", "")
		if not uid.is_empty() and _user_cache.has(uid):
			return _user_cache[uid]
		var user: Dictionary = conn.get("user", {})
		if user.size() > 0:
			return user
	return current_user

func get_space_by_id(gid: String) -> Dictionary:
	return _space_cache.get(gid, {})

func get_user_for_space(space_id: String) -> Dictionary:
	var conn = _conn_for_space(space_id)
	if conn == null:
		return {}
	var uid: String = conn.get("user_id", "")
	if not uid.is_empty() and _user_cache.has(uid):
		return _user_cache[uid]
	return conn.get("user", {})

func get_members_for_space(gid: String) -> Array:
	return _member_cache.get(gid, [])

func get_roles_for_space(gid: String) -> Array:
	return _role_cache.get(gid, [])

func get_messages_for_thread(parent_id: String) -> Array:
	return _thread_message_cache.get(parent_id, [])

func get_forum_posts(channel_id: String) -> Array:
	return _forum_post_cache.get(channel_id, [])

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

func is_user_speaking(user_id: String) -> bool:
	return _speaking_users.has(user_id)

func _check_speaking_timeouts() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var expired: Array = []
	for uid in _speaking_users:
		if now - _speaking_users[uid] > 0.3:
			expired.append(uid)
	for uid in expired:
		_speaking_users.erase(uid)
		if debug_voice_logs:
			_voice_log("speaking_stop uid=%s" % uid)
		AppState.speaking_changed.emit(uid, false)

func _voice_log(message: String) -> void:
	if not debug_voice_logs:
		return
	var line := "[VoiceDebug] " + message
	print(line)
	# Rotate if file exceeds max size
	if FileAccess.file_exists(VOICE_LOG_PATH):
		var check := FileAccess.open(VOICE_LOG_PATH, FileAccess.READ)
		if check:
			var size := check.get_length()
			check.close()
			if size > VOICE_LOG_MAX_SIZE:
				_rotate_voice_log()
	var f := FileAccess.open(VOICE_LOG_PATH, FileAccess.READ_WRITE)
	if f:
		f.seek_end()
		f.store_line(line)
		f.close()


func _rotate_voice_log() -> void:
	if not FileAccess.file_exists(VOICE_LOG_PATH):
		return
	var bak_path := VOICE_LOG_PATH + ".1"
	var bak_global := ProjectSettings.globalize_path(bak_path)
	if FileAccess.file_exists(bak_path):
		DirAccess.remove_absolute(bak_global)
	DirAccess.rename_absolute(
		ProjectSettings.globalize_path(VOICE_LOG_PATH),
		bak_global
	)

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
	attachments: Array = [], thread_id: String = "",
	title: String = ""
) -> bool:
	return await mutations.send_message_to_channel(
		cid, content, reply_to, attachments, thread_id, title
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

func start_screen_share(source: Dictionary) -> void:
	voice.start_screen_share(source)

func stop_screen_share() -> void:
	voice.stop_screen_share()

func get_camera_track():
	return _camera_track

func get_screen_track():
	return _screen_track

func get_remote_track(
	user_id: String,
):
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
	await mutations.dm.create_dm(user_id)

func create_group_dm(user_ids: Array) -> void:
	await mutations.dm.create_group_dm(user_ids)

func add_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	return await mutations.dm.add_dm_member(
		channel_id, user_id
	)

func remove_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	return await mutations.dm.remove_dm_member(
		channel_id, user_id
	)

func rename_group_dm(
	channel_id: String, new_name: String,
) -> bool:
	return await mutations.dm.rename_group_dm(
		channel_id, new_name
	)

func close_dm(channel_id: String) -> void:
	await mutations.dm.close_dm(channel_id)

func has_permission(gid: String, perm: String) -> bool:
	return permissions.has_permission(gid, perm)

func has_channel_permission(
	gid: String, channel_id: String, perm: String,
) -> bool:
	return permissions.has_channel_permission(gid, channel_id, perm)

func update_space_folder(gid: String, folder_name: String) -> void:
	if _space_cache.has(gid):
		_space_cache[gid]["folder"] = folder_name
		AppState.spaces_updated.emit()

func is_space_owner(gid: String) -> bool:
	return permissions.is_space_owner(gid)

func get_my_highest_role_position(gid: String) -> int:
	return permissions.get_my_highest_role_position(gid)

# --- Unread / mention tracking ---

func _on_channel_selected_clear_unread(cid: String) -> void:
	if not _unread_channels.has(cid):
		return
	_unread_channels.erase(cid)
	_channel_mention_counts.erase(cid)
	# Update the cached channel dict
	if _channel_cache.has(cid):
		_channel_cache[cid]["unread"] = false
		var gid: String = _channel_cache[cid].get("space_id", "")
		_update_space_unread(gid)
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
		var gid: String = _channel_cache[cid].get("space_id", "")
		_update_space_unread(gid)
		AppState.channels_updated.emit(gid)
		AppState.spaces_updated.emit()
	elif _dm_channel_cache.has(cid):
		_dm_channel_cache[cid]["unread"] = true
		AppState.dm_channels_updated.emit()

func _update_space_unread(gid: String) -> void:
	if gid.is_empty() or not _space_cache.has(gid):
		return
	var has_unread := false
	var total_mentions := 0
	for ch_id in _channel_cache:
		var ch: Dictionary = _channel_cache[ch_id]
		if ch.get("space_id", "") != gid:
			continue
		if _unread_channels.has(ch_id):
			has_unread = true
		total_mentions += _channel_mention_counts.get(ch_id, 0)
	_space_cache[gid]["unread"] = has_unread
	_space_cache[gid]["mentions"] = total_mentions

# --- Server management ---

func disconnect_all() -> void:
	connection.disconnect_all()

func disconnect_server(space_id: String) -> void:
	connection.disconnect_server(space_id)

# --- Connection status helpers ---

func is_space_connected(gid: String) -> bool:
	var conn = _conn_for_space(gid)
	return conn != null and conn["status"] == "connected"

func get_space_connection_status(gid: String) -> String:
	var conn = _conn_for_space(gid)
	if conn == null: return "none"
	return conn.get("status", "none")

func is_space_syncing(gid: String) -> bool:
	var conn = _conn_for_space(gid)
	if conn == null:
		return false
	return conn.get("_syncing", false)

func get_conn_index_for_space(gid: String) -> int:
	return _space_to_conn.get(gid, -1)

func reconnect_server(index: int) -> void:
	connection.reconnect_server(index)

func _flush_message_queue(space_id: String) -> void:
	var to_send: Array = []
	var remaining: Array = []
	for entry in _message_queue:
		var gid: String = _channel_to_space.get(
			entry["channel_id"], ""
		)
		if gid == space_id:
			to_send.append(entry)
		else:
			remaining.append(entry)
	_message_queue = remaining
	for entry in to_send:
		await send_message_to_channel(
			entry["channel_id"], entry["content"],
			entry.get("reply_to", ""),
			entry.get("attachments", [])
		)

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
	space_id: String, emoji_id: String,
	emoji_name: String,
) -> void:
	emoji.register(space_id, emoji_id, emoji_name)

func register_custom_emoji_texture(
	emoji_name: String, texture: Texture2D,
) -> void:
	emoji.register_texture(emoji_name, texture)

func trim_user_cache() -> void:
	emoji.trim_user_cache()

# --- Member index helpers ---

func _rebuild_member_index(space_id: String) -> void:
	var index: Dictionary = {}
	var members: Array = _member_cache.get(space_id, [])
	for i in members.size():
		index[members[i].get("id", "")] = i
	_member_id_index[space_id] = index

func _member_index_for(space_id: String, user_id: String) -> int:
	var index: Dictionary = _member_id_index.get(space_id, {})
	return index.get(user_id, -1)

func _on_profile_switched() -> void:
	disconnect_all()
	_forum_post_cache.clear()
	# Reset AppState navigation state
	AppState.current_space_id = ""
	AppState.current_channel_id = ""
	AppState.is_dm_mode = false
	AppState.replying_to_message_id = ""
	AppState.editing_message_id = ""
	# Reconnect with new config
	if Config.has_servers():
		for i in Config.get_servers().size():
			connect_server(i)
