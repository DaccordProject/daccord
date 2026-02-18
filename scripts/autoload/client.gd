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

var mode: Mode = Mode.CONNECTING
var current_user: Dictionary = {}

# --- Data access API (properties) ---

var guilds: Array:
	get:
		return _guild_cache.values()

var channels: Array:
	get:
		return _channel_cache.values()

var dm_channels: Array:
	get:
		return _dm_channel_cache.values()

# Per-server connection state
# Each entry: {
#   "config": Dictionary,         # { base_url, token, guild_name }
#   "client": AccordClient,       # the AccordClient instance
#   "guild_id": String,           # resolved guild ID (from guild_name)
#   "cdn_url": String,            # base_url + "/cdn"
#   "status": String,             # "connecting", "connected", "error"
# }
var _connections: Array = []

# Caches (keyed by ID)
var _user_cache: Dictionary = {}
var _guild_cache: Dictionary = {}
var _channel_cache: Dictionary = {}
var _dm_channel_cache: Dictionary = {}
var _message_cache: Dictionary = {} # channel_id -> Array of message dicts
var _member_cache: Dictionary = {} # guild_id -> Array of user dicts
var _role_cache: Dictionary = {} # guild_id -> Array of role dicts

# Maps guild_id -> connection index for routing
var _guild_to_conn: Dictionary = {}
# Maps channel_id -> guild_id for routing
var _channel_to_guild: Dictionary = {}

var _gw: ClientGateway

func _ready() -> void:
	_gw = ClientGateway.new(self)
	if Config.has_servers():
		for i in Config.get_servers().size():
			connect_server(i)

func _derive_gateway_url(base_url: String) -> String:
	var gw := base_url.replace("https://", "wss://").replace("http://", "ws://")
	return gw + "/ws"

func _derive_cdn_url(base_url: String) -> String:
	return base_url + "/cdn"

# --- Multi-server connection ---

