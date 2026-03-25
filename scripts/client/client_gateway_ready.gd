class_name ClientGatewayReady
extends RefCounted

## Populates Client caches from an enriched gateway READY payload.
## This avoids the 10+ sequential REST calls that _refetch_data() does.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func apply(
	data: Dictionary, conn: Dictionary, conn_index: int,
) -> void:
	var space_id: String = conn["space_id"]
	var cdn_url: String = conn.get("cdn_url", "")
	conn["_syncing"] = true

	# 1. Current user
	var user_data: Variant = data.get("user", null)
	if user_data is Dictionary and not user_data.is_empty():
		var user: AccordUser = AccordUser.from_dict(user_data)
		var user_dict: Dictionary = ClientModels.user_to_dict(
			user, ClientModels.UserStatus.ONLINE, cdn_url
		)
		_c._user_cache[user.id] = user_dict
		conn["user"] = user_dict
		conn["user_id"] = user.id
		if _c.current_user.is_empty():
			_c.current_user = user_dict

	# 2. All users (populate cache before members/voice need them)
	var users_arr: Array = data.get("users", [])
	for u in users_arr:
		if not u is Dictionary:
			continue
		var user: AccordUser = AccordUser.from_dict(u)
		if not _c._user_cache.has(user.id):
			_c._user_cache[user.id] = ClientModels.user_to_dict(
				user, ClientModels.UserStatus.OFFLINE, cdn_url
			)

	# 3. Spaces
	var spaces_arr: Array = data.get("spaces", [])
	for s in spaces_arr:
		if not s is Dictionary:
			continue
		var space: AccordSpace = AccordSpace.from_dict(s)
		var d: Dictionary = ClientModels.space_to_dict(space, cdn_url)
		d["folder"] = Config.get_space_folder(d["id"])
		_c._space_cache[d["id"]] = d
	AppState.spaces_updated.emit()

	# 4. Roles
	if not space_id.is_empty():
		var roles_arr: Array = data.get("roles", [])
		var roles: Array = []
		for r in roles_arr:
			if not r is Dictionary:
				continue
			var role: AccordRole = AccordRole.from_dict(r)
			roles.append(ClientModels.role_to_dict(role))
		_c._role_cache[space_id] = roles
		AppState.roles_updated.emit(space_id)

	# 5. Members
	if not space_id.is_empty():
		var members_arr: Array = data.get("members", [])
		var all_members: Array = []
		for m in members_arr:
			if not m is Dictionary:
				continue
			var member: AccordMember = AccordMember.from_dict(m)
			all_members.append(
				ClientModels.member_to_dict(
					member, _c._user_cache, cdn_url
				)
			)
		_c._member_cache[space_id] = all_members
		_c._rebuild_member_index(space_id)
		AppState.members_updated.emit(space_id)

	# 6. Channels
	if not space_id.is_empty():
		_apply_channels(data, space_id)

	# 7. Voice states
	_apply_voice_states(data)

	# 8. DM channels
	_apply_dm_channels(data, conn_index, cdn_url)

	# 9. Relationships
	_apply_relationships(data, conn, conn_index, cdn_url)

	# 10. Mutes
	var mutes_arr: Array = data.get("mutes", [])
	for entry in mutes_arr:
		var channel_id: String = str(
			entry.get("channel_id", "")
		) if entry is Dictionary else str(entry)
		if not channel_id.is_empty():
			_c._muted_channels[channel_id] = true
	AppState.channel_mutes_updated.emit()

	# 11. Unread
	_apply_unread(data)

	conn["_syncing"] = false
	if not space_id.is_empty():
		AppState.server_synced.emit(space_id)

func _apply_channels(data: Dictionary, space_id: String) -> void:
	# Clear old channels for this space
	var to_remove: Array = []
	for ch_id in _c._channel_cache:
		if _c._channel_cache[ch_id].get(
			"space_id", ""
		) == space_id:
			to_remove.append(ch_id)
	for ch_id in to_remove:
		_c._channel_cache.erase(ch_id)
		_c._channel_to_space.erase(ch_id)

	var channels_arr: Array = data.get("channels", [])
	for ch in channels_arr:
		if not ch is Dictionary:
			continue
		var channel: AccordChannel = AccordChannel.from_dict(ch)
		var d: Dictionary = ClientModels.channel_to_dict(channel)
		_c._channel_cache[d["id"]] = d
		_c._channel_to_space[d["id"]] = space_id
	AppState.channels_updated.emit(space_id)

