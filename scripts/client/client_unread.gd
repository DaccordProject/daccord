extends RefCounted

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func on_channel_selected_clear_unread(cid: String) -> void:
	if _c._unread_channels.has(cid):
		clear_channel_unread(cid)
	else:
		# Still ack to update server read position even if not locally unread
		_ack_channel(cid)

func clear_channel_unread(cid: String) -> void:
	if not _c._unread_channels.has(cid):
		return
	_c._unread_channels.erase(cid)
	_c._channel_mention_counts.erase(cid)
	# Update the cached channel dict
	if _c._channel_cache.has(cid):
		_c._channel_cache[cid]["unread"] = false
		var gid: String = _c._channel_cache[cid].get("space_id", "")
		update_space_unread(gid)
		AppState.channels_updated.emit(gid)
	elif _c._dm_channel_cache.has(cid):
		_c._dm_channel_cache[cid]["unread"] = false
		AppState.dm_channels_updated.emit()
	# Tell the server we've read this channel
	_ack_channel(cid)

func _ack_channel(cid: String) -> void:
	var last_msg_id: String = _get_last_message_id(cid)
	if last_msg_id.is_empty():
		return
	var client: AccordClient = _c._client_for_channel(cid)
	if client == null:
		return
	var result: RestResult = await client.channels.ack(cid, last_msg_id)
	if not result.ok:
		var err: String = result.error.message if result.error else "unknown"
		push_warning("[Client] Failed to ack channel %s: %s" % [cid, err])

func _get_last_message_id(cid: String) -> String:
	# Check message cache for the most recent message
	var msgs: Array = _c._message_cache.get(cid, [])
	if not msgs.is_empty():
		var last: Dictionary = msgs[msgs.size() - 1]
		var mid: String = last.get("id", "")
		if not mid.is_empty():
			return mid
	# Fall back to the channel cache's last_message_id
	if _c._channel_cache.has(cid):
		return _c._channel_cache[cid].get("last_message_id", "")
	if _c._dm_channel_cache.has(cid):
		return _c._dm_channel_cache[cid].get("last_message_id", "")
	return ""

func mark_channel_unread(cid: String, is_mention: bool = false) -> void:
	_c._unread_channels[cid] = true
	if is_mention:
		var cur: int = _c._channel_mention_counts.get(cid, 0)
		_c._channel_mention_counts[cid] = cur + 1
	# Update channel dict
	if _c._channel_cache.has(cid):
		_c._channel_cache[cid]["unread"] = true
		var gid: String = _c._channel_cache[cid].get("space_id", "")
		update_space_unread(gid)
		AppState.channels_updated.emit(gid)
		AppState.spaces_updated.emit()
	elif _c._dm_channel_cache.has(cid):
		_c._dm_channel_cache[cid]["unread"] = true
		AppState.dm_channels_updated.emit()

func update_space_unread(gid: String) -> void:
	if gid.is_empty() or not _c._space_cache.has(gid):
		return
	var has_unread := false
	var total_mentions := 0
	for ch_id in _c._channel_cache:
		var ch: Dictionary = _c._channel_cache[ch_id]
		if ch.get("space_id", "") != gid:
			continue
		if _c._unread_channels.has(ch_id):
			has_unread = true
		total_mentions += _c._channel_mention_counts.get(ch_id, 0)
	_c._space_cache[gid]["unread"] = has_unread
	_c._space_cache[gid]["mentions"] = total_mentions

# --- Channel mute API ---

func is_channel_muted(channel_id: String) -> bool:
	if _c._muted_channels.has(channel_id):
		return true
	# Check if parent category is muted (inherited mute)
	var ch: Dictionary = _c._channel_cache.get(channel_id, {})
	var parent_id: String = ch.get("parent_id", "")
	if not parent_id.is_empty() and _c._muted_channels.has(parent_id):
		return true
	return false

func mute_channel(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return
	var result: RestResult = await client.channels.mute(channel_id)
	if result.ok:
		_c._muted_channels[channel_id] = true
		AppState.channel_mutes_updated.emit()
	else:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[Client] Failed to mute channel: ", err)

func unmute_channel(channel_id: String) -> void:
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error("[Client] No connection for channel: ", channel_id)
		return
	var result: RestResult = await client.channels.unmute(channel_id)
	if result.ok:
		_c._muted_channels.erase(channel_id)
		AppState.channel_mutes_updated.emit()
	else:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[Client] Failed to unmute channel: ", err)