func connect_server(index: int, invite_code: String = "") -> Dictionary:
	var servers := Config.get_servers()
	if index < 0 or index >= servers.size():
		return {"error": "Invalid server index"}

	var server_config: Dictionary = servers[index]
	var base_url: String = server_config["base_url"]
	var token: String = server_config["token"]
	var guild_name: String = server_config["guild_name"]
	var gateway_url := _derive_gateway_url(base_url)
	var cdn_url := _derive_cdn_url(base_url)

	var conn := {
		"config": server_config,
		"client": null,
		"guild_id": "",
		"cdn_url": cdn_url,
		"status": "connecting",
	}

	# Ensure the array is big enough
	while _connections.size() <= index:
		_connections.append(null)
	_connections[index] = conn

	print("[Client] Connecting to server: ", base_url)

	var client := AccordClient.new()
	client.token = token
	client.token_type = "Bearer"
	client.base_url = base_url
	client.gateway_url = gateway_url
	client.cdn_url = cdn_url
	client.intents = GatewayIntents.default() + [
		GatewayIntents.MESSAGE_TYPING,
		GatewayIntents.DIRECT_MESSAGES,
		GatewayIntents.DM_TYPING,
		GatewayIntents.MEMBERS,
		GatewayIntents.PRESENCES,
	]
	add_child(client)
	conn["client"] = client

	# Fetch current user
	var me_result := await client.users.get_me()
	if not me_result.ok and base_url.begins_with("https://"):
		# HTTPS failed -- retry with HTTP (common for local dev servers)
		print("[Client] HTTPS failed for ", base_url, ", falling back to HTTP")
		client.queue_free()
		base_url = base_url.replace("https://", "http://")
		gateway_url = _derive_gateway_url(base_url)
		cdn_url = _derive_cdn_url(base_url)
		conn["cdn_url"] = cdn_url
		client = AccordClient.new()
		client.token = token
		client.token_type = "Bearer"
		client.base_url = base_url
		client.gateway_url = gateway_url
		client.cdn_url = cdn_url
		client.intents = GatewayIntents.default() + [
			GatewayIntents.MESSAGE_TYPING,
			GatewayIntents.DIRECT_MESSAGES,
			GatewayIntents.DM_TYPING,
			GatewayIntents.MEMBERS,
			GatewayIntents.PRESENCES,
		]
		add_child(client)
		conn["client"] = client
		me_result = await client.users.get_me()
	if not me_result.ok:
		var err_msg: String = me_result.error.message if me_result.error else "Failed to authenticate"
		push_error("[Client] Auth failed for ", base_url, ": ", err_msg)
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	# If we fell back to HTTP, update the saved config so future startups use it directly
	if base_url != server_config["base_url"]:
		Config.update_server_url(index, base_url)

	var me_user: AccordUser = me_result.data
	var me_dict := ClientModels.user_to_dict(me_user, ClientModels.UserStatus.ONLINE, cdn_url)
	_user_cache[me_user.id] = me_dict
	if current_user.is_empty():
		current_user = me_dict

	print("[Client] Logged in as: ", me_dict["display_name"], " on ", base_url)

	# Accept invite if provided (non-fatal -- user may already be a member)
	if not invite_code.is_empty():
		var invite_result := await client.invites.accept(invite_code)
		if not invite_result.ok:
			var inv_err: String = invite_result.error.message if invite_result.error else "unknown"
			push_warning("[Client] Invite accept failed (non-fatal): ", inv_err)

	# Find the guild matching guild_name
	var spaces_result := await client.users.list_spaces()
	if not spaces_result.ok:
		var err_msg: String = (
			spaces_result.error.message
			if spaces_result.error
			else "Failed to list guilds"
		)
		push_error("[Client] Failed to list guilds on ", base_url, ": ", err_msg)
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	var found_guild_id := ""
	for space in spaces_result.data:
		var space_obj: AccordSpace = space
		if space_obj.slug == guild_name:
			found_guild_id = space_obj.id
			var d := ClientModels.space_to_guild_dict(space_obj)
			_guild_cache[d["id"]] = d
			break

	if found_guild_id.is_empty():
		var err_msg := "Guild '%s' not found on %s" % [guild_name, base_url]
		push_error("[Client] ", err_msg)
		conn["status"] = "error"
		client.queue_free()
		conn["client"] = null
		return {"error": err_msg}

	conn["guild_id"] = found_guild_id
	_guild_to_conn[found_guild_id] = index

	# Connect gateway signals (scoped to this connection via bind)
	client.ready_received.connect(_gw.on_gateway_ready.bind(index))
	client.message_create.connect(_gw.on_message_create.bind(index))
	client.message_update.connect(_gw.on_message_update.bind(index))
	client.message_delete.connect(_gw.on_message_delete)
	client.typing_start.connect(_gw.on_typing_start)
	client.presence_update.connect(_gw.on_presence_update.bind(index))
	client.member_join.connect(_gw.on_member_join.bind(index))
	client.member_leave.connect(_gw.on_member_leave.bind(index))
	client.member_update.connect(_gw.on_member_update.bind(index))
	client.space_create.connect(_gw.on_space_create.bind(index))
	client.space_update.connect(_gw.on_space_update)
	client.space_delete.connect(_gw.on_space_delete)
	client.channel_create.connect(_gw.on_channel_create.bind(index))
	client.channel_update.connect(_gw.on_channel_update.bind(index))
	client.channel_delete.connect(_gw.on_channel_delete)
	client.role_create.connect(_gw.on_role_create.bind(index))
	client.role_update.connect(_gw.on_role_update.bind(index))
	client.role_delete.connect(_gw.on_role_delete.bind(index))
	client.ban_create.connect(_gw.on_ban_create.bind(index))
	client.ban_delete.connect(_gw.on_ban_delete.bind(index))
	client.invite_create.connect(_gw.on_invite_create.bind(index))
	client.invite_delete.connect(_gw.on_invite_delete.bind(index))
	client.emoji_update.connect(_gw.on_emoji_update.bind(index))

	client.login()

	conn["status"] = "connected"
	mode = Mode.LIVE
	AppState.guilds_updated.emit()

	return {"guild_id": found_guild_id}

# --- Client routing ---