func _apply_voice_states(data: Dictionary) -> void:
	var voice_arr: Array = data.get("voice_states", [])
	for vs_data in voice_arr:
		if not vs_data is Dictionary:
			continue
		var vs: AccordVoiceState = \
			AccordVoiceState.from_dict(vs_data)
		var ch_id: String = ""
		if vs.channel_id != null:
			ch_id = str(vs.channel_id)
		if ch_id.is_empty():
			continue
		if not _c._voice_state_cache.has(ch_id):
			_c._voice_state_cache[ch_id] = []
		_c._voice_state_cache[ch_id].append(
			ClientModels.voice_state_to_dict(vs, _c._user_cache)
		)
		if _c._channel_cache.has(ch_id):
			_c._channel_cache[ch_id]["voice_users"] = \
				_c._voice_state_cache[ch_id].size()
	for ch_id in _c._voice_state_cache:
		AppState.voice_state_updated.emit(ch_id)

func _apply_dm_channels(
	data: Dictionary, conn_index: int, cdn_url: String,
) -> void:
	var dm_arr: Array = data.get("dm_channels", [])
	if dm_arr.is_empty():
		return
	# Snapshot old state
	var old_unread: Dictionary = {}
	for dm_id in _c._dm_channel_cache:
		if _c._dm_channel_cache[dm_id].get("unread", false):
			old_unread[dm_id] = true
	var old_previews: Dictionary = {}
	for dm_id in _c._dm_channel_cache:
		var preview: String = _c._dm_channel_cache[dm_id] \
			.get("last_message", "")
		if not preview.is_empty():
			old_previews[dm_id] = preview
	_c._dm_channel_cache.clear()
	_c._dm_to_conn.clear()

	for ch in dm_arr:
		if not ch is Dictionary:
			continue
		var channel: AccordChannel = AccordChannel.from_dict(ch)
		# Cache recipient users
		if channel.recipients is Array:
			for recipient in channel.recipients:
				if not _c._user_cache.has(recipient.id):
					_c._user_cache[recipient.id] = \
						ClientModels.user_to_dict(
							recipient,
							ClientModels.UserStatus.OFFLINE,
							cdn_url
						)
		var d: Dictionary = ClientModels.dm_channel_to_dict(
			channel, _c._user_cache
		)
		_c._dm_channel_cache[d["id"]] = d
		_c._dm_to_conn[d["id"]] = conn_index

	# Restore old state
	for dm_id in old_unread:
		if _c._dm_channel_cache.has(dm_id):
			_c._dm_channel_cache[dm_id]["unread"] = true
	for dm_id in old_previews:
		if _c._dm_channel_cache.has(dm_id):
			var cur: String = _c._dm_channel_cache[dm_id] \
				.get("last_message", "")
			if cur.is_empty():
				_c._dm_channel_cache[dm_id]["last_message"] = \
					old_previews[dm_id]
	AppState.dm_channels_updated.emit()

func _apply_relationships(
	data: Dictionary, conn: Dictionary,
	conn_index: int, cdn_url: String,
) -> void:
	var rels_arr: Array = data.get("relationships", [])
	if rels_arr.is_empty():
		return
	var cfg: Dictionary = conn.get("config", {})
	var srv_url: String = cfg.get("base_url", "")
	var sp_name: String = cfg.get("space_name", "")
	for r in rels_arr:
		if not r is Dictionary:
			continue
		var rel: AccordRelationship = \
			AccordRelationship.from_dict(r)
		var d: Dictionary = ClientModels.relationship_to_dict(
			rel, cdn_url, srv_url, sp_name
		)
		var key: String = str(conn_index) + ":" \
			+ d["user"].get("id", "")
		_c._relationship_cache[key] = d
	AppState.relationships_updated.emit()

func _apply_unread(data: Dictionary) -> void:
	var unread_arr: Array = data.get("unread", [])
	for entry in unread_arr:
		if not entry is Dictionary:
			continue
		var channel_id: String = str(
			entry.get("channel_id", "")
		)
		var mention_count: int = int(
			entry.get("mention_count", 0)
		)
		if channel_id.is_empty():
			continue
		_c._unread_channels[channel_id] = true
		if mention_count > 0:
			_c._channel_mention_counts[channel_id] = mention_count
		if _c._channel_cache.has(channel_id):
			_c._channel_cache[channel_id]["unread"] = true
		elif _c._dm_channel_cache.has(channel_id):
			_c._dm_channel_cache[channel_id]["unread"] = true
	# Recompute space-level unread
	var affected_spaces: Dictionary = {}
	for channel_id in _c._unread_channels:
		var gid: String = _c._channel_to_space.get(
			channel_id, ""
		)
		if not gid.is_empty():
			affected_spaces[gid] = true
	for sid in affected_spaces:
		_c.unread.update_space_unread(sid)
		AppState.channels_updated.emit(sid)
	AppState.dm_channels_updated.emit()
	AppState.spaces_updated.emit()
