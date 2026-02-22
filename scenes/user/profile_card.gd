extends PanelContainer

## Floating user profile card shown on avatar/username click.

const _ACTIVITY_PREFIXES := {
	"playing": "Playing ",
	"streaming": "Streaming ",
	"listening": "Listening to ",
	"watching": "Watching ",
	"competing": "Competing in ",
	"custom": "",
}

var _user_data: Dictionary = {}
var _guild_id: String = ""

var _banner_rect: ColorRect
var _avatar: ColorRect
var _status_dot: ColorRect
var _display_name_label: Label
var _username_label: Label
var _custom_status_label: Label
var _bio_section: VBoxContainer
var _bio_label: RichTextLabel
var _roles_section: VBoxContainer
var _roles_flow: HFlowContainer
var _member_since_label: Label
var _badges_flow: HFlowContainer
var _activities_label: Label
var _device_status_hbox: HBoxContainer
var _message_btn: Button

func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.114, 0.118, 0.129)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 12.0
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Banner area
	_banner_rect = ColorRect.new()
	_banner_rect.custom_minimum_size = Vector2(300, 60)
	_banner_rect.color = Color(0.188, 0.196, 0.212)
	vbox.add_child(_banner_rect)

	# Content area with padding
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	content_margin.add_theme_constant_override("margin_top", 0)
	content_margin.add_theme_constant_override("margin_bottom", 0)
	content_margin.add_child(content)
	vbox.add_child(content_margin)

	# Avatar + status row (overlapping banner)
	var avatar_row := HBoxContainer.new()
	avatar_row.add_theme_constant_override("separation", 6)
	content.add_child(avatar_row)

	var AvatarScene: PackedScene = preload(
		"res://scenes/common/avatar.tscn"
	)
	_avatar = AvatarScene.instantiate()
	_avatar.avatar_size = 64
	_avatar.show_letter = true
	_avatar.letter_font_size = 24
	_avatar.custom_minimum_size = Vector2(64, 64)
	avatar_row.add_child(_avatar)

	_status_dot = ColorRect.new()
	_status_dot.custom_minimum_size = Vector2(12, 12)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_END
	avatar_row.add_child(_status_dot)

	# Display name
	_display_name_label = Label.new()
	_display_name_label.add_theme_font_size_override("font_size", 18)
	content.add_child(_display_name_label)

	# Username
	_username_label = Label.new()
	_username_label.add_theme_font_size_override("font_size", 13)
	_username_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	content.add_child(_username_label)

	# Custom status
	_custom_status_label = Label.new()
	_custom_status_label.add_theme_font_size_override("font_size", 13)
	_custom_status_label.add_theme_color_override(
		"font_color", Color(0.75, 0.75, 0.75)
	)
	_custom_status_label.visible = false
	content.add_child(_custom_status_label)

	# Separator
	var sep := HSeparator.new()
	content.add_child(sep)

	# Activities
	_activities_label = Label.new()
	_activities_label.add_theme_font_size_override("font_size", 12)
	_activities_label.add_theme_color_override(
		"font_color", Color(0.75, 0.75, 0.75)
	)
	_activities_label.visible = false
	_activities_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	content.add_child(_activities_label)

	# Device status
	_device_status_hbox = HBoxContainer.new()
	_device_status_hbox.add_theme_constant_override("separation", 8)
	_device_status_hbox.visible = false
	content.add_child(_device_status_hbox)

	# About Me section
	_bio_section = VBoxContainer.new()
	_bio_section.add_theme_constant_override("separation", 4)
	_bio_section.visible = false
	content.add_child(_bio_section)

	var bio_header := Label.new()
	bio_header.text = "ABOUT ME"
	bio_header.add_theme_font_size_override("font_size", 11)
	bio_header.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_bio_section.add_child(bio_header)

	_bio_label = RichTextLabel.new()
	_bio_label.bbcode_enabled = true
	_bio_label.fit_content = true
	_bio_label.scroll_active = false
	_bio_label.custom_minimum_size = Vector2(0, 20)
	_bio_label.add_theme_font_size_override("normal_font_size", 13)
	_bio_section.add_child(_bio_label)

	# Roles section
	_roles_section = VBoxContainer.new()
	_roles_section.add_theme_constant_override("separation", 4)
	_roles_section.visible = false
	content.add_child(_roles_section)

	var roles_header := Label.new()
	roles_header.text = "ROLES"
	roles_header.add_theme_font_size_override("font_size", 11)
	roles_header.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_roles_section.add_child(roles_header)

	_roles_flow = HFlowContainer.new()
	_roles_flow.add_theme_constant_override("h_separation", 4)
	_roles_flow.add_theme_constant_override("v_separation", 4)
	_roles_section.add_child(_roles_flow)

	# Badges
	_badges_flow = HFlowContainer.new()
	_badges_flow.add_theme_constant_override("h_separation", 4)
	_badges_flow.visible = false
	content.add_child(_badges_flow)

	# Member since
	_member_since_label = Label.new()
	_member_since_label.add_theme_font_size_override("font_size", 11)
	_member_since_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_member_since_label.visible = false
	content.add_child(_member_since_label)

	# Message button
	_message_btn = Button.new()
	_message_btn.text = "Message"
	_message_btn.pressed.connect(_on_message_pressed)
	_message_btn.visible = false
	content.add_child(_message_btn)

