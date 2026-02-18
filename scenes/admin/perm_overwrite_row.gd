extends HBoxContainer

signal state_changed(perm: String, new_state: int)

## Must match channel_permissions_dialog.gd OverwriteState
const INHERIT := 0
const ALLOW := 1
const DENY := 2

var _perm: String = ""

@onready var _label: Label = $PermLabel
@onready var _allow_btn: Button = $AllowButton
@onready var _inherit_btn: Button = $InheritButton
@onready var _deny_btn: Button = $DenyButton

func _ready() -> void:
	_allow_btn.text = "\u2713"
	_inherit_btn.text = "/"
	_deny_btn.text = "\u2717"
	_allow_btn.pressed.connect(func(): state_changed.emit(_perm, ALLOW))
	_inherit_btn.pressed.connect(func(): state_changed.emit(_perm, INHERIT))
	_deny_btn.pressed.connect(func(): state_changed.emit(_perm, DENY))

func setup(perm: String, state: int) -> void:
	_perm = perm
	_label.text = perm.replace("_", " ").capitalize()
	update_state(state)

func update_state(state: int) -> void:
	_allow_btn.add_theme_color_override("font_color",
		Color(0.231, 0.647, 0.365) if state == ALLOW else Color(0.4, 0.4, 0.4))
	_inherit_btn.add_theme_color_override("font_color",
		Color(0.58, 0.608, 0.643) if state == INHERIT else Color(0.4, 0.4, 0.4))
	_deny_btn.add_theme_color_override("font_color",
		Color(0.929, 0.259, 0.271) if state == DENY else Color(0.4, 0.4, 0.4))
