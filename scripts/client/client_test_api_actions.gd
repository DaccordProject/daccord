class_name ClientTestApiActions
extends RefCounted

## Mutation, moderation, voice, and lifecycle endpoint handlers
## for ClientTestApi.

var _c: Node


func _init(client_node: Node) -> void:
	_c = client_node


# --- Action endpoints ---

func endpoint_send_message(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	var content: String = args.get("content", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	if content.is_empty():
		return {"error": "content is required"}
	var reply_to: String = args.get("reply_to", "")
	var ok: bool = await _c.send_message_to_channel(
		channel_id, content, reply_to
	)
	return {"ok": ok}


func endpoint_edit_message(args: Dictionary) -> Dictionary:
	var message_id: String = args.get("message_id", "")
	var content: String = args.get("content", "")
	if message_id.is_empty():
		return {"error": "message_id is required"}
	if content.is_empty():
		return {"error": "content is required"}
	var ok: bool = await _c.update_message_content(
		message_id, content
	)
	return {"ok": ok}


func endpoint_delete_message(args: Dictionary) -> Dictionary:
	var message_id: String = args.get("message_id", "")
	if message_id.is_empty():
		return {"error": "message_id is required"}
	var ok: bool = await _c.remove_message(message_id)
	return {"ok": ok}


func endpoint_add_reaction(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	var message_id: String = args.get("message_id", "")
	var emoji_name: String = args.get("emoji", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	if message_id.is_empty():
		return {"error": "message_id is required"}
	if emoji_name.is_empty():
		return {"error": "emoji is required"}
	await _c.add_reaction(channel_id, message_id, emoji_name)
	return {"ok": true}


# --- Moderation endpoints ---

func endpoint_kick_member(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.kick_member(
		space_id, user_id
	)
	if result == null:
		return {"error": "Kick failed"}
	return {"ok": result.ok if result else false}


func endpoint_ban_user(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	var reason: String = args.get("reason", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.ban_user(
		space_id, user_id, reason
	)
	if result == null:
		return {"error": "Ban failed"}
	return {"ok": result.ok if result else false}


func endpoint_unban_user(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.unban_user(
		space_id, user_id
	)
	if result == null:
		return {"error": "Unban failed"}
	return {"ok": result.ok if result else false}


func endpoint_timeout_member(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	var duration: int = args.get("duration", 0)
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	if duration <= 0:
		return {"error": "duration is required (seconds)"}
	var result: Variant = await _c.admin.timeout_member(
		space_id, user_id, duration
	)
	if result == null:
		return {"error": "Timeout failed"}
	return {"ok": result.ok if result else false}


# --- Voice endpoints ---

func endpoint_join_voice(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	var ok: bool = await _c.join_voice_channel(channel_id)
	return {"ok": ok}


func endpoint_leave_voice(_args: Dictionary) -> Dictionary:
	var ok: bool = await _c.leave_voice_channel()
	return {"ok": ok}


func endpoint_toggle_mute(_args: Dictionary) -> Dictionary:
	var new_state: bool = not AppState.is_voice_muted
	_c.set_voice_muted(new_state)
	return {"ok": true, "muted": new_state}


func endpoint_toggle_deafen(
	_args: Dictionary,
) -> Dictionary:
	var new_state: bool = not AppState.is_voice_deafened
	_c.set_voice_deafened(new_state)
	return {"ok": true, "deafened": new_state}


# --- Lifecycle endpoints ---

func endpoint_wait_frames(args: Dictionary) -> Dictionary:
	var count: int = args.get("count", 1)
	count = clampi(count, 1, 60)
	for i in count:
		await _c.get_tree().process_frame
	return {"ok": true, "frames_waited": count}


func endpoint_quit(_args: Dictionary) -> Dictionary:
	var response := {"ok": true, "quitting": true}
	_c.get_tree().create_timer(0.1).timeout.connect(
		_c.get_tree().quit
	)
	return response
