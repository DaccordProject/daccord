extends Node

enum Mode { LIVE, CONNECTING }

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
var unread: RefCounted # ClientUnread (loaded dynamically to avoid class_name dep)
var emoji # ClientEmoji (typed reference causes circular dep)
var permissions: RefCounted
var connection: ClientConnection
var relationships: ClientRelationships
var web_links: ClientWebLinks
var plugins: ClientPlugins
var test_api: ClientTestApi
var mcp: ClientMcp

# --- Data access API (properties) ---

var spaces: Array:
	get: return _space_cache.values()

var channels: Array:
	get: return _channel_cache.values()

var dm_channels: Array:
	get:
		return _dm_channel_cache.values().filter(func(dm):
			if dm.get("is_group", false):
				return true
			var user_id: String = dm.get("user", {}).get("id", "")
			return user_id.is_empty() or not relationships.is_user_blocked(user_id)
		)

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
						"connecting": conn["status"] == "connecting",
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
					"connecting": false,
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
var _thread_mention_count: Dictionary = {} # parent_message_id -> int
var _forum_post_cache: Dictionary = {} # channel_id -> Array of post dicts

# Relationship cache: "{conn_index}:{user_id}" -> relationship dict
var _relationship_cache: Dictionary = {}

# Channel mute tracking (server-side, per-user)
var _muted_channels: Dictionary = {}        # channel_id -> true

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
var _voice_session # LiveKitAdapter on desktop/mobile, WebVoiceSession on web
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
	_gw = ClientGateway.new(self)
	fetch = ClientFetch.new(self)
	admin = ClientAdmin.new(self)
	voice = ClientVoice.new(self)
	mutations = ClientMutations.new(self)
	if debug_voice_logs:
		voice._rotate_voice_log()
		var f := FileAccess.open(
			ClientVoice.VOICE_LOG_PATH, FileAccess.WRITE
		)
		if f:
			f.store_line("=== Voice debug start ===")
			f.close()
		voice._voice_log("voice logger initialized")
		voice._voice_log(
			"ClassDB.class_exists(LiveKitRoom)=%s" % [
				str(ClassDB.class_exists(&"LiveKitRoom"))
			]
		)
	unread = load("res://scripts/autoload/client_unread.gd").new(self)
	var PermClass = load(
		"res://scripts/autoload/client_permissions.gd"
	)
	permissions = PermClass.new(self)
	var ClientEmojiClass = load("res://scripts/autoload/client_emoji.gd")
	emoji = ClientEmojiClass.new(self)
	connection = ClientConnection.new(self)
	relationships = ClientRelationships.new(self)
	web_links = ClientWebLinks.new(self)
	plugins = ClientPlugins.new(self)
	web_links.setup()
	# On Android, request dangerous permissions (microphone, camera) early so
	# they are granted before the user tries to join a voice channel.
	if OS.get_name() == "Android":
		OS.request_permissions()
	if OS.get_name() == "Web":
		var WebVoiceSessionClass = load(
			"res://scripts/autoload/web_voice_session.gd"
		)
		_voice_session = WebVoiceSessionClass.new()
	else:
		var LiveKitAdapterClass = load(
			"res://scripts/autoload/livekit_adapter.gd"
		)
		_voice_session = LiveKitAdapterClass.new()
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
		voice._voice_log(
			"voice session ready platform=%s" % OS.get_name()
		)
	# Speaking debounce timer (checks every 200ms for 300ms silence)
	_speaking_timer = Timer.new()
	_speaking_timer.wait_time = 0.2
	_speaking_timer.timeout.connect(_check_speaking_timeouts)
	add_child(_speaking_timer)
	_speaking_timer.start()
	AppState.channel_selected.connect(unread.on_channel_selected_clear_unread)
	AppState.profile_switched.connect(connection.on_profile_switched)
	AppState.server_reconnected.connect(connection.flush_message_queue)
	AppState.config_changed.connect(voice.on_voice_config_changed)
	# Idle timer setup
	_last_input_time = Time.get_ticks_msec() / 1000.0
	_idle_timer = Timer.new()
	_idle_timer.wait_time = 10.0
	_idle_timer.timeout.connect(_check_idle)
	add_child(_idle_timer)
	_idle_timer.start()
	# Test API subsystem (for CI / developer mode)
	if _is_test_api_enabled():
		test_api = ClientTestApi.new(self)
		var token: String = ""
		var require_auth: bool = false
		if not _has_cli_flag("--test-api-no-auth"):
			token = Config.developer.get_test_api_token()
			if not token.is_empty():
				require_auth = true
		var verbose: bool = _has_cli_flag("--test-api-verbose")
		test_api.start(
			_get_test_api_port(), token, require_auth, verbose
		)
	# MCP subsystem (delegates to test_api internally)
	if _is_mcp_enabled():
		# MCP needs a test_api instance as its backend
		if test_api == null:
			test_api = ClientTestApi.new(self)
			# Start without HTTP listener — MCP calls methods
			# directly, no need for a second HTTP port
		var mcp_token: String = Config.developer.get_mcp_token()
		mcp = ClientMcp.new(self, test_api)
		mcp.start(Config.developer.get_mcp_port(), mcp_token)
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