func _conn_for_guild(guild_id: String):
	var idx = _guild_to_conn.get(guild_id, -1)
	if idx == -1 or idx >= _connections.size():
		return null
	return _connections[idx]

func _client_for_guild(guild_id: String) -> AccordClient:
	var conn = _conn_for_guild(guild_id)
	if conn == null:
		return null
	return conn["client"]

func _client_for_channel(channel_id: String) -> AccordClient:
	var guild_id: String = _channel_to_guild.get(channel_id, "")
	return _client_for_guild(guild_id)

func _cdn_for_guild(guild_id: String) -> String:
	var conn = _conn_for_guild(guild_id)
	if conn == null:
		return ""
	return conn["cdn_url"]

func _cdn_for_channel(channel_id: String) -> String:
	var guild_id: String = _channel_to_guild.get(channel_id, "")
	return _cdn_for_guild(guild_id)

func _all_failed() -> bool:
	for c in _connections:
		if c != null and c["status"] != "error":
			return false
	return true

func _first_connected_client() -> AccordClient:
	for conn in _connections:
		if conn != null and conn["status"] == "connected" and conn["client"] != null:
			return conn["client"]
	return null

func _first_connected_cdn() -> String:
	for conn in _connections:
		if conn != null and conn["status"] == "connected":
			return conn["cdn_url"]
	return ""

# --- Data access API ---

func get_channels_for_guild(guild_id: String) -> Array:
	var result: Array = []
	for ch in _channel_cache.values():
		if ch.get("guild_id", "") == guild_id:
			result.append(ch)
	return result

func get_messages_for_channel(channel_id: String) -> Array:
	return _message_cache.get(channel_id, [])

func get_user_by_id(user_id: String) -> Dictionary:
	return _user_cache.get(user_id, {})

func get_guild_by_id(guild_id: String) -> Dictionary:
	return _guild_cache.get(guild_id, {})

func get_members_for_guild(guild_id: String) -> Array:
	return _member_cache.get(guild_id, [])

func get_roles_for_guild(guild_id: String) -> Array:
	return _role_cache.get(guild_id, [])

func get_message_by_id(message_id: String) -> Dictionary:
	for ch_messages in _message_cache.values():
		for msg in ch_messages:
			if msg.get("id", "") == message_id:
				return msg
	return {}

# --- Mutation API ---

func send_message_to_channel(channel_id: String, content: String, reply_to: String = "") -> void:
	var client := _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection found for channel: ", channel_id)
		return
	var data := {"content": content}
	if not reply_to.is_empty():
		data["reply_to"] = reply_to
	var result := await client.messages.create(channel_id, data)
	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to send message: ",
			err_msg
		)

func update_message_content(message_id: String, new_content: String) -> void:
	var channel_id := _find_channel_for_message(message_id)
	if channel_id.is_empty():
		push_error("[Client] Cannot find channel for message: ", message_id)
		return
	var client := _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection found for channel: ", channel_id)
		return
	var result := await client.messages.edit(
		channel_id, message_id, {"content": new_content}
	)
	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to edit message: ",
			err_msg
		)

func remove_message(message_id: String) -> void:
	var channel_id := _find_channel_for_message(message_id)
	if channel_id.is_empty():
		push_error("[Client] Cannot find channel for message: ", message_id)
		return
	var client := _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection found for channel: ", channel_id)
		return
	var result := await client.messages.delete(
		channel_id, message_id
	)
	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to delete message: ",
			err_msg
		)

func send_typing(channel_id: String) -> void:
	var client := _client_for_channel(channel_id)
	if client != null:
		client.messages.typing(channel_id)

# --- Fetch methods ---

func fetch_guilds() -> void:
	for conn in _connections:
		if conn == null or conn["status"] != "connected" or conn["client"] == null:
			continue
		var result = await conn["client"].users.list_spaces()
		if result.ok:
			for space in result.data:
				var space_obj: AccordSpace = space
				if space_obj.id == conn["guild_id"]:
					var d := ClientModels.space_to_guild_dict(space_obj)
					_guild_cache[d["id"]] = d
	AppState.guilds_updated.emit()

