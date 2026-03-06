extends RefCounted

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func on_channel_selected_clear_unread(cid: String) -> void:
	clear_channel_unread(cid)

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
