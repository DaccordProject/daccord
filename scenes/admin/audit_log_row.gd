extends HBoxContainer

@onready var _icon_label: Label = $IconLabel
@onready var _user_label: Label = $UserLabel
@onready var _action_label: Label = $ActionLabel
@onready var _target_label: Label = $TargetLabel
@onready var _time_label: Label = $TimeLabel


func setup(entry: Dictionary) -> void:
	var action: String = entry.get("action_type", "")
	_icon_label.text = _action_icon(action)
	_user_label.text = _resolve_user(entry.get("user_id", ""))
	_action_label.text = _format_action(action)
	_target_label.text = _format_target(entry)
	_time_label.text = _relative_time(entry.get("created_at", ""))


func _action_icon(action: String) -> String:
	match action:
		"member_kick":
			return "🚪"
		"member_ban_add":
			return "🔨"
		"member_ban_remove":
			return "🔓"
		"member_update", "member_role_update":
			return "👤"
		"role_create":
			return "🏷"
		"role_update":
			return "🏷"
		"role_delete":
			return "🗑"
		"channel_create":
			return "📝"
		"channel_update":
			return "📝"
		"channel_delete":
			return "🗑"
		"space_update":
			return "⚙"
		"invite_create":
			return "📨"
		"invite_delete":
			return "📨"
		"message_delete":
			return "💬"
		_:
			return "📋"


func _format_action(action: String) -> String:
	return action.replace("_", " ").capitalize()


func _resolve_user(user_id: String) -> String:
	if user_id.is_empty():
		return "System"
	var members: Array = Client.get_members_for_guild(
		AppState.current_guild_id
	)
	for m in members:
		if str(m.get("user_id", "")) == user_id:
			return m.get("display_name", m.get("username", user_id))
	return user_id


func _format_target(entry: Dictionary) -> String:
	var target_id: String = str(entry.get("target_id", ""))
	var target_type: String = entry.get("target_type", "")
	if target_id.is_empty():
		return ""
	match target_type:
		"member", "user":
			return "user:" + target_id.right(4)
		"role":
			return "role:" + target_id.right(4)
		"channel":
			return "ch:" + target_id.right(4)
		_:
			return target_id.right(6)


func _relative_time(timestamp: String) -> String:
	if timestamp.is_empty():
		return ""
	# Parse ISO-8601 timestamp to relative string
	var dt := Time.get_datetime_dict_from_datetime_string(timestamp, false)
	if dt.is_empty():
		return timestamp
	var unix: int = Time.get_unix_time_from_datetime_dict(dt)
	var now: int = int(Time.get_unix_time_from_system())
	var diff: int = now - unix
	if diff < 60:
		return "just now"
	elif diff < 3600:
		var mins: int = diff / 60
		return "%dm ago" % mins
	elif diff < 86400:
		var hours: int = diff / 3600
		return "%dh ago" % hours
	elif diff < 604800:
		var days: int = diff / 86400
		return "%dd ago" % days
	else:
		return timestamp.left(10)