func fetch_channels(guild_id: String) -> void:
	var client := _client_for_guild(guild_id)
	if client == null:
		return
	var result := await client.spaces.list_channels(guild_id)
	if result.ok:
		# Remove old channels for this guild
		var to_remove: Array = []
		for ch_id in _channel_cache:
			if _channel_cache[ch_id].get("guild_id", "") == guild_id:
				to_remove.append(ch_id)
		for ch_id in to_remove:
			_channel_cache.erase(ch_id)
			_channel_to_guild.erase(ch_id)
		# Add new channels
		for channel in result.data:
			var d := ClientModels.channel_to_dict(channel)
			_channel_cache[d["id"]] = d
			_channel_to_guild[d["id"]] = guild_id
		AppState.channels_updated.emit(guild_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch channels: ",
			err_msg
		)

func fetch_dm_channels() -> void:
	var client := _first_connected_client()
	if client == null:
		return
	var cdn_url := _first_connected_cdn()
	var result := await client.users.list_channels()
	if result.ok:
		_dm_channel_cache.clear()
		for channel in result.data:
			if channel.recipients != null and channel.recipients is Array:
				for recipient in channel.recipients:
					if not _user_cache.has(recipient.id):
						_user_cache[recipient.id] = ClientModels.user_to_dict(
							recipient,
							ClientModels.UserStatus.OFFLINE,
							cdn_url
						)
			var d := ClientModels.dm_channel_to_dict(channel, _user_cache)
			_dm_channel_cache[d["id"]] = d
		AppState.dm_channels_updated.emit()
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch DM channels: ",
			err_msg
		)

