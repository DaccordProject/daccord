class_name ClientGateway
extends RefCounted

## Handles gateway events for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and fetch methods.

var _c: Node # Client autoload
var _typing_timers: Dictionary = {} # channel_id -> Timer node
var _reactions: ClientGatewayReactions
var _events: ClientGatewayEvents
var _members: ClientGatewayMembers

func _init(client_node: Node) -> void:
	_c = client_node
	_reactions = ClientGatewayReactions.new(client_node)
	_events = ClientGatewayEvents.new(client_node)
	_members = ClientGatewayMembers.new(client_node)

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
		_members.on_member_join.bind(idx))
	client.member_leave.connect(
		_members.on_member_leave.bind(idx))
	client.member_update.connect(
		_members.on_member_update.bind(idx))
	client.member_chunk.connect(
		_members.on_member_chunk.bind(idx))
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
	client.raw_event.connect(
		on_gateway_raw_event.bind(idx))

func on_gateway_ready(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	print("[Client] Gateway ready for: ", conn["config"]["base_url"])
	_c._auto_reconnect_attempted.erase(conn_index)
	# Parse server version from READY payload (if provided)
	var srv_version: String = _data.get("server_version", "")
	var api_version: String = _data.get("api_version", "")
	if not srv_version.is_empty():
		conn["server_version"] = srv_version
	if not api_version.is_empty():
		conn["api_version"] = api_version
		if api_version != AccordConfig.API_VERSION:
			AppState.server_version_warning.emit(
				conn["space_id"], srv_version,
				AccordConfig.CLIENT_VERSION
			)
	# Emit reconnected if this was a reconnect after disconnect
	var was_down: bool = conn.get("_was_disconnected", false) \
		or conn["status"] != "connected"
	conn["_was_disconnected"] = false
	conn["status"] = "connected"
	var space_id: String = conn["space_id"]
	if was_down and not space_id.is_empty():
		AppState.server_reconnected.emit(space_id)
	# Refetch all data (awaited so server_synced fires after completion)
	await _refetch_data(conn, conn_index)

	# Apply initial presences from READY payload
	var presences: Array = _data.get("presences", [])
	_apply_presences(presences, space_id)

func _apply_presences(presences: Array, space_id: String) -> void:
	for p in presences:
		if not p is Dictionary:
			continue
		var uid: String = str(p.get("user_id", ""))
		if uid.is_empty():
			continue
		var status: int = ClientModels._status_string_to_enum(
			p.get("status", "offline")
		)
		# Update user cache
		if _c._user_cache.has(uid):
			_c._user_cache[uid]["status"] = status
			_c._user_cache[uid]["client_status"] = p.get(
				"client_status", {}
			)
			_c._user_cache[uid]["activities"] = p.get(
				"activities", []
			)
		# Update member cache
		if not space_id.is_empty():
			var idx: int = _c._member_index_for(space_id, uid)
			if idx != -1:
				_c._member_cache[space_id][idx]["status"] = status
	# Notify UI
	if not space_id.is_empty():
		AppState.members_updated.emit(space_id)

func on_gateway_disconnected(code: int, reason: String, conn_index: int) -> void:
	if _c.is_shutting_down:
		return
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	var space_id: String = conn["space_id"]
	var fatal_codes := [4003, 4004, 4012, 4013, 4014]
	if code in fatal_codes:
		# Escalate to full reconnect (with re-auth) instead of
		# giving up immediately. _handle_gateway_reconnect_failed
		# will go to "error" if it has already been tried once.
		conn["status"] = "disconnected"
		conn["_was_disconnected"] = true
		AppState.server_disconnected.emit(space_id, code, reason)
		_c.call_deferred(
			"_handle_gateway_reconnect_failed", conn_index
		)
	else:
		conn["status"] = "disconnected"
		conn["_was_disconnected"] = true
		AppState.server_disconnected.emit(space_id, code, reason)

func on_gateway_reconnecting(attempt: int, max_attempts: int, conn_index: int) -> void:
	if _c.is_shutting_down:
		return
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	conn["status"] = "reconnecting"
	AppState.server_reconnecting.emit(conn["space_id"], attempt, max_attempts)
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
	AppState.server_reconnected.emit(conn["space_id"])
	# RESUME path: also refetch data since server restart invalidates state
	await _refetch_data(conn, conn_index)

func on_gateway_raw_event(
	_event_type: String, _data: Dictionary, conn_index: int
) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	if conn.get("status", "") == "connected":
		return
	var space_id: String = conn.get("space_id", "")
	conn["status"] = "connected"
	conn["_was_disconnected"] = false
	_c._auto_reconnect_attempted.erase(conn_index)
	if not space_id.is_empty():
		AppState.server_reconnected.emit(space_id)

func _refetch_data(conn: Dictionary, conn_index: int) -> void:
	var space_id: String = conn["space_id"]
	conn["_syncing"] = true
	if not space_id.is_empty():
		await _c.fetch.fetch_channels(space_id)
		await _c.fetch.fetch_members(space_id)
		await _c.fetch.fetch_roles(space_id)
		_c.fetch.resync_voice_states(space_id)
		await _c.fetch.refresh_current_user(conn_index)
	await _c.fetch.fetch_dm_channels()
	conn["_syncing"] = false
	if not space_id.is_empty():
		AppState.server_synced.emit(space_id)

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

	# Thread reply handling: route to thread cache if this is a thread reply
	if message.thread_id != null and not str(message.thread_id).is_empty():
		var tid: String = str(message.thread_id)
		# Add to thread message cache if we're tracking this thread
		if _c._thread_message_cache.has(tid):
			# Skip if already in cache
			var already_cached := false
			for existing in _c._thread_message_cache[tid]:
				if existing.get("id", "") == message.id:
					already_cached = true
					break
			if not already_cached:
				_c._thread_message_cache[tid].append(msg_dict)
		# Update parent message's reply_count in main cache
		var parent_cid: String = _c._message_id_index.get(tid, "")
		if not parent_cid.is_empty() and _c._message_cache.has(parent_cid):
			for parent_msg in _c._message_cache[parent_cid]:
				if parent_msg.get("id", "") == tid:
					parent_msg["reply_count"] = parent_msg.get("reply_count", 0) + 1
					break
			AppState.messages_updated.emit(parent_cid)
		# Update reply_count and last_reply_at in forum post cache
		for forum_ch_id in _c._forum_post_cache:
			var forum_posts: Array = _c._forum_post_cache[forum_ch_id]
			for fp in forum_posts:
				if fp.get("id", "") == tid:
					fp["reply_count"] = fp.get("reply_count", 0) + 1
					fp["last_reply_at"] = msg_dict.get("timestamp", "")
					AppState.forum_posts_updated.emit(forum_ch_id)
					break
		# Mark thread as unread if panel is not open for it
		if AppState.current_thread_id != tid:
			_c._thread_unread[tid] = true
		# Emit thread update signal
		if AppState.current_thread_id == tid:
			AppState.thread_messages_updated.emit(tid)
		return

	# Forum channel: top-level message = new post → insert into forum post cache
	if _c._channel_cache.has(message.channel_id):
		var ch_type: int = _c._channel_cache[message.channel_id].get("type", 0)
		if ch_type == ClientModels.ChannelType.FORUM:
			if not _c._forum_post_cache.has(message.channel_id):
				_c._forum_post_cache[message.channel_id] = []
			_c._forum_post_cache[message.channel_id].insert(0, msg_dict)
			_c._message_id_index[message.id] = message.channel_id
			AppState.forum_posts_updated.emit(message.channel_id)
			return

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
			var space_id: String = _c._channel_to_space.get(message.channel_id, "")
			if Config.is_server_muted(space_id):
				pass # Server is muted — skip unread tracking
			else:
				# Determine if this is a mention
				var is_mention: bool = my_id in message.mentions
				if message.mention_everyone and not Config.get_suppress_everyone():
					is_mention = true
				if not is_mention:
					is_mention = _has_role_mention(message.mention_roles, space_id)

				# Enforce default_notifications setting
				var space: Dictionary = _c._space_cache.get(space_id, {})
				var notif_level: String = space.get("default_notifications", "all")
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
	var cdn_url := ""
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		cdn_url = _c._connections[conn_index]["cdn_url"]
	var msg_dict := ClientModels.message_to_dict(message, _c._user_cache, cdn_url)

	# Thread reply: update in thread cache
	if message.thread_id != null and not str(message.thread_id).is_empty():
		var tid: String = str(message.thread_id)
		if _c._thread_message_cache.has(tid):
			var thread_msgs: Array = _c._thread_message_cache[tid]
			for i in thread_msgs.size():
				if thread_msgs[i].get("id", "") == message.id:
					thread_msgs[i] = msg_dict
					break
		if AppState.current_thread_id == tid:
			AppState.thread_messages_updated.emit(tid)
		return

	# Update forum post cache if applicable
	if _c._forum_post_cache.has(message.channel_id):
		var forum_posts: Array = _c._forum_post_cache[message.channel_id]
		for i in forum_posts.size():
			if forum_posts[i].get("id", "") == message.id:
				forum_posts[i] = msg_dict
				AppState.forum_posts_updated.emit(message.channel_id)
				break

	if not _c._message_cache.has(message.channel_id):
		return
	var msgs: Array = _c._message_cache[message.channel_id]
	for i in msgs.size():
		if msgs[i].get("id", "") == message.id:
			msgs[i] = msg_dict
			break
	AppState.messages_updated.emit(message.channel_id)

func on_message_delete(data: Dictionary) -> void:
	var msg_id: String = data.get("id", "")
	var channel_id: String = data.get("channel_id", "")

	# Check if this is a thread reply deletion
	for tid in _c._thread_message_cache:
		var thread_msgs: Array = _c._thread_message_cache[tid]
		for i in thread_msgs.size():
			if thread_msgs[i].get("id", "") == msg_id:
				thread_msgs.remove_at(i)
				# Decrement parent message reply_count
				var parent_cid: String = _c._message_id_index.get(tid, "")
				if not parent_cid.is_empty() and _c._message_cache.has(parent_cid):
					for parent_msg in _c._message_cache[parent_cid]:
						if parent_msg.get("id", "") == tid:
							parent_msg["reply_count"] = maxi(parent_msg.get("reply_count", 1) - 1, 0)
							break
					AppState.messages_updated.emit(parent_cid)
				if AppState.current_thread_id == tid:
					AppState.thread_messages_updated.emit(tid)
				return

	# Remove from forum post cache if applicable
	if not channel_id.is_empty() and _c._forum_post_cache.has(channel_id):
		var forum_posts: Array = _c._forum_post_cache[channel_id]
		for i in forum_posts.size():
			if forum_posts[i].get("id", "") == msg_id:
				forum_posts.remove_at(i)
				_c._message_id_index.erase(msg_id)
				AppState.forum_posts_updated.emit(channel_id)
				return

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
		var space_id: String = _c._connections[conn_index]["space_id"]
		var idx: int = _c._member_index_for(space_id, presence.user_id)
		if idx != -1:
			var new_status: int = ClientModels._status_string_to_enum(presence.status)
			var old_status: int = _c._member_cache[space_id][idx].get("status", -1)
			_c._member_cache[space_id][idx]["status"] = new_status
			if old_status != new_status:
				AppState.member_status_changed.emit(
					space_id, presence.user_id, new_status
				)
			AppState.members_updated.emit(space_id)

func on_user_update(user: AccordUser, conn_index: int) -> void:
	var cdn_url := ""
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		cdn_url = _c._connections[conn_index]["cdn_url"]
	var existing: Dictionary = _c._user_cache.get(user.id, {})
	var status: int = existing.get("status", ClientModels.UserStatus.OFFLINE)
	var user_dict: Dictionary = ClientModels.user_to_dict(user, status, cdn_url)
	_c._user_cache[user.id] = user_dict
	if _c.current_user.get("id", "") == user.id:
		_c.current_user = user_dict
	# Propagate display_name/avatar changes to member_cache entries
	for gid in _c._member_cache:
		var idx: int = _c._member_index_for(gid, user.id)
		if idx != -1:
			var member: Dictionary = _c._member_cache[gid][idx]
			member["display_name"] = user_dict.get("display_name", member.get("display_name", ""))
			member["avatar"] = user_dict.get("avatar", member.get("avatar", ""))
			member["username"] = user_dict.get("username", member.get("username", ""))
			AppState.members_updated.emit(gid)
	AppState.user_updated.emit(user.id)

func on_channel_pins_update(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	if not channel_id.is_empty():
		AppState.messages_updated.emit(channel_id)

func on_interaction_create(_interaction: AccordInteraction, _conn_index: int) -> void:
	pass # No interaction UI; wired to prevent silent drop

func on_space_create(space: AccordSpace, conn_index: int) -> void:
	if conn_index < _c._connections.size() and _c._connections[conn_index] != null:
		var conn: Dictionary = _c._connections[conn_index]
		if space.id == conn["space_id"]:
			var cdn_url: String = conn.get("cdn_url", "")
			var new_space: Dictionary = ClientModels.space_to_dict(space, cdn_url)
			new_space["folder"] = Config.get_space_folder(space.id)
			_c._space_cache[space.id] = new_space
			AppState.spaces_updated.emit()

func on_space_update(space: AccordSpace) -> void:
	if _c._space_cache.has(space.id):
		var old_space: Dictionary = _c._space_cache[space.id]
		var cdn_url: String = _c._cdn_for_space(space.id)
		var new_space: Dictionary = ClientModels.space_to_dict(space, cdn_url)
		new_space["unread"] = old_space.get("unread", false)
		new_space["mentions"] = old_space.get("mentions", 0)
		new_space["folder"] = old_space.get("folder", "")
		_c._space_cache[space.id] = new_space
		AppState.spaces_updated.emit()

func on_space_delete(data: Dictionary) -> void:
	var space_id: String = data.get("id", "")
	_c._space_cache.erase(space_id)
	_c._space_to_conn.erase(space_id)
	AppState.spaces_updated.emit()

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
		var space_id: String = str(channel.space_id) if channel.space_id != null else ""
		_c._channel_to_space[channel.id] = space_id
		AppState.channels_updated.emit(space_id)

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
		var space_id: String = str(channel.space_id) if channel.space_id != null else ""
		_c._channel_to_space[channel.id] = space_id
		AppState.channels_updated.emit(space_id)

func on_channel_delete(channel: AccordChannel) -> void:
	if channel.type == "dm" or channel.type == "group_dm":
		_c._dm_channel_cache.erase(channel.id)
		AppState.dm_channels_updated.emit()
	else:
		_c._channel_cache.erase(channel.id)
		_c._channel_to_space.erase(channel.id)
		var space_id: String = str(channel.space_id) if channel.space_id != null else ""
		AppState.channels_updated.emit(space_id)

func on_role_create(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var role := AccordRole.from_dict(data.get("role", data))
	var role_dict := ClientModels.role_to_dict(role)
	if not _c._role_cache.has(space_id):
		_c._role_cache[space_id] = []
	_c._role_cache[space_id].append(role_dict)
	AppState.roles_updated.emit(space_id)

func on_role_update(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var role := AccordRole.from_dict(data.get("role", data))
	var role_dict := ClientModels.role_to_dict(role)
	if _c._role_cache.has(space_id):
		var roles: Array = _c._role_cache[space_id]
		for i in roles.size():
			if roles[i].get("id", "") == role_dict["id"]:
				roles[i] = role_dict
				break
	AppState.roles_updated.emit(space_id)

func on_role_delete(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var role_id: String = str(data.get("role_id", data.get("id", "")))
	if _c._role_cache.has(space_id):
		var roles: Array = _c._role_cache[space_id]
		for i in roles.size():
			if roles[i].get("id", "") == role_id:
				roles.remove_at(i)
				break
	AppState.roles_updated.emit(space_id)

func _has_role_mention(mention_roles: Array, space_id: String) -> bool:
	if mention_roles.is_empty() or space_id.is_empty():
		return false
	var my_id: String = _c.current_user.get("id", "")
	var idx: int = _c._member_index_for(space_id, my_id)
	if idx == -1:
		return false
	var my_roles: Array = _c._member_cache.get(space_id, [])[idx].get("roles", [])
	for role_id in mention_roles:
		if role_id in my_roles:
			return true
	return false
