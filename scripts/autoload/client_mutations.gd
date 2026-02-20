class_name ClientMutations
extends RefCounted

## Handles data mutation operations for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and emit AppState signals.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

# --- Search API ---

func search_messages(
	guild_id: String, query_str: String,
	filters: Dictionary = {},
) -> Dictionary:
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		return {"results": [], "has_more": false}
	var cdn_url: String = _c._cdn_for_guild(guild_id)
	var result: RestResult = await client.messages.search(
		guild_id, query_str, filters
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to search messages: ", err
		)
		return {"results": [], "has_more": false}
	var msgs: Array = []
	for msg in result.data:
		var accord_msg: AccordMessage = msg
		if not _c._user_cache.has(accord_msg.author_id):
			var user_result: RestResult = \
				await client.users.fetch(
					accord_msg.author_id
				)
			if user_result.ok:
				_c._user_cache[accord_msg.author_id] = \
					ClientModels.user_to_dict(
						user_result.data,
						ClientModels.UserStatus.OFFLINE,
						cdn_url
					)
		msgs.append(
			ClientModels.message_to_dict(
				accord_msg, _c._user_cache, cdn_url
			)
		)
	var has_more: bool = msgs.size() >= filters.get(
		"limit", 25
	)
	return {"results": msgs, "has_more": has_more}

# --- Message mutations ---

func send_message_to_channel(
	cid: String, content: String, reply_to: String = "",
	attachments: Array = []
) -> bool:
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		AppState.message_send_failed.emit(
			cid, content, "No connection found"
		)
		return false
	var data := {"content": content}
	if not reply_to.is_empty():
		data["reply_to"] = reply_to
	var result: RestResult
	if attachments.is_empty():
		result = await client.messages.create(cid, data)
	else:
		result = await client.messages.create_with_attachments(
			cid, data, attachments
		)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to send message: ", err
		)
		AppState.message_send_failed.emit(
			cid, content, err
		)
		return false
	return true

func update_message_content(
	mid: String, new_content: String
) -> bool:
	var cid: String = _c._find_channel_for_message(mid)
	if cid.is_empty():
		push_error(
			"[Client] Cannot find channel for message: ",
			mid
		)
		AppState.message_edit_failed.emit(
			mid, "Cannot find channel for message"
		)
		return false
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		AppState.message_edit_failed.emit(
			mid, "No connection found"
		)
		return false
	var result := await client.messages.edit(
		cid, mid, {"content": new_content}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to edit message: ", err
		)
		AppState.message_edit_failed.emit(mid, err)
		return false
	return true

func remove_message(mid: String) -> bool:
	var cid: String = _c._find_channel_for_message(mid)
	if cid.is_empty():
		push_error(
			"[Client] Cannot find channel for message: ",
			mid
		)
		AppState.message_delete_failed.emit(
			mid, "Cannot find channel for message"
		)
		return false
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		AppState.message_delete_failed.emit(
			mid, "No connection found"
		)
		return false
	var result := await client.messages.delete(cid, mid)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to delete message: ", err
		)
		AppState.message_delete_failed.emit(mid, err)
		return false
	return true

# --- Reaction mutations ---

func add_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		AppState.reaction_failed.emit(
			cid, mid, emoji, "No connection found"
		)
		return
	# Optimistic cache update — emit only for new emoji
	# (existing pills handle their own visual update)
	var is_new := _update_reaction_cache_add(
		cid, mid, emoji
	)
	if is_new:
		AppState.reactions_updated.emit(cid, mid)
	var result := await client.reactions.add(
		cid, mid, emoji
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to add reaction: ", err
		)
		# Revert optimistic update
		_update_reaction_cache_remove(cid, mid, emoji)
		AppState.reactions_updated.emit(cid, mid)
		AppState.reaction_failed.emit(
			cid, mid, emoji, err
		)