func fetch_messages(channel_id: String) -> void:
	var client := _client_for_channel(channel_id)
	if client == null:
		return
	var cdn_url := _cdn_for_channel(channel_id)
	var result := await client.messages.list(channel_id, {"limit": MESSAGE_CAP})
	if result.ok:
		var msgs: Array = []
		for msg in result.data:
			var accord_msg: AccordMessage = msg
			if not _user_cache.has(accord_msg.author_id):
				var user_result := await client.users.fetch(accord_msg.author_id)
				if user_result.ok:
					_user_cache[accord_msg.author_id] = ClientModels.user_to_dict(
						user_result.data,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
			msgs.append(ClientModels.message_to_dict(accord_msg, _user_cache))
		_message_cache[channel_id] = msgs
		AppState.messages_updated.emit(channel_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch messages: ",
			err_msg
		)

func fetch_members(guild_id: String) -> void:
	var client := _client_for_guild(guild_id)
	if client == null:
		return
	var cdn_url := _cdn_for_guild(guild_id)
	var result := await client.members.list(guild_id, {"limit": 1000})
	if result.ok:
		var members: Array = []
		for member in result.data:
			var accord_member: AccordMember = member
			if not _user_cache.has(accord_member.user_id):
				var user_result := await client.users.fetch(accord_member.user_id)
				if user_result.ok:
					_user_cache[accord_member.user_id] = ClientModels.user_to_dict(
						user_result.data,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
			members.append(ClientModels.member_to_dict(accord_member, _user_cache))
		_member_cache[guild_id] = members
		AppState.members_updated.emit(guild_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error("[Client] Failed to fetch members: ", err_msg)

func fetch_roles(guild_id: String) -> void:
	var client := _client_for_guild(guild_id)
	if client == null:
		return
	var result := await client.roles.list(guild_id)
	if result.ok:
		var roles: Array = []
		for role in result.data:
			roles.append(ClientModels.role_to_dict(role))
		_role_cache[guild_id] = roles
		AppState.roles_updated.emit(guild_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error("[Client] Failed to fetch roles: ", err_msg)

# --- Permission helpers ---

func has_permission(guild_id: String, perm: String) -> bool:
	var my_id: String = current_user.get("id", "")
	# Space owner has all permissions
	var guild: Dictionary = _guild_cache.get(guild_id, {})
	if guild.get("owner_id", "") == my_id:
		return true
	# Find current user's role IDs from member cache
	var members: Array = _member_cache.get(guild_id, [])
	var my_roles: Array = []
	for m in members:
		if m.get("id", "") == my_id:
			my_roles = m.get("roles", [])
			break
	# Collect permissions from @everyone (position 0) + assigned roles
	var roles: Array = _role_cache.get(guild_id, [])
	var all_perms: Array = []
	for role in roles:
		if role.get("position", 0) == 0 or role.get("id", "") in my_roles:
			for p in role.get("permissions", []):
				if p not in all_perms:
					all_perms.append(p)
	return AccordPermission.has(all_perms, perm)

func is_space_owner(guild_id: String) -> bool:
	var guild: Dictionary = _guild_cache.get(guild_id, {})
	return guild.get("owner_id", "") == current_user.get("id", "")

# --- Admin API wrappers ---

func update_space(guild_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.spaces.update(guild_id, data)

func delete_space(guild_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.spaces.delete(guild_id)

func create_channel(guild_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.spaces.create_channel(guild_id, data)

func update_channel(channel_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return null
	return await client.channels.update(channel_id, data)

func delete_channel(channel_id: String) -> RestResult:
	var client := _client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return null
	return await client.channels.delete(channel_id)

func create_role(guild_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.roles.create(guild_id, data)

func update_role(guild_id: String, role_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.roles.update(guild_id, role_id, data)

func delete_role(guild_id: String, role_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.roles.delete(guild_id, role_id)

func kick_member(guild_id: String, user_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.members.kick(guild_id, user_id)

func ban_member(guild_id: String, user_id: String, data: Dictionary = {}) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.bans.create(guild_id, user_id, data)

func unban_member(guild_id: String, user_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.bans.remove(guild_id, user_id)

func add_member_role(guild_id: String, user_id: String, role_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.members.add_role(guild_id, user_id, role_id)

func remove_member_role(guild_id: String, user_id: String, role_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.members.remove_role(guild_id, user_id, role_id)

func get_bans(guild_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.bans.list(guild_id)

func get_invites(guild_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.invites.list_space(guild_id)

func create_invite(guild_id: String, data: Dictionary = {}) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.invites.create_space(guild_id, data)

func delete_invite(code: String, guild_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.invites.delete(code)

func get_emojis(guild_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.emojis.list(guild_id)

func create_emoji(guild_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.emojis.create(guild_id, data)

func update_emoji(guild_id: String, emoji_id: String, data: Dictionary) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.emojis.update(guild_id, emoji_id, data)

func delete_emoji(guild_id: String, emoji_id: String) -> RestResult:
	var client := _client_for_guild(guild_id)
	if client == null:
		push_error("[Client] No connection for guild: ", guild_id)
		return null
	return await client.emojis.delete(guild_id, emoji_id)

func disconnect_server(guild_id: String) -> void:
	var idx: int = _guild_to_conn.get(guild_id, -1)
	if idx == -1:
		return
	var conn = _connections[idx]
	if conn != null and conn["client"] != null:
		conn["client"].queue_free()
	# Clean caches
	_guild_cache.erase(guild_id)
	_role_cache.erase(guild_id)
	_member_cache.erase(guild_id)
	var channels_to_remove: Array = []
	for ch_id in _channel_cache:
		if _channel_cache[ch_id].get("guild_id", "") == guild_id:
			channels_to_remove.append(ch_id)
	for ch_id in channels_to_remove:
		_channel_cache.erase(ch_id)
		_channel_to_guild.erase(ch_id)
		_message_cache.erase(ch_id)
	_guild_to_conn.erase(guild_id)
	_connections[idx] = null
	Config.remove_server(idx)
	# Re-index connections after removal
	_guild_to_conn.clear()
	for i in _connections.size():
		if _connections[i] != null:
			_guild_to_conn[_connections[i]["guild_id"]] = i
	if _all_failed() or _connections.is_empty():
		mode = Mode.CONNECTING
	AppState.guilds_updated.emit()

# --- Helpers ---

func _find_channel_for_message(message_id: String) -> String:
	for channel_id in _message_cache:
		for msg in _message_cache[channel_id]:
			if msg.get("id", "") == message_id:
				return channel_id
	return ""