func _process(_delta: float) -> void:
	if test_api != null:
		test_api.poll()
	if mcp != null:
		mcp.poll()

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
		if mcp != null:
			mcp.stop()
		if test_api != null:
			test_api.stop()
		for conn in _connections:
			if conn != null and conn["client"] != null:
				conn["client"].logout()
		get_tree().quit()

func _is_test_api_enabled() -> bool:
	# Strip test API from release builds
	if OS.has_feature("release"):
		return false
	if _has_cli_flag("--test-api") \
			or OS.get_environment("DACCORD_TEST_API") == "true":
		return true
	return Config.developer.get_developer_mode() \
			and Config.developer.get_test_api_enabled()

func _is_mcp_enabled() -> bool:
	if OS.has_feature("release"):
		return false
	return Config.developer.get_developer_mode() \
			and Config.developer.get_mcp_enabled()

func _get_test_api_port() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	var idx: int = _find_cli_arg("--test-api-port")
	if idx >= 0 and idx + 1 < args.size():
		return args[idx + 1].to_int()
	var env: String = OS.get_environment("DACCORD_TEST_API_PORT")
	if not env.is_empty():
		return env.to_int()
	return Config.developer.get_test_api_port()

func _has_cli_flag(flag: String) -> bool:
	return flag in OS.get_cmdline_args()

func _find_cli_arg(arg: String) -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		if args[i] == arg:
			return i
	return -1

func _derive_gateway_url(base_url: String) -> String:
	var gw := base_url.replace("https://", "wss://").replace("http://", "ws://")
	return gw + "/ws"

func _derive_cdn_url(base_url: String) -> String:
	return base_url + "/cdn"

# --- Multi-server connection ---

func connect_server(index: int, invite_code: String = "") -> Dictionary:
	return await connection.connect_server(index, invite_code)

func connect_guest(
	url: String, token: String, sid: String,
	expires_at: String = "",
) -> Dictionary:
	return await connection.connect_guest(url, token, sid, expires_at)

func upgrade_guest_connection(
	url: String, token: String, space: String, user: String, dn: String = "",
) -> Dictionary:
	return await connection.upgrade_guest_connection(url, token, space, user, dn)

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

func find_user_id_by_username(username: String) -> String:
	var lower: String = username.to_lower()
	for uid: String in _user_cache:
		var u: Dictionary = _user_cache[uid]
		if u.get("username", "").to_lower() == lower \
				or u.get("display_name", "").to_lower() == lower:
			return uid
	return ""

func send_presence(status: String, activity: Dictionary = {}) -> void:
	for conn in _connections:
		if conn == null or conn.get("status", "") != "connected":
			continue
		var client: AccordClient = conn.get("client")
		if client != null:
			client.update_presence(status, activity)

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
			voice._voice_log("speaking_stop uid=%s" % uid)
		AppState.speaking_changed.emit(uid, false)

func search_messages(
	gid: String, q: String, filters: Dictionary = {},
) -> Dictionary:
	return await mutations.search_messages(
		gid, q, filters
	)

func send_message_to_channel(
	cid: String, content: String, reply_to: String = "",
	attachments: Array = [], thread_id: String = "",
	title: String = ""
) -> bool:
	if AppState.is_guest_mode:
		return false
	return await mutations.send_message_to_channel(
		cid, content, reply_to, attachments, thread_id, title
	)

func update_message_content(
	mid: String, new_content: String
) -> bool:
	if AppState.is_guest_mode:
		return false
	return await mutations.update_message_content(
		mid, new_content
	)

func remove_message(mid: String) -> bool:
	if AppState.is_guest_mode:
		return false
	return await mutations.remove_message(mid)

func add_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	if AppState.is_guest_mode:
		return
	await mutations.add_reaction(cid, mid, emoji)