## Updates the reaction cache for an add. Returns true if a new
## emoji was appended (no existing pill), false otherwise.
func _update_reaction_cache_add(
	cid: String, mid: String, emoji: String,
) -> bool:
	if not _c._message_cache.has(cid):
		return false
	for msg in _c._message_cache[cid]:
		if msg.get("id", "") != mid:
			continue
		var reactions: Array = msg.get("reactions", [])
		for r in reactions:
			if r.get("emoji", "") == emoji:
				r["count"] = r.get("count", 0) + 1
				r["active"] = true
				msg["reactions"] = reactions
				return false # Existing emoji
		reactions.append({
			"emoji": emoji,
			"count": 1,
			"active": true,
		})
		msg["reactions"] = reactions
		return true # New emoji
	return false

func remove_reaction(
	cid: String, mid: String, emoji: String
) -> void:
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		AppState.reaction_failed.emit(
			cid, mid, emoji, "No connection found"
		)
		return
	# Optimistic cache update — emit only when emoji is
	# fully removed (existing pills handle visual update)
	var was_removed := _update_reaction_cache_remove(
		cid, mid, emoji
	)
	if was_removed:
		AppState.reactions_updated.emit(cid, mid)
	var result := await client.reactions.remove_own(
		cid, mid, emoji
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to remove reaction: ", err
		)
		# Revert optimistic update
		_update_reaction_cache_add(cid, mid, emoji)
		AppState.reactions_updated.emit(cid, mid)
		AppState.reaction_failed.emit(
			cid, mid, emoji, err
		)

func remove_all_reactions(
	cid: String, mid: String,
) -> void:
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		push_error(
			"[Client] No connection for channel: ", cid
		)
		return
	var result := await client.reactions.remove_all(
		cid, mid
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to remove all reactions: ",
			err
		)

## Updates the reaction cache for a remove. Returns true if the
## emoji was fully removed (count hit 0), false otherwise.
func _update_reaction_cache_remove(
	cid: String, mid: String, emoji: String,
) -> bool:
	if not _c._message_cache.has(cid):
		return false
	for msg in _c._message_cache[cid]:
		if msg.get("id", "") != mid:
			continue
		var reactions: Array = msg.get("reactions", [])
		for i in reactions.size():
			if reactions[i].get("emoji", "") != emoji:
				continue
			reactions[i]["count"] = max(
				0, reactions[i].get("count", 0) - 1
			)
			reactions[i]["active"] = false
			if reactions[i]["count"] <= 0:
				reactions.remove_at(i)
				msg["reactions"] = reactions
				return true # Fully removed
			msg["reactions"] = reactions
			return false # Still has other users
		break
	return false

# --- Presence & typing ---

func update_presence(
	status: int, activity: Dictionary = {},
) -> void:
	_c.current_user["status"] = status
	var my_id: String = _c.current_user.get("id", "")
	if _c._user_cache.has(my_id):
		_c._user_cache[my_id]["status"] = status
	Config.set_user_status(status)
	var s := ClientModels._status_enum_to_string(status)
	for conn in _c._connections:
		if conn != null \
				and conn["status"] == "connected" \
				and conn["client"] != null:
			conn["client"].update_presence(s, activity)
	AppState.user_updated.emit(my_id)
	for gid in _c._member_cache:
		for md in _c._member_cache[gid]:
			if md.get("id", "") == my_id:
				md["status"] = status
				break
		AppState.members_updated.emit(gid)

func send_typing(cid: String) -> void:
	var client: AccordClient = _c._client_for_channel(cid)
	if client != null:
		client.messages.typing(cid)

# --- Profile management ---

func update_profile(data: Dictionary) -> bool:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		push_error("[Client] No connected client for update_profile")
		return false
	var cdn_url: String = _c._first_connected_cdn()
	var result: RestResult = await client.users.update_me(data)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error("[Client] Failed to update profile: ", err)
		return false
	var user: AccordUser = result.data
	var status: int = _c.current_user.get(
		"status", ClientModels.UserStatus.ONLINE
	)
	var user_dict := ClientModels.user_to_dict(
		user, status, cdn_url
	)
	# Preserve presence details
	var old: Dictionary = _c._user_cache.get(user.id, {})
	user_dict["client_status"] = old.get("client_status", {})
	user_dict["activities"] = old.get("activities", [])
	_c._user_cache[user.id] = user_dict
	_c.current_user = user_dict
	AppState.user_updated.emit(user.id)
	return true

