class_name ClientGateway
extends RefCounted

## Handles gateway events for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and fetch methods.

var _c: Node # Client autoload
var _typing_timers: Dictionary = {} # channel_id -> Timer node
var _reactions: ClientGatewayReactions
var _events: ClientGatewayEvents

func _init(client_node: Node) -> void:
	_c = client_node
	_reactions = ClientGatewayReactions.new(client_node)
	_events = ClientGatewayEvents.new(client_node)

func connect_signals(
	client: AccordClient, idx: int
) -> void:
	client.ready_received.connect(
		on_gateway_ready.bind(idx))
	client.message_create.connect(
		on_message_create.bind(idx))
	client.message_update.connect(
		on_message_update.bind(idx))
	client.message_delete.connect(on_message_delete)
	client.message_delete_bulk.connect(
		on_message_delete_bulk)
	client.typing_start.connect(on_typing_start)
	client.presence_update.connect(
		on_presence_update.bind(idx))
	client.member_join.connect(
		on_member_join.bind(idx))
	client.member_leave.connect(
		on_member_leave.bind(idx))
	client.member_update.connect(
		on_member_update.bind(idx))
	client.member_chunk.connect(
		on_member_chunk.bind(idx))
	client.user_update.connect(
		on_user_update.bind(idx))
	client.space_create.connect(
		on_space_create.bind(idx))
	client.space_update.connect(on_space_update)
	client.space_delete.connect(on_space_delete)
	client.channel_create.connect(
		on_channel_create.bind(idx))
	client.channel_update.connect(
		on_channel_update.bind(idx))
	client.channel_delete.connect(on_channel_delete)
	client.channel_pins_update.connect(
		on_channel_pins_update)
	client.role_create.connect(
		on_role_create.bind(idx))
	client.role_update.connect(
		on_role_update.bind(idx))
	client.role_delete.connect(
		on_role_delete.bind(idx))
	client.ban_create.connect(_events.on_ban_create.bind(idx))
	client.ban_delete.connect(_events.on_ban_delete.bind(idx))
	client.invite_create.connect(
		_events.on_invite_create.bind(idx))
	client.invite_delete.connect(
		_events.on_invite_delete.bind(idx))
	client.emoji_create.connect(
		_events.on_emoji_create.bind(idx))
	client.emoji_update.connect(
		_events.on_emoji_update.bind(idx))
	client.emoji_delete.connect(
		_events.on_emoji_delete.bind(idx))
	client.interaction_create.connect(
		_events.on_interaction_create.bind(idx))
	client.soundboard_create.connect(
		_events.on_soundboard_create.bind(idx))
	client.soundboard_update.connect(
		_events.on_soundboard_update.bind(idx))
	client.soundboard_delete.connect(
		_events.on_soundboard_delete.bind(idx))
	client.soundboard_play.connect(
		_events.on_soundboard_play.bind(idx))
	client.reaction_add.connect(_reactions.on_reaction_add)
	client.reaction_remove.connect(_reactions.on_reaction_remove)
	client.reaction_clear.connect(_reactions.on_reaction_clear)
	client.reaction_clear_emoji.connect(
		_reactions.on_reaction_clear_emoji)
	client.voice_state_update.connect(
		_events.on_voice_state_update.bind(idx))
	client.voice_server_update.connect(
		_events.on_voice_server_update.bind(idx))
	client.voice_signal.connect(
		_events.on_voice_signal.bind(idx))
	client.disconnected.connect(
		on_gateway_disconnected.bind(idx))
	client.reconnecting.connect(
		on_gateway_reconnecting.bind(idx))
	client.resumed.connect(
		on_gateway_reconnected.bind(idx))

