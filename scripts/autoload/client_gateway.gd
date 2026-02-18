class_name ClientGateway
extends RefCounted

## Handles gateway events for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and fetch methods.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func on_gateway_ready(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	print("[Client] Gateway ready for: ", conn["config"]["base_url"])
	if not conn["guild_id"].is_empty():
		_c.fetch_channels(conn["guild_id"])
		_c.fetch_members(conn["guild_id"])
		_c.fetch_roles(conn["guild_id"])
	_c.fetch_dm_channels()

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

	var msg_dict := ClientModels.message_to_dict(message, _c._user_cache)
	if not _c._message_cache.has(message.channel_id):
		_c._message_cache[message.channel_id] = []
	_c._message_cache[message.channel_id].append(msg_dict)

	while _c._message_cache[message.channel_id].size() > Client.MESSAGE_CAP:
		_c._message_cache[message.channel_id].pop_front()

	AppState.messages_updated.emit(message.channel_id)

func on_message_update(message: AccordMessage, _conn_index: int) -> void:
	if not _c._message_cache.has(message.channel_id):
		return
	var msgs: Array = _c._message_cache[message.channel_id]
	for i in msgs.size():
		if msgs[i].get("id", "") == message.id:
			msgs[i] = ClientModels.message_to_dict(message, _c._user_cache)
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
			break
	AppState.messages_updated.emit(channel_id)

func on_typing_start(data: Dictionary) -> void:
	var user_id: String = data.get("user_id", "")
	var channel_id: String = data.get("channel_id", "")
	if user_id == _c.current_user.get("id", ""):
		return
	var user_dict: Dictionary = _c.get_user_by_id(user_id)
	var username: String = user_dict.get("display_name", "Someone")
	AppState.typing_started.emit(channel_id, username)

func on_presence_update(presence: AccordPresence, conn_index: int) -> void:
	if _c._user_cache.has(presence.user_id):
		_c._user_cache[presence.user_id]["status"] = ClientModels._status_string_to_enum(presence.status)
		AppState.user_updated.emit(presence.user_id)
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		var guild_id: String = _c._connections[conn_index]["guild_id"]
		if _c._member_cache.has(guild_id):
			for member_dict in _c._member_cache[guild_id]:
				if member_dict.get("id", "") == presence.user_id:
					member_dict["status"] = ClientModels._status_string_to_enum(presence.status)
					break
			AppState.members_updated.emit(guild_id)

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
		var members: Array = _c._member_cache[guild_id]
		for i in members.size():
			if members[i].get("id", "") == user_id:
				members.remove_at(i)
				break
		AppState.members_updated.emit(guild_id)

func on_member_update(member: AccordMember, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	if _c._member_cache.has(guild_id):
		var member_dict := ClientModels.member_to_dict(member, _c._user_cache)
		var members: Array = _c._member_cache[guild_id]
		var found := false
		for i in members.size():
			if members[i].get("id", "") == member.user_id:
				members[i] = member_dict
				found = true
				break
		if not found:
			members.append(member_dict)
		AppState.members_updated.emit(guild_id)

func on_space_create(space: AccordSpace, conn_index: int) -> void:
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		var conn: Dictionary = _c._connections[conn_index]
		if space.id == conn["guild_id"]:
			_c._guild_cache[space.id] = ClientModels.space_to_guild_dict(space)
			AppState.guilds_updated.emit()

func on_space_update(space: AccordSpace) -> void:
	if _c._guild_cache.has(space.id):
		_c._guild_cache[space.id] = ClientModels.space_to_guild_dict(space)
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
		_c._dm_channel_cache[channel.id] = ClientModels.dm_channel_to_dict(channel, _c._user_cache)
		AppState.dm_channels_updated.emit()
	else:
		_c._channel_cache[channel.id] = ClientModels.channel_to_dict(channel)
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

func on_ban_create(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.bans_updated.emit(guild_id)

func on_ban_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.bans_updated.emit(guild_id)

func on_invite_create(_invite: AccordInvite, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.invites_updated.emit(guild_id)

func on_invite_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.invites_updated.emit(guild_id)

func on_emoji_update(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.emojis_updated.emit(guild_id)
