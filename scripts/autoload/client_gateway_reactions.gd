class_name ClientGatewayReactions
extends RefCounted

## Handles reaction gateway events for ClientGateway.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

func _parse_emoji_name(data: Dictionary) -> String:
	var raw = data.get("emoji", "")
	if raw is Dictionary:
		return raw.get("name", "")
	if raw is String:
		return raw
	return ""

func on_reaction_add(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	var message_id: String = str(data.get("message_id", ""))
	var user_id: String = str(data.get("user_id", ""))
	var emoji_name: String = _parse_emoji_name(data)
	if channel_id.is_empty() or message_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var is_own: bool = user_id == _c.current_user.get("id", "")
	var msgs: Array = _c._message_cache[channel_id]
	for msg in msgs:
		if msg.get("id", "") == message_id:
			var reactions: Array = msg.get("reactions", [])
			var found := false
			for r in reactions:
				if r.get("emoji", "") == emoji_name:
					# Skip if already applied optimistically
					if is_own and r.get("active", false):
						found = true
						break
					r["count"] = r.get("count", 0) + 1
					if is_own:
						r["active"] = true
					found = true
					break
			if not found:
				reactions.append({
					"emoji": emoji_name,
					"count": 1,
					"active": is_own,
				})
			msg["reactions"] = reactions
			break
	AppState.reactions_updated.emit(channel_id, message_id)

func on_reaction_remove(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	var message_id: String = str(data.get("message_id", ""))
	var user_id: String = str(data.get("user_id", ""))
	var emoji_name: String = _parse_emoji_name(data)
	if channel_id.is_empty() or message_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var is_own: bool = user_id == _c.current_user.get("id", "")
	var msgs: Array = _c._message_cache[channel_id]
	for msg in msgs:
		if msg.get("id", "") == message_id:
			var reactions: Array = msg.get("reactions", [])
			for i in reactions.size():
				if reactions[i].get("emoji", "") == emoji_name:
					# Skip if already applied optimistically
					if is_own and not reactions[i].get("active", true):
						break
					reactions[i]["count"] = max(0, reactions[i].get("count", 0) - 1)
					if is_own:
						reactions[i]["active"] = false
					if reactions[i]["count"] <= 0:
						reactions.remove_at(i)
					break
			msg["reactions"] = reactions
			break
	AppState.reactions_updated.emit(channel_id, message_id)

func on_reaction_clear(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	var message_id: String = str(data.get("message_id", ""))
	if channel_id.is_empty() or message_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var msgs: Array = _c._message_cache[channel_id]
	for msg in msgs:
		if msg.get("id", "") == message_id:
			msg["reactions"] = []
			break
	AppState.reactions_updated.emit(channel_id, message_id)

func on_reaction_clear_emoji(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	var message_id: String = str(data.get("message_id", ""))
	var emoji_name: String = _parse_emoji_name(data)
	if channel_id.is_empty() or message_id.is_empty() or not _c._message_cache.has(channel_id):
		return
	var msgs: Array = _c._message_cache[channel_id]
	for msg in msgs:
		if msg.get("id", "") == message_id:
			var reactions: Array = msg.get("reactions", [])
			for i in reactions.size():
				if reactions[i].get("emoji", "") == emoji_name:
					reactions.remove_at(i)
					break
			msg["reactions"] = reactions
			break
	AppState.reactions_updated.emit(channel_id, message_id)
