class_name ClientFetch
extends RefCounted

## Handles data fetching for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and emit AppState signals.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func fetch_guilds() -> void:
	for conn in _c._connections:
		if conn == null \
				or conn["status"] != "connected" \
				or conn["client"] == null:
			continue
		var client: AccordClient = conn["client"]
		var cdn_url: String = conn.get("cdn_url", "")
		var result: RestResult = await client.users.list_spaces()
		if result.ok:
			for space in result.data:
				var s: AccordSpace = space
				if s.id == conn["guild_id"]:
					var d := ClientModels.space_to_guild_dict(
						s, cdn_url
					)
					_c._guild_cache[d["id"]] = d
	AppState.guilds_updated.emit()

func fetch_channels(guild_id: String) -> void:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		return
	var result: RestResult = await client.spaces.list_channels(
		guild_id
	)
	if result.ok:
		var to_remove: Array = []
		for ch_id in _c._channel_cache:
			if _c._channel_cache[ch_id].get("guild_id", "") == guild_id:
				to_remove.append(ch_id)
		for ch_id in to_remove:
			_c._channel_cache.erase(ch_id)
			_c._channel_to_guild.erase(ch_id)
		for channel in result.data:
			var d := ClientModels.channel_to_dict(channel)
			_c._channel_cache[d["id"]] = d
			_c._channel_to_guild[d["id"]] = guild_id
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
	# Snapshot unread state before clearing
	var old_unread: Dictionary = {}
	for dm_id in _c._dm_channel_cache:
		if _c._dm_channel_cache[dm_id].get("unread", false):
			old_unread[dm_id] = true
	# Snapshot old last_message previews
	var old_previews: Dictionary = {}
	for dm_id in _c._dm_channel_cache:
		var preview: String = _c._dm_channel_cache[dm_id] \
			.get("last_message", "")
		if not preview.is_empty():
			old_previews[dm_id] = preview

	_c._dm_channel_cache.clear()
	_c._dm_to_conn.clear()

	# Iterate all connected servers for DM channels
	for conn_idx in _c._connections.size():
		var conn = _c._connections[conn_idx]
		if conn == null \
				or conn["status"] != "connected" \
				or conn["client"] == null:
			continue
		var client: AccordClient = conn["client"]
		var cdn_url: String = conn.get("cdn_url", "")
		var result: RestResult = \
			await client.users.list_channels()
		if result.ok:
			for channel in result.data:
				if _c._dm_channel_cache.has(channel.id):
					continue  # Already fetched from another conn
				if channel.recipients != null \
						and channel.recipients is Array:
					for recipient in channel.recipients:
						if not _c._user_cache.has(recipient.id):
							_c._user_cache[recipient.id] = \
								ClientModels.user_to_dict(
									recipient,
									ClientModels.UserStatus.OFFLINE,
									cdn_url
								)
				var d := ClientModels.dm_channel_to_dict(
					channel, _c._user_cache
				)
				_c._dm_channel_cache[d["id"]] = d
				_c._dm_to_conn[d["id"]] = conn_idx
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

	# Restore unread state
	for dm_id in old_unread:
		if _c._dm_channel_cache.has(dm_id):
			_c._dm_channel_cache[dm_id]["unread"] = true
	# Restore old last_message previews
	for dm_id in old_previews:
		if _c._dm_channel_cache.has(dm_id):
			var cur: String = _c._dm_channel_cache[dm_id] \
				.get("last_message", "")
			if cur.is_empty():
				_c._dm_channel_cache[dm_id]["last_message"] = \
					old_previews[dm_id]

	AppState.dm_channels_updated.emit()

	# Asynchronously fetch last message previews
	_fetch_dm_previews()

func _fetch_unknown_authors(
	messages: Array, client: AccordClient, cdn_url: String,
) -> void:
	var seen: Dictionary = {}
	for msg in messages:
		var accord_msg: AccordMessage = msg
		var uid: String = accord_msg.author_id
		if _c._user_cache.has(uid) or seen.has(uid):
			continue
		seen[uid] = true
		var user_result: RestResult = \
			await client.users.fetch(uid)
		if user_result.ok:
			_c._user_cache[uid] = ClientModels.user_to_dict(
				user_result.data,
				ClientModels.UserStatus.OFFLINE,
				cdn_url
			)

