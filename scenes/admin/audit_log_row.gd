extends VBoxContainer

const _ACTION_ICONS := {
	"member_kick": "🚪",
	"member_ban_add": "🔨",
	"member_ban_remove": "🔓",
	"member_update": "👤",
	"member_role_update": "👤",
	"role_create": "🏷",
	"role_update": "🏷",
	"role_delete": "🗑",
	"channel_create": "📝",
	"channel_update": "📝",
	"channel_delete": "🗑",
	"space_update": "⚙",
	"invite_create": "📨",
	"invite_delete": "📨",
	"message_delete": "💬",
	"automod_block": "🛡",
	"automod_delete": "🛡",
	"automod_flag": "🚩",
	"automod_csam_report": "⚠",
	"report_create": "📢",
	"report_resolve": "📢",
	"invite_accept": "📩",
	"member_join": "👋",
}

var _space_id: String = ""

@onready var _icon_label: Label = $Row/IconLabel
@onready var _user_label: Label = $Row/UserLabel
@onready var _action_label: Label = $Row/ActionLabel
@onready var _target_label: Label = $Row/TargetLabel
@onready var _time_label: Label = $Row/TimeLabel
@onready var _changes_panel: VBoxContainer = $ChangesPanel


func _ready() -> void:
	ThemeManager.apply_font_colors(self)


func setup(entry: Dictionary, space_id: String = "") -> void:
	_space_id = space_id if not space_id.is_empty() \
		else AppState.current_space_id
	var action: String = entry.get("action_type", "")
	_icon_label.text = _action_icon(action)
	_user_label.text = _resolve_user(entry.get("user_id", ""))
	_action_label.text = _format_action(action)
	_target_label.text = _format_target(entry)
	_time_label.text = _relative_time(entry.get("created_at", ""))
	_setup_changes(entry.get("changes", null))


func _action_icon(action: String) -> String:
	return _ACTION_ICONS.get(action, "📋")


func _format_action(action: String) -> String:
	return action.replace("_", " ").capitalize()


func _resolve_user(user_id: String) -> String:
	if user_id.is_empty():
		return tr("System")
	# Check space member cache first
	var members: Array = Client.get_members_for_space(_space_id)
	for m in members:
		if str(m.get("user_id", "")) == user_id:
			return m.get("display_name", m.get("username", user_id))
	# Fall back to global user cache
	var user: Dictionary = Client.get_user_by_id(user_id)
	if not user.is_empty():
		return user.get("display_name", user.get("username", user_id))
	return user_id


func _format_target(entry: Dictionary) -> String:
	var target_id: String = str(entry.get("target_id", ""))
	var target_type: String = entry.get("target_type", "")
	if target_id.is_empty():
		return ""
	match target_type:
		"member", "user":
			return _resolve_user(target_id)
		"role":
			return _resolve_role(target_id)
		"channel":
			return _resolve_channel(target_id)
		"invite":
			var result: String = "invite"
			var changes: Variant = entry.get("changes", null)
			if changes is Dictionary:
				var code: String = str(changes.get("invite_code", ""))
				var inviter: String = str(changes.get("inviter_id", ""))
				if not inviter.is_empty() and inviter != "<null>":
					result = "code:%s by %s" % [code, _resolve_user(inviter)]
				elif not code.is_empty():
					result = "code:" + code
			return result
		_:
			return target_id.right(6)


func _resolve_role(role_id: String) -> String:
	var roles: Array = Client.get_roles_for_space(_space_id)
	for r in roles:
		if str(r.get("id", "")) == role_id:
			return r.get("name", "role:" + role_id.right(4))
	return "role:" + role_id.right(4)


func _resolve_channel(channel_id: String) -> String:
	var channels: Array = Client.get_channels_for_space(_space_id)
	for ch in channels:
		if str(ch.get("id", "")) == channel_id:
			return "#" + ch.get("name", "ch:" + channel_id.right(4))
	return "ch:" + channel_id.right(4)


func _setup_changes(changes: Variant) -> void:
	_changes_panel.visible = false
	if changes == null:
		return
	if changes is Dictionary and changes.is_empty():
		return
	if changes is Array and changes.is_empty():
		return

	var toggle_btn := Button.new()
	toggle_btn.text = tr("Show Details")
	toggle_btn.flat = true
	toggle_btn.add_theme_font_size_override("font_size", 11)
	toggle_btn.set_meta("theme_font_color", "accent")
	ThemeManager.apply_font_colors(toggle_btn)

	var detail_box := VBoxContainer.new()
	detail_box.visible = false
	detail_box.add_theme_constant_override("separation", 2)

	if changes is Dictionary:
		_add_dict_changes(detail_box, changes)
	elif changes is Array:
		for item in changes:
			if item is Dictionary:
				_add_dict_changes(detail_box, item)

	if detail_box.get_child_count() == 0:
		return

	toggle_btn.pressed.connect(func() -> void:
		detail_box.visible = not detail_box.visible
		toggle_btn.text = tr("Hide Details") if detail_box.visible \
			else tr("Show Details")
	)

	_changes_panel.add_child(toggle_btn)
	_changes_panel.add_child(detail_box)
	_changes_panel.visible = true


func _add_dict_changes(container: VBoxContainer, d: Dictionary) -> void:
	for key: String in d:
		var value: Variant = d[key]
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.set_meta("theme_font_color", "text_muted")
		ThemeManager.apply_font_colors(label)

		if value is Dictionary and (value.has("old") or value.has("new")):
			var old_val: String = str(value.get("old", ""))
			var new_val: String = str(value.get("new", ""))
			label.text = "  %s: %s -> %s" % [
				key.replace("_", " ").capitalize(), old_val, new_val
			]
		else:
			label.text = "  %s: %s" % [
				key.replace("_", " ").capitalize(), str(value)
			]

		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		container.add_child(label)


func _relative_time(timestamp: String) -> String:
	if timestamp.is_empty():
		return ""
	var dt := Time.get_datetime_dict_from_datetime_string(
		timestamp, false
	)
	if dt.is_empty():
		return timestamp
	var unix: int = Time.get_unix_time_from_datetime_dict(dt)
	var now: int = int(Time.get_unix_time_from_system())
	var diff: int = now - unix
	var thresholds := [
		[60, tr("just now"), 1],
		[3600, tr("%dm ago"), 60],
		[86400, tr("%dh ago"), 3600],
		[604800, tr("%dd ago"), 86400],
	]
	for t in thresholds:
		if diff < t[0]:
			if t[2] == 1:
				return t[1]
			return t[1] % (diff / t[2])
	return timestamp.left(10)