func setup(user_data: Dictionary, guild_id: String = "") -> void:
	_user_data = user_data
	_guild_id = guild_id

	var dn: String = user_data.get("display_name", "Unknown")
	_display_name_label.text = dn
	_username_label.text = user_data.get("username", "")

	# Avatar
	_avatar.set_avatar_color(
		user_data.get("color", Color(0.345, 0.396, 0.949))
	)
	if dn.length() > 0:
		_avatar.set_letter(dn[0].to_upper())
	var avatar_url = user_data.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		_avatar.set_avatar_url(avatar_url)

	# Status dot
	var status: int = user_data.get(
		"status", ClientModels.UserStatus.OFFLINE
	)
	_status_dot.color = ClientModels.status_color(status)

	# Banner / accent color
	var accent: int = user_data.get("accent_color", 0)
	if accent > 0:
		_banner_rect.color = Color.hex(accent)

	# Bio
	var bio: String = user_data.get("bio", "")
	if not bio.is_empty():
		_bio_section.visible = true
		_bio_label.text = ClientModels.markdown_to_bbcode(bio)

	# Activities
	var activities: Array = user_data.get("activities", [])
	if activities.size() > 0:
		var activity_texts: Array = []
		for act in activities:
			if act is Dictionary:
				var atype: String = act.get("type", "playing")
				var aname: String = act.get("name", "")
				var prefix: String = _activity_prefix(atype)
				if not aname.is_empty():
					activity_texts.append(prefix + aname)
		if activity_texts.size() > 0:
			_activities_label.text = "\n".join(activity_texts)
			_activities_label.visible = true

	# Per-device status
	var client_status: Dictionary = user_data.get("client_status", {})
	if client_status.size() > 0:
		_device_status_hbox.visible = true
		for device in ["desktop", "mobile", "web"]:
			if client_status.has(device):
				var dev_label := Label.new()
				var dev_status: int = ClientModels._status_string_to_enum(
					str(client_status[device])
				)
				dev_label.text = device.capitalize()
				dev_label.add_theme_font_size_override("font_size", 11)
				dev_label.add_theme_color_override(
					"font_color", ClientModels.status_color(dev_status)
				)
				_device_status_hbox.add_child(dev_label)

	# Roles (guild context)
	if not guild_id.is_empty():
		var user_id: String = user_data.get("id", "")
		var member_roles: Array = []
		for member in Client.get_members_for_guild(guild_id):
			if member.get("id", "") == user_id:
				member_roles = member.get("roles", [])
				break
		var all_roles: Array = Client.get_roles_for_guild(guild_id)
		var displayed_roles: Array = []
		for role in all_roles:
			if role.get("id", "") in member_roles and role.get("position", 0) != 0:
				displayed_roles.append(role)
		if displayed_roles.size() > 0:
			_roles_section.visible = true
			for role in displayed_roles:
				var pill := Label.new()
				pill.text = role.get("name", "")
				pill.add_theme_font_size_override("font_size", 12)
				var pill_style := StyleBoxFlat.new()
				pill_style.bg_color = Color(0.22, 0.23, 0.25)
				pill_style.corner_radius_top_left = 4
				pill_style.corner_radius_top_right = 4
				pill_style.corner_radius_bottom_left = 4
				pill_style.corner_radius_bottom_right = 4
				pill_style.content_margin_left = 6.0
				pill_style.content_margin_right = 6.0
				pill_style.content_margin_top = 2.0
				pill_style.content_margin_bottom = 2.0
				pill.add_theme_stylebox_override("normal", pill_style)
				_roles_flow.add_child(pill)

	# Badges
	var flags: int = user_data.get("public_flags", 0)
	var badges: Array = ClientModels.get_user_badges(flags)
	if badges.size() > 0:
		_badges_flow.visible = true
		for badge_name in badges:
			var badge_label := Label.new()
			badge_label.text = badge_name
			badge_label.add_theme_font_size_override("font_size", 11)
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(0.275, 0.29, 0.318)
			bs.corner_radius_top_left = 3
			bs.corner_radius_top_right = 3
			bs.corner_radius_bottom_left = 3
			bs.corner_radius_bottom_right = 3
			bs.content_margin_left = 4.0
			bs.content_margin_right = 4.0
			bs.content_margin_top = 1.0
			bs.content_margin_bottom = 1.0
			badge_label.add_theme_stylebox_override("normal", bs)
			_badges_flow.add_child(badge_label)

	# Member since
	var created_at: String = user_data.get("created_at", "")
	if not created_at.is_empty():
		_member_since_label.text = "Member since " + _format_date(created_at)
		_member_since_label.visible = true

	# Message button (hidden for self or unknown user)
	var my_id: String = Client.current_user.get("id", "")
	var target_id: String = user_data.get("id", "")
	if not my_id.is_empty() and not target_id.is_empty() and target_id != my_id:
		_message_btn.visible = true
	else:
		_message_btn.visible = false

func _activity_prefix(type: String) -> String:
	return _ACTIVITY_PREFIXES.get(type, "")

func _format_date(iso: String) -> String:
	var t_idx := iso.find("T")
	if t_idx != -1:
		return iso.substr(0, t_idx)
	return iso

func _on_message_pressed() -> void:
	var user_id: String = _user_data.get("id", "")
	if not user_id.is_empty():
		Client.create_dm(user_id)
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
	elif event is InputEventMouseButton and event.pressed:
		# Close on click outside
		var local := get_local_mouse_position()
		if not Rect2(Vector2.ZERO, size).has_point(local):
			queue_free()