func remove_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	if AppState.is_guest_mode:
		return
	await mutations.remove_reaction(cid, mid, emoji)

func remove_all_reactions(
	cid: String, mid: String,
) -> void:
	await mutations.remove_all_reactions(cid, mid)

func update_presence(
	status: int, activity: Dictionary = {},
) -> void:
	mutations.update_presence(status, activity)

func send_typing(cid: String, thread_id: String = "") -> void:
	if AppState.is_guest_mode:
		return
	mutations.send_typing(cid, thread_id)

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

func get_remote_track(user_id: String):
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
	if AppState.is_guest_mode:
		return
	await mutations.dm.create_dm(user_id)

func create_group_dm(user_ids: Array) -> void:
	await mutations.dm.create_group_dm(user_ids)

func add_dm_member(channel_id: String, user_id: String) -> bool:
	return await mutations.dm.add_dm_member(channel_id, user_id)

func remove_dm_member(channel_id: String, user_id: String) -> bool:
	return await mutations.dm.remove_dm_member(channel_id, user_id)

func rename_group_dm(channel_id: String, new_name: String) -> bool:
	return await mutations.dm.rename_group_dm(channel_id, new_name)

func close_dm(channel_id: String) -> void:
	await mutations.dm.close_dm(channel_id)

# --- Channel mute API ---

func is_channel_muted(channel_id: String) -> bool:
	if _muted_channels.has(channel_id):
		return true
	# Check if parent category is muted (inherited mute)
	var ch: Dictionary = _channel_cache.get(channel_id, {})
	var parent_id: String = ch.get("parent_id", "")
	if not parent_id.is_empty() and _muted_channels.has(parent_id):
		return true
	return false

func mute_channel(channel_id: String) -> void:
	var client: AccordClient = _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return
	var result: RestResult = await client.channels.mute(channel_id)
	if result.ok:
		_muted_channels[channel_id] = true
		AppState.channel_mutes_updated.emit()
	else:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[Client] Failed to mute channel: ", err)

func unmute_channel(channel_id: String) -> void:
	var client: AccordClient = _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return
	var result: RestResult = await client.channels.unmute(channel_id)
	if result.ok:
		_muted_channels.erase(channel_id)
		AppState.channel_mutes_updated.emit()
	else:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[Client] Failed to unmute channel: ", err)

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

## Returns the color of the user's highest-positioned role that has a non-zero
## color in the given space, or null if no colored role exists.
func get_role_color_for_user(gid: String, user_id: String) -> Variant:
	var mi: int = _member_index_for(gid, user_id)
	if mi == -1:
		return null
	var member_roles: Array = _member_cache.get(gid, [])[mi].get("roles", [])
	var roles: Array = _role_cache.get(gid, [])
	var best_color: int = 0
	var best_position: int = -1
	for role in roles:
		var rid: String = role.get("id", "")
		if rid not in member_roles:
			continue
		var c: int = role.get("color", 0)
		if c == 0:
			continue
		var pos: int = role.get("position", 0)
		if pos > best_position:
			best_position = pos
			best_color = c
	if best_color == 0:
		return null
	return Color.hex(best_color)

# --- Unread / mention tracking (delegates to ClientUnread) ---

func clear_channel_unread(cid: String) -> void:
	unread.clear_channel_unread(cid)

func mark_channel_unread(cid: String, is_mention: bool = false) -> void:
	unread.mark_channel_unread(cid, is_mention)

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

func get_base_url_for_space(space_id: String) -> String:
	var conn = _conn_for_space(space_id)
	if conn == null:
		return ""
	var cfg: Dictionary = conn.get("config", {})
	return cfg.get("base_url", "")

func is_nsfw_acked(space_id: String) -> bool:
	var base_url := get_base_url_for_space(space_id)
	if base_url.is_empty():
		return false
	return Config.has_nsfw_ack(base_url)

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
	for ch_id in _message_cache:
		for msg in _message_cache[ch_id]:
			if msg.get("id", "") == mid:
				return ch_id
	return ""

func _rebuild_member_index(space_id: String) -> void:
	var index: Dictionary = {}
	var members: Array = _member_cache.get(space_id, [])
	for i in members.size():
		index[members[i].get("id", "")] = i
	_member_id_index[space_id] = index

func _member_index_for(space_id: String, user_id: String) -> int:
	var index: Dictionary = _member_id_index.get(space_id, {})
	return index.get(user_id, -1)