func fetch_messages(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		AppState.message_fetch_failed.emit(
			channel_id, "No connection found"
		)
		return
	var cdn_url: String = _c._cdn_for_channel(channel_id)
	var cap: int = _c.MESSAGE_CAP
	var result: RestResult = await client.messages.list(
		channel_id, {"limit": cap}
	)
	if result.ok:
		# Fetch all unknown authors in parallel
		await _fetch_unknown_authors(
			result.data, client, cdn_url
		)
		var msgs: Array = []
		for msg in result.data:
			var accord_msg: AccordMessage = msg
			msgs.append(
				ClientModels.message_to_dict(
					accord_msg, _c._user_cache, cdn_url
				)
			)
		# Clear old index entries for this channel
		if _c._message_cache.has(channel_id):
			for old_msg in _c._message_cache[channel_id]:
				_c._message_id_index.erase(old_msg.get("id", ""))
		_c._message_cache[channel_id] = msgs
		# Build index for new messages
		for msg in msgs:
			_c._message_id_index[msg.get("id", "")] = channel_id
		# Trim user cache periodically
		_c.trim_user_cache()
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
		AppState.message_fetch_failed.emit(
			channel_id, err_msg
		)

func fetch_older_messages(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		return
	var existing: Array = _c._message_cache.get(
		channel_id, []
	)
	if existing.is_empty():
		return
	var oldest_id: String = existing[0].get("id", "")
	if oldest_id.is_empty():
		return
	var cdn_url: String = _c._cdn_for_channel(channel_id)
	var cap: int = _c.MESSAGE_CAP
	var result: RestResult = await client.messages.list(
		channel_id,
		{"before": oldest_id, "limit": cap},
	)
	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch older messages: ",
			err_msg
		)
		return
	# Fetch all unknown authors in parallel
	await _fetch_unknown_authors(
		result.data, client, cdn_url
	)
	var older_msgs: Array = []
	for msg in result.data:
		var accord_msg: AccordMessage = msg
		older_msgs.append(
			ClientModels.message_to_dict(
				accord_msg, _c._user_cache, cdn_url
			)
		)
	if older_msgs.is_empty():
		AppState.messages_updated.emit(channel_id)
		return
	# Prepend older messages to existing cache
	var combined: Array = older_msgs + existing
	# Cap total cached messages per channel
	while combined.size() > _c.MAX_CHANNEL_MESSAGES:
		var evicted: Dictionary = combined.pop_back()
		_c._message_id_index.erase(evicted.get("id", ""))
	_c._message_cache[channel_id] = combined
	# Update index for new messages
	for msg in older_msgs:
		_c._message_id_index[msg.get("id", "")] = channel_id
	AppState.messages_updated.emit(channel_id)

func fetch_thread_messages(channel_id: String, parent_message_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		return
	var cdn_url: String = _c._cdn_for_channel(channel_id)
	var result: RestResult = await client.messages.list_thread(
		channel_id, parent_message_id
	)
	if result.ok:
		await _fetch_unknown_authors(
			result.data, client, cdn_url
		)
		var msgs: Array = []
		for msg in result.data:
			var accord_msg: AccordMessage = msg
			msgs.append(
				ClientModels.message_to_dict(
					accord_msg, _c._user_cache, cdn_url
				)
			)
		_c._thread_message_cache[parent_message_id] = msgs
		AppState.thread_messages_updated.emit(
			parent_message_id
		)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch thread messages: ",
			err_msg
		)

func fetch_active_threads(channel_id: String) -> Array:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		return []
	var cdn_url: String = _c._cdn_for_channel(channel_id)
	var result: RestResult = await client.messages.list_active_threads(
		channel_id
	)
	if result.ok:
		await _fetch_unknown_authors(
			result.data, client, cdn_url
		)
		var msgs: Array = []
		for msg in result.data:
			var accord_msg: AccordMessage = msg
			msgs.append(
				ClientModels.message_to_dict(
					accord_msg, _c._user_cache, cdn_url
				)
			)
		return msgs
	return []

func fetch_members(guild_id: String) -> void:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		return
	var cdn_url: String = _c._cdn_for_guild(guild_id)
	var all_members: Array = []
	var cursor: String = ""

	# Paginated fetch loop
	while true:
		var params: Dictionary = {"limit": 1000}
		if not cursor.is_empty():
			params["after"] = cursor
		var result: RestResult = await client.members.list(
			guild_id, params
		)
		if not result.ok:
			var err_msg: String = (
				result.error.message
				if result.error
				else "unknown"
			)
			push_error(
				"[Client] Failed to fetch members: ",
				err_msg
			)
			return

		var page: Array = result.data
		if page.is_empty():
			break

		# Collect unique missing user IDs upfront
		var missing_ids: Array = []
		var seen_ids: Dictionary = {}
		for member in page:
			var accord_member: AccordMember = member
			var uid: String = accord_member.user_id
			if not _c._user_cache.has(uid) \
					and not seen_ids.has(uid):
				missing_ids.append(uid)
				seen_ids[uid] = true

		# Fetch missing users (deduplicated)
		for uid in missing_ids:
			var user_result: RestResult = \
				await client.users.fetch(uid)
			if user_result.ok:
				_c._user_cache[uid] = \
					ClientModels.user_to_dict(
						user_result.data,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)

		# Build member dicts (all users now cached)
		for member in page:
			var accord_member: AccordMember = member
			all_members.append(
				ClientModels.member_to_dict(
					accord_member, _c._user_cache
				)
			)

		# Pagination: if page < limit, we're done
		if page.size() < 1000:
			break
		var last_member: AccordMember = page[page.size() - 1]
		cursor = last_member.user_id

	_c._member_cache[guild_id] = all_members
	_c._rebuild_member_index(guild_id)
	AppState.members_updated.emit(guild_id)

func fetch_roles(guild_id: String) -> void:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		return
	var result: RestResult = await client.roles.list(guild_id)
	if result.ok:
		var roles: Array = []
		for role in result.data:
			roles.append(ClientModels.role_to_dict(role))
		_c._role_cache[guild_id] = roles
		AppState.roles_updated.emit(guild_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch roles: ", err_msg
		)

func fetch_voice_states(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		return
	var result: RestResult = await client.voice.get_status(
		channel_id
	)
	if result.ok:
		var states: Array = []
		for state in result.data:
			var vs: AccordVoiceState = state
			states.append(
				ClientModels.voice_state_to_dict(
					vs, _c._user_cache
				)
			)
		_c._voice_state_cache[channel_id] = states
		if _c._channel_cache.has(channel_id):
			_c._channel_cache[channel_id]["voice_users"] = \
				states.size()
		AppState.voice_state_updated.emit(channel_id)
	else:
		var err_msg: String = (
			result.error.message
			if result.error
			else "unknown"
		)
		push_error(
			"[Client] Failed to fetch voice states: ",
			err_msg
		)

func _fetch_dm_previews() -> void:
	var updated := false
	for dm_id in _c._dm_channel_cache:
		var dm: Dictionary = _c._dm_channel_cache[dm_id]
		if not dm.get("last_message", "").is_empty():
			continue  # Already has a preview
		var msg_id: String = dm.get("last_message_id", "")
		if msg_id.is_empty():
			continue
		var client: AccordClient = _c._client_for_channel(
			dm_id
		)
		if client == null:
			continue
		var result: RestResult = await client.messages.fetch(
			dm_id, msg_id
		)
		if result.ok:
			var msg: AccordMessage = result.data
			var preview: String = msg.content
			if preview.length() > 80:
				preview = preview.substr(0, 80) + "..."
			_c._dm_channel_cache[dm_id]["last_message"] = \
				preview
			updated = true
	if updated:
		AppState.dm_channels_updated.emit()
