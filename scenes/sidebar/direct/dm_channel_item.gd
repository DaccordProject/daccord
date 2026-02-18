extends Button

signal dm_pressed(dm_id: String)
signal dm_closed(dm_id: String)

var dm_id: String = ""

@onready var avatar: ColorRect = $HBox/Avatar
@onready var username_label: Label = $HBox/Info/Username
@onready var last_message_label: Label = $HBox/Info/LastMessage
@onready var unread_dot: ColorRect = $HBox/UnreadDot
@onready var close_btn: Button = $HBox/CloseBtn

func _ready() -> void:
	pressed.connect(func(): dm_pressed.emit(dm_id))
	last_message_label.add_theme_font_size_override("font_size", 12)
	last_message_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	close_btn.visible = false
	close_btn.pressed.connect(_on_close_pressed)
	mouse_entered.connect(func(): close_btn.visible = true)
	mouse_exited.connect(func(): close_btn.visible = false)

func setup(data: Dictionary) -> void:
	dm_id = data.get("id", "")
	var user: Dictionary = data.get("user", {})
	username_label.text = user.get("display_name", "Unknown")
	last_message_label.text = data.get("last_message", "")
	last_message_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	avatar.set_avatar_color(user.get("color", Color(0.345, 0.396, 0.949)))
	unread_dot.visible = data.get("unread", false)

func _on_close_pressed() -> void:
	dm_closed.emit(dm_id)

func set_active(active: bool) -> void:
	if active:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.24, 0.25, 0.27)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		add_theme_stylebox_override("normal", style)
		username_label.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		remove_theme_stylebox_override("normal")
		username_label.remove_theme_color_override("font_color")