func on_gateway_ready(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	print("[Client] Gateway ready for: ", conn["config"]["base_url"])
	_c._auto_reconnect_attempted.erase(conn_index)
	# Emit reconnected if this was a reconnect after disconnect
	var was_down: bool = conn.get("_was_disconnected", false) \
		or conn["status"] != "connected"
	conn["_was_disconnected"] = false
	conn["status"] = "connected"
	if was_down and not conn["guild_id"].is_empty():
		AppState.server_reconnected.emit(conn["guild_id"])
	if not conn["guild_id"].is_empty():
		_c.fetch.fetch_channels(conn["guild_id"])
		_c.fetch.fetch_members(conn["guild_id"])
		_c.fetch.fetch_roles(conn["guild_id"])
	_c.fetch.fetch_dm_channels()

func on_gateway_disconnected(code: int, reason: String, conn_index: int) -> void:
	if _c.is_shutting_down:
		return
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	var guild_id: String = conn["guild_id"]
	var fatal_codes := [4003, 4004, 4012, 4013, 4014]
	if code in fatal_codes:
		# Escalate to full reconnect (with re-auth) instead of
		# giving up immediately. _handle_gateway_reconnect_failed
		# will go to "error" if it has already been tried once.
		conn["_was_disconnected"] = true
		AppState.server_disconnected.emit(guild_id, code, reason)
		_c.call_deferred(
			"_handle_gateway_reconnect_failed", conn_index
		)
	else:
		conn["status"] = "disconnected"
		conn["_was_disconnected"] = true
		AppState.server_disconnected.emit(guild_id, code, reason)

func on_gateway_reconnecting(attempt: int, max_attempts: int, conn_index: int) -> void:
	if _c.is_shutting_down:
		return
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	conn["status"] = "reconnecting"
	AppState.server_reconnecting.emit(conn["guild_id"], attempt, max_attempts)
	if attempt >= max_attempts:
		# Escalate to full reconnect with re-auth instead of
		# giving up. The old client will be destroyed by
		# reconnect_server(), stopping any pending gateway work.
		conn["_was_disconnected"] = true
		_c.call_deferred(
			"_handle_gateway_reconnect_failed", conn_index
		)

func on_gateway_reconnected(conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	conn["status"] = "connected"
	conn["_was_disconnected"] = false
	_c._auto_reconnect_attempted.erase(conn_index)
	AppState.server_reconnected.emit(conn["guild_id"])

func on_message_create(message: AccordMessage, conn_index: int) -> void:
	var cdn_url := ""
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		cdn_url = _c._connections[conn_index]["cdn_url"]

	if not _c._user_cache.has(message.author_id):
		var client: AccordClient = _c._client_for_channel(message.channel_id)
		if client == null and conn_index < _c._connections.size() and _c._connections[conn_index] != null:
			client = _c._connections[conn_index]["client"]
		if client != null:
			var user_result: RestResult = await client.users.fetch(message.author_id)
			if user_result.ok:
				_c._user_cache[message.author_id] = ClientModels.user_to_dict(
					user_result.data,
					ClientModels.UserStatus.OFFLINE,
					cdn_url
				)

	var msg_dict := ClientModels.message_to_dict(message, _c._user_cache, cdn_url)
	# Skip if already in cache (e.g. from a parallel gateway connection)
	if _c._message_id_index.has(message.id):
		return
	if not _c._message_cache.has(message.channel_id):
		_c._message_cache[message.channel_id] = []
	_c._message_cache[message.channel_id].append(msg_dict)
	_c._message_id_index[message.id] = message.channel_id

	while _c._message_cache[message.channel_id].size() > Client.MESSAGE_CAP:
		var evicted: Dictionary = _c._message_cache[message.channel_id].pop_front()
		_c._message_id_index.erase(evicted.get("id", ""))

	# Track unread + mentions for channels not currently viewed
	var my_id: String = _c.current_user.get("id", "")
	if message.channel_id != AppState.current_channel_id and message.author_id != my_id:
		# DND suppresses all notification indicators
		var user_status: int = _c.current_user.get("status", 0)
		if user_status == ClientModels.UserStatus.DND:
			pass # Skip all notification tracking in DND mode
		else:
			# Check server mute
			var guild_id: String = _c._channel_to_guild.get(message.channel_id, "")
			if Config.is_server_muted(guild_id):
				pass # Server is muted — skip unread tracking
			else:
				# Determine if this is a mention
				var is_mention: bool = my_id in message.mentions
				if message.mention_everyone and not Config.get_suppress_everyone():
					is_mention = true
				if not is_mention:
					is_mention = _has_role_mention(message.mention_roles, guild_id)

				# Enforce default_notifications setting
				var guild: Dictionary = _c._guild_cache.get(guild_id, {})
				var notif_level: String = guild.get("default_notifications", "all")
				if notif_level == "mentions" and not is_mention:
					pass # Not a mention in mentions-only mode — skip
				else:
					_c.mark_channel_unread(message.channel_id, is_mention)

	# Play notification sound (guard for headless mode)
	if SoundManager != null:
		SoundManager.play_for_message(
			message.channel_id, message.author_id,
			message.mentions, message.mention_everyone
		)

	# Update DM channel last_message preview
	if _c._dm_channel_cache.has(message.channel_id):
		var preview: String = message.content
		if preview.length() > 80:
			preview = preview.substr(0, 80) + "..."
		_c._dm_channel_cache[message.channel_id]["last_message"] = preview
		AppState.dm_channels_updated.emit()

	AppState.messages_updated.emit(message.channel_id)

func on_message_update(message: AccordMessage, conn_index: int) -> void:
	if not _c._message_cache.has(message.channel_id):
		return
	var cdn_url := ""
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		cdn_url = _c._connections[conn_index]["cdn_url"]
	var msgs: Array = _c._message_cache[message.channel_id]
	for i in msgs.size():
		if msgs[i].get("id", "") == message.id:
			msgs[i] = ClientModels.message_to_dict(message, _c._user_cache, cdn_url)
			break
	AppState.messages_updated.emit(message.channel_id)

func on_message_delete(data: Dictionary) -> void:
	var msg_id: String = data.get("id", "")
	var channel_id: String = data.get("channel_id", "")
	if channel_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var msgs: Array = _c._message_cache[channel_id]
	for i in msgs.size():
		if msgs[i].get("id", "") == msg_id:
			msgs.remove_at(i)
			_c._message_id_index.erase(msg_id)
			break
	AppState.messages_updated.emit(channel_id)

func on_message_delete_bulk(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	var ids: Array = data.get("ids", [])
	if channel_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var msgs: Array = _c._message_cache[channel_id]
	var id_set: Dictionary = {}
	for mid in ids:
		id_set[str(mid)] = true
	var i := msgs.size() - 1
	while i >= 0:
		var mid: String = msgs[i].get("id", "")
		if id_set.has(mid):
			msgs.remove_at(i)
			_c._message_id_index.erase(mid)
		i -= 1
	AppState.messages_updated.emit(channel_id)

func on_typing_start(data: Dictionary) -> void:
	var user_id: String = data.get("user_id", "")
	var channel_id: String = data.get("channel_id", "")
	if user_id == _c.current_user.get("id", ""):
		return
	var user_dict: Dictionary = _c.get_user_by_id(user_id)
	var username: String = user_dict.get("display_name", "Someone")
	AppState.typing_started.emit(channel_id, username)
	# Reset/create timeout to emit typing_stopped
	if _typing_timers.has(channel_id) and is_instance_valid(_typing_timers[channel_id]):
		_typing_timers[channel_id].queue_free()
	var timer := Timer.new()
	timer.wait_time = 10.0
	timer.one_shot = true
	timer.timeout.connect(func():
		AppState.typing_stopped.emit(channel_id)
		_typing_timers.erase(channel_id)
		timer.queue_free()
	)
	_c.add_child(timer)
	timer.start()
	_typing_timers[channel_id] = timer

func on_presence_update(presence: AccordPresence, conn_index: int) -> void:
	if _c._user_cache.has(presence.user_id):
		_c._user_cache[presence.user_id]["status"] = ClientModels._status_string_to_enum(presence.status)
		# Store per-device status and activities
		_c._user_cache[presence.user_id]["client_status"] = presence.client_status
		var act_arr: Array = []
		for a in presence.activities:
			if a is AccordActivity:
				act_arr.append(a.to_dict())
		_c._user_cache[presence.user_id]["activities"] = act_arr
		AppState.user_updated.emit(presence.user_id)
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		var guild_id: String = _c._connections[conn_index]["guild_id"]
		var idx: int = _c._member_index_for(guild_id, presence.user_id)
		if idx != -1:
			var new_status: int = ClientModels._status_string_to_enum(presence.status)
			var old_status: int = _c._member_cache[guild_id][idx].get("status", -1)
			_c._member_cache[guild_id][idx]["status"] = new_status
			if old_status != new_status:
				AppState.member_status_changed.emit(
					guild_id, presence.user_id, new_status
				)
			AppState.members_updated.emit(guild_id)

func on_user_update(user: AccordUser, conn_index: int) -> void:
	var cdn_url := ""
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		cdn_url = _c._connections[conn_index]["cdn_url"]
	var existing: Dictionary = _c._user_cache.get(user.id, {})
	var status: int = existing.get("status", ClientModels.UserStatus.OFFLINE)
	_c._user_cache[user.id] = ClientModels.user_to_dict(user, status, cdn_url)
	if _c.current_user.get("id", "") == user.id:
		_c.current_user = _c._user_cache[user.id]
	AppState.user_updated.emit(user.id)

func on_member_chunk(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var cdn_url: String = _c._connections[conn_index]["cdn_url"]
	var members_data: Array = data.get("members", [])
	if not _c._member_cache.has(guild_id):
		_c._member_cache[guild_id] = []
	var existing: Array = _c._member_cache[guild_id]
	var existing_ids: Dictionary = {}
	for i in existing.size():
		existing_ids[existing[i].get("id", "")] = i
	for raw in members_data:
		if raw is Dictionary:
			var raw_user = raw.get("user", null)
			if raw_user is Dictionary:
				var uid: String = str(raw_user.get("id", ""))
				if not uid.is_empty() and not _c._user_cache.has(uid):
					var parsed_user: AccordUser = AccordUser.from_dict(raw_user)
					_c._user_cache[uid] = ClientModels.user_to_dict(
						parsed_user, ClientModels.UserStatus.OFFLINE, cdn_url
					)
		var member: AccordMember = AccordMember.from_dict(raw)
		var member_dict := ClientModels.member_to_dict(member, _c._user_cache)
		if existing_ids.has(member.user_id):
			existing[existing_ids[member.user_id]] = member_dict
		else:
			existing.append(member_dict)
			existing_ids[member.user_id] = existing.size() - 1
	_c._member_id_index[guild_id] = existing_ids
	AppState.members_updated.emit(guild_id)

func on_channel_pins_update(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	if not channel_id.is_empty():
		AppState.messages_updated.emit(channel_id)

func on_interaction_create(_interaction: AccordInteraction, _conn_index: int) -> void:
	pass # No interaction UI; wired to prevent silent drop

func on_member_join(member: AccordMember, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	var guild_id: String = conn["guild_id"]
	var cdn_url: String = conn["cdn_url"]
	if not _c._user_cache.has(member.user_id):
		var client: AccordClient = conn["client"]
		if client != null:
			var user_result: RestResult = await client.users.fetch(member.user_id)
			if user_result.ok:
				_c._user_cache[member.user_id] = ClientModels.user_to_dict(
					user_result.data,
					ClientModels.UserStatus.OFFLINE,
					cdn_url
				)
	var member_dict := ClientModels.member_to_dict(member, _c._user_cache)
	if not _c._member_cache.has(guild_id):
		_c._member_cache[guild_id] = []
	_c._member_cache[guild_id].append(member_dict)
	if not _c._member_id_index.has(guild_id):
		_c._member_id_index[guild_id] = {}
	_c._member_id_index[guild_id][member.user_id] = _c._member_cache[guild_id].size() - 1
	AppState.member_joined.emit(guild_id, member_dict)
	AppState.members_updated.emit(guild_id)

func on_member_leave(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var user_id: String = data.get("user_id", "")
	if user_id.is_empty():
		var user_data = data.get("user", null)
		if user_data is Dictionary:
			user_id = str(user_data.get("id", ""))
	if _c._member_cache.has(guild_id):
		var idx: int = _c._member_index_for(guild_id, user_id)
		if idx != -1:
			_c._member_cache[guild_id].remove_at(idx)
			_c._rebuild_member_index(guild_id)
			AppState.member_left.emit(guild_id, user_id)
			AppState.members_updated.emit(guild_id)

func on_member_update(member: AccordMember, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	if _c._member_cache.has(guild_id):
		var member_dict := ClientModels.member_to_dict(member, _c._user_cache)
		var idx: int = _c._member_index_for(guild_id, member.user_id)
		if idx != -1:
			_c._member_cache[guild_id][idx] = member_dict
		else:
			_c._member_cache[guild_id].append(member_dict)
			if not _c._member_id_index.has(guild_id):
				_c._member_id_index[guild_id] = {}
			_c._member_id_index[guild_id][member.user_id] = _c._member_cache[guild_id].size() - 1
		AppState.members_updated.emit(guild_id)

func on_space_create(space: AccordSpace, conn_index: int) -> void:
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		var conn: Dictionary = _c._connections[conn_index]
		if space.id == conn["guild_id"]:
			var cdn_url: String = conn.get("cdn_url", "")
			var new_guild: Dictionary = ClientModels.space_to_guild_dict(space, cdn_url)
			new_guild["folder"] = Config.get_guild_folder(space.id)
			_c._guild_cache[space.id] = new_guild
			AppState.guilds_updated.emit()

func on_space_update(space: AccordSpace) -> void:
	if _c._guild_cache.has(space.id):
		var old_guild: Dictionary = _c._guild_cache[space.id]
		var cdn_url: String = _c._cdn_for_guild(space.id)
		var new_guild: Dictionary = ClientModels.space_to_guild_dict(space, cdn_url)
		new_guild["unread"] = old_guild.get("unread", false)
		new_guild["mentions"] = old_guild.get("mentions", 0)
		new_guild["folder"] = old_guild.get("folder", "")
		_c._guild_cache[space.id] = new_guild
		AppState.guilds_updated.emit()

func on_space_delete(data: Dictionary) -> void:
	var space_id: String = data.get("id", "")
	_c._guild_cache.erase(space_id)
	_c._guild_to_conn.erase(space_id)
	AppState.guilds_updated.emit()

func on_channel_create(channel: AccordChannel, conn_index: int) -> void:
	if channel.type == "dm" or channel.type == "group_dm":
		var cdn_url := ""
		if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
			cdn_url = _c._connections[conn_index]["cdn_url"]
		if channel.recipients != null and channel.recipients is Array:
			for recipient in channel.recipients:
				if not _c._user_cache.has(recipient.id):
					_c._user_cache[recipient.id] = ClientModels.user_to_dict(
						recipient,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
		_c._dm_channel_cache[channel.id] = ClientModels.dm_channel_to_dict(channel, _c._user_cache)
		AppState.dm_channels_updated.emit()
	else:
		_c._channel_cache[channel.id] = ClientModels.channel_to_dict(channel)
		var guild_id: String = str(channel.space_id) if channel.space_id != null else ""
		_c._channel_to_guild[channel.id] = guild_id
		AppState.channels_updated.emit(guild_id)

func on_channel_update(channel: AccordChannel, conn_index: int) -> void:
	if channel.type == "dm" or channel.type == "group_dm":
		var cdn_url := ""
		if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
			cdn_url = _c._connections[conn_index]["cdn_url"]
		if channel.recipients != null and channel.recipients is Array:
			for recipient in channel.recipients:
				if not _c._user_cache.has(recipient.id):
					_c._user_cache[recipient.id] = ClientModels.user_to_dict(
						recipient,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
		var old_dm: Dictionary = _c._dm_channel_cache.get(channel.id, {})
		var new_dm: Dictionary = ClientModels.dm_channel_to_dict(channel, _c._user_cache)
		new_dm["unread"] = old_dm.get("unread", false)
		_c._dm_channel_cache[channel.id] = new_dm
		AppState.dm_channels_updated.emit()
	else:
		var old_ch: Dictionary = _c._channel_cache.get(channel.id, {})
		var new_ch: Dictionary = ClientModels.channel_to_dict(channel)
		new_ch["unread"] = old_ch.get("unread", false)
		new_ch["voice_users"] = old_ch.get("voice_users", 0)
		_c._channel_cache[channel.id] = new_ch
		var guild_id: String = str(channel.space_id) if channel.space_id != null else ""
		_c._channel_to_guild[channel.id] = guild_id
		AppState.channels_updated.emit(guild_id)

func on_channel_delete(channel: AccordChannel) -> void:
	if channel.type == "dm" or channel.type == "group_dm":
		_c._dm_channel_cache.erase(channel.id)
		AppState.dm_channels_updated.emit()
	else:
		_c._channel_cache.erase(channel.id)
		_c._channel_to_guild.erase(channel.id)
		var guild_id: String = str(channel.space_id) if channel.space_id != null else ""
		AppState.channels_updated.emit(guild_id)

func on_role_create(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var role := AccordRole.from_dict(data.get("role", data))
	var role_dict := ClientModels.role_to_dict(role)
	if not _c._role_cache.has(guild_id):
		_c._role_cache[guild_id] = []
	_c._role_cache[guild_id].append(role_dict)
	AppState.roles_updated.emit(guild_id)

func on_role_update(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var role := AccordRole.from_dict(data.get("role", data))
	var role_dict := ClientModels.role_to_dict(role)
	if _c._role_cache.has(guild_id):
		var roles: Array = _c._role_cache[guild_id]
		for i in roles.size():
			if roles[i].get("id", "") == role_dict["id"]:
				roles[i] = role_dict
				break
	AppState.roles_updated.emit(guild_id)

func on_role_delete(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var role_id: String = str(data.get("role_id", data.get("id", "")))
	if _c._role_cache.has(guild_id):
		var roles: Array = _c._role_cache[guild_id]
		for i in roles.size():
			if roles[i].get("id", "") == role_id:
				roles.remove_at(i)
				break
	AppState.roles_updated.emit(guild_id)

func _has_role_mention(mention_roles: Array, guild_id: String) -> bool:
	if mention_roles.is_empty() or guild_id.is_empty():
		return false
	var my_id: String = _c.current_user.get("id", "")
	var idx: int = _c._member_index_for(guild_id, my_id)
	if idx == -1:
		return false
	var my_roles: Array = _c._member_cache.get(guild_id, [])[idx].get("roles", [])
	for role_id in mention_roles:
		if role_id in my_roles:
			return true
	return false
