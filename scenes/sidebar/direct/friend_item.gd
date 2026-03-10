extends HBoxContainer

signal message_pressed(user_id: String)
signal remove_pressed(user_id: String)
signal block_pressed(user_id: String)
signal accept_pressed(user_id: String)
signal decline_pressed(user_id: String)
signal cancel_pressed(user_id: String)
signal unblock_pressed(user_id: String)

# RelationshipType enum (mirrors AccordRelationship)
const FRIEND := 1
const BLOCKED := 2
const PENDING_INCOMING := 3
const PENDING_OUTGOING := 4

var _rel_data: Dictionary = {}

@onready var avatar: ColorRect = $Avatar
@onready var info_box: VBoxContainer = $InfoBox
@onready var name_label: Label = $InfoBox/NameLabel
@onready var status_label: Label = $InfoBox/StatusLabel
@onready var activity_label: Label = $InfoBox/ActivityLabel
@onready var action_box: HBoxContainer = $ActionBox

func _ready() -> void:
	add_to_group("themed")
	status_label.add_theme_font_size_override("font_size", 12)
	activity_label.add_theme_font_size_override("font_size", 11)
	activity_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	gui_input.connect(_on_gui_input)

func setup(data: Dictionary) -> void:
	_rel_data = data
	var user: Dictionary = data.get("user", {})
	var rel_type: int = data.get("type", 0)
	var dname: String = user.get("display_name", "Unknown")

	name_label.text = dname
	tooltip_text = dname

	# Avatar
	avatar.setup_from_dict(user)

	# Status line
	var since_str: String = data.get("since", "")
	match rel_type:
		FRIEND:
			var status: int = user.get("status", ClientModels.UserStatus.OFFLINE)
			var status_text: String = ClientModels.status_label(status)
			var since_formatted: String = _format_since(since_str)
			if not since_formatted.is_empty():
				status_text += " · Friends since " + since_formatted
			status_label.text = status_text
			status_label.add_theme_color_override(
				"font_color", ClientModels.status_color(status)
			)
		BLOCKED:
			var blocked_text := "Blocked"
			var since_formatted: String = _format_since(since_str)
			if not since_formatted.is_empty():
				blocked_text += " · Since " + since_formatted
			status_label.text = blocked_text
			status_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("text_muted")
			)
		PENDING_INCOMING:
			status_label.text = "Incoming Friend Request"
			status_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("text_muted")
			)
		PENDING_OUTGOING:
			status_label.text = "Outgoing Friend Request"
			status_label.add_theme_color_override(
				"font_color", ThemeManager.get_color("text_muted")
			)

	# Activity line (FRIEND only)
	activity_label.visible = false
	if rel_type == FRIEND:
		var activities: Array = user.get("activities", [])
		if activities.size() > 0:
			var act_text: String = ClientModels.format_activity(activities[0])
			if not act_text.is_empty():
				activity_label.text = act_text
				activity_label.visible = true

	# Lazy-load mutual friend count for friends
	var user_id: String = user.get("id", "")
	if rel_type == FRIEND and not user_id.is_empty():
		_fetch_mutual_count(user_id)

	# Rebuild action buttons
	for child in action_box.get_children():
		child.queue_free()
	match rel_type:
		FRIEND:
			_add_action_btn("Message", func(): message_pressed.emit(user_id))
			_add_action_btn("Remove", func(): remove_pressed.emit(user_id))
			_add_action_btn("Block", func(): block_pressed.emit(user_id))
		BLOCKED:
			_add_action_btn("Unblock", func(): unblock_pressed.emit(user_id))
		PENDING_INCOMING:
			_add_action_btn("Accept", func(): accept_pressed.emit(user_id))
			_add_action_btn("Decline", func(): decline_pressed.emit(user_id))
		PENDING_OUTGOING:
			_add_action_btn("Cancel", func(): cancel_pressed.emit(user_id))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var user_id: String = _rel_data.get("user", {}).get("id", "")
		if not user_id.is_empty():
			var pos := get_global_mouse_position()
			AppState.profile_card_requested.emit(user_id, pos)

func _fetch_mutual_count(user_id: String) -> void:
	var mutuals: Array = await Client.relationships.get_mutual_friends(user_id)
	if not is_instance_valid(self):
		return
	if mutuals.size() > 0:
		var suffix := " · %d mutual friend" % mutuals.size()
		if mutuals.size() > 1:
			suffix += "s"
		status_label.text += suffix

func _disable_all_actions() -> void:
	for child in action_box.get_children():
		if child is Button:
			child.disabled = true

static func _format_since(iso: String) -> String:
	if iso.is_empty():
		return ""
	var t_idx := iso.find("T")
	var date_part: String = iso.substr(0, t_idx) if t_idx != -1 else iso
	var parts: PackedStringArray = date_part.split("-")
	if parts.size() < 3:
		return ""
	var month: int = parts[1].to_int()
	var year: int = parts[0].to_int()
	if month < 1 or month > 12 or year < 2000:
		return ""
	const MONTH_NAMES: Array = [
		"Jan", "Feb", "Mar", "Apr", "May", "Jun",
		"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
	]
	return "%s %d" % [MONTH_NAMES[month - 1], year]

func _add_action_btn(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 28)
	btn.pressed.connect(func():
		_disable_all_actions()
		callback.call()
	)
	action_box.add_child(btn)
