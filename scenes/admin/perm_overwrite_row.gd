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
	tooltip_text = AccordPermission.description(perm)
	update_state(state)

func update_state(state: int) -> void:
	var dim := Color(ThemeManager.get_color("icon_default"), 0.3)
	_allow_btn.add_theme_color_override("font_color",
		ThemeManager.get_color("success") if state == ALLOW else dim)
	_inherit_btn.add_theme_color_override("font_color",
		ThemeManager.get_color("text_body") if state == INHERIT else dim)
	_deny_btn.add_theme_color_override("font_color",
		ThemeManager.get_color("error") if state == DENY else dim)
