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
@onready var action_box: HBoxContainer = $ActionBox

func _ready() -> void:
	add_to_group("themed")
	status_label.add_theme_font_size_override("font_size", 12)

func setup(data: Dictionary) -> void:
	_rel_data = data
	var user: Dictionary = data.get("user", {})
	var rel_type: int = data.get("type", 0)
	var dname: String = user.get("display_name", "Unknown")

	name_label.text = dname
	tooltip_text = dname

	# Avatar
	avatar.set_avatar_color(user.get("color", ThemeManager.get_color("accent")))
	if dname.length() > 0:
		avatar.set_letter(dname[0].to_upper())
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		avatar.set_avatar_url(avatar_url)

	# Status line
	match rel_type:
		FRIEND:
			var status: int = user.get("status", ClientModels.UserStatus.OFFLINE)
			status_label.text = ClientModels.status_label(status)
			status_label.add_theme_color_override(
				"font_color", ClientModels.status_color(status)
			)
		BLOCKED:
			status_label.text = "Blocked"
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

	# Rebuild action buttons
	for child in action_box.get_children():
		child.queue_free()

	var user_id: String = user.get("id", "")
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

func _add_action_btn(label: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = label
	btn.flat = true
	btn.custom_minimum_size = Vector2(0, 28)
	btn.pressed.connect(callback)
	action_box.add_child(btn)
