extends HBoxContainer

signal move_requested(role: Dictionary, direction: int)
signal selected(role: Dictionary)

var _role_data: Dictionary = {}

@onready var _up_btn: Button = $UpButton
@onready var _down_btn: Button = $DownButton
@onready var _role_btn: Button = $RoleButton

func _ready() -> void:
	_up_btn.pressed.connect(func(): move_requested.emit(_role_data, -1))
	_down_btn.pressed.connect(func(): move_requested.emit(_role_data, 1))
	_role_btn.pressed.connect(func(): selected.emit(_role_data))

func setup(role: Dictionary, index: int, total: int) -> void:
	_role_data = role

	# Arrow characters
	_up_btn.text = "\u25b2"
	_down_btn.text = "\u25bc"

	var is_everyone: bool = role.get("position", 0) == 0
	_up_btn.disabled = is_everyone or index == 0
	_down_btn.disabled = is_everyone or index == total - 1

	var role_color: int = role.get("color", 0)
	var display_color := Color.WHITE
	if role_color > 0:
		display_color = Color.hex(role_color)

	_role_btn.text = role.get("name", "")
	_role_btn.add_theme_color_override("font_color", display_color)