# --- Password & account management ---

func change_password(
	current_pw: String, new_pw: String,
) -> Dictionary:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		return {"ok": false, "error": "Not connected"}
	var result: RestResult = await client.auth.change_password({
		"current_password": current_pw,
		"new_password": new_pw,
	})
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		return {"ok": false, "error": err}
	return {"ok": true}

func delete_account(password: String) -> Dictionary:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		return {"ok": false, "error": "Not connected"}
	var result: RestResult = await client.users.delete_me(
		{"password": password}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		return {"ok": false, "error": err}
	return {"ok": true}

# --- DM management ---

func create_dm(user_id: String) -> void:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for create_dm"
		)
		return
	var cdn_url: String = _c._first_connected_cdn()
	var result: RestResult = await client.users.create_dm(
		{"recipient_id": user_id}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error("[Client] Failed to create DM: ", err)
		return
	var channel: AccordChannel = result.data
	# Cache the recipient
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
	_c._dm_channel_cache[channel.id] = \
		ClientModels.dm_channel_to_dict(
			channel, _c._user_cache
		)
	AppState.dm_channels_updated.emit()
	AppState.enter_dm_mode()
	AppState.select_channel(channel.id)

func create_group_dm(user_ids: Array) -> void:
	var client: AccordClient = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for create_group_dm"
		)
		return
	var cdn_url: String = _c._first_connected_cdn()
	var result: RestResult = await client.users.create_dm(
		{"recipients": user_ids}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to create group DM: ", err
		)
		return
	var channel: AccordChannel = result.data
	# Cache all recipients
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
	_c._dm_channel_cache[channel.id] = \
		ClientModels.dm_channel_to_dict(
			channel, _c._user_cache
		)
	AppState.dm_channels_updated.emit()
	AppState.enter_dm_mode()
	AppState.select_channel(channel.id)


func add_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for add_dm_member"
		)
		return false
	var result: RestResult = \
		await client.channels.add_recipient(
			channel_id, user_id
		)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to add DM member: ", err
		)
		return false
	return true


func remove_dm_member(
	channel_id: String, user_id: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for remove_dm_member"
		)
		return false
	var result: RestResult = \
		await client.channels.remove_recipient(
			channel_id, user_id
		)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to remove DM member: ", err
		)
		return false
	# If removing self, clean up cache
	if user_id == _c.current_user.get("id", ""):
		_c._dm_channel_cache.erase(channel_id)
		_c._dm_to_conn.erase(channel_id)
		if AppState.current_channel_id == channel_id:
			AppState.current_channel_id = ""
		AppState.dm_channels_updated.emit()
	return true


func rename_group_dm(
	channel_id: String, new_name: String,
) -> bool:
	var client: AccordClient = _c._client_for_channel(
		channel_id
	)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for rename_group_dm"
		)
		return false
	var result: RestResult = await client.channels.update(
		channel_id, {"name": new_name}
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to rename group DM: ", err
		)
		return false
	return true


func close_dm(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		client = _c._first_connected_client()
	if client == null:
		push_error(
			"[Client] No connected client for close_dm"
		)
		return
	var result: RestResult = await client.channels.delete(
		channel_id
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error("[Client] Failed to close DM: ", err)
		return
	_c._dm_channel_cache.erase(channel_id)
	_c._dm_to_conn.erase(channel_id)
	# If we were viewing this DM, clear selection
	if AppState.current_channel_id == channel_id:
		AppState.current_channel_id = ""
	AppState.dm_channels_updated.emit()

func try_reauth(
	base_url: String, username: String, password: String,
) -> String:
	if username.is_empty() or password.is_empty():
		return ""
	var api_url := base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	_c.add_child(rest)
	var auth := AuthApi.new(rest)
	var result := await auth.login(
		{"username": username, "password": password}
	)
	rest.queue_free()
	if result.ok and result.data is Dictionary:
		return result.data.get("token", "")
	return ""
