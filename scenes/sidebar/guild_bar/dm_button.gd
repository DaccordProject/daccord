extends HBoxContainer

signal dm_pressed()

var is_active: bool = false
var _normal_style: StyleBoxFlat
var _hover_style: StyleBoxFlat

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $IconButton

func _ready() -> void:
	add_to_group("themed")
	icon_button.pressed.connect(_on_pressed)
	icon_button.tooltip_text = tr("Direct Messages")
	# Style the button as a circle
	_normal_style = StyleBoxFlat.new()
	_normal_style.corner_radius_top_left = 24
	_normal_style.corner_radius_top_right = 24
	_normal_style.corner_radius_bottom_left = 24
	_normal_style.corner_radius_bottom_right = 24
	icon_button.add_theme_stylebox_override("normal", _normal_style)
	_hover_style = _normal_style.duplicate()
	icon_button.add_theme_stylebox_override("hover", _hover_style)
	_apply_theme()

func _apply_theme() -> void:
	_normal_style.bg_color = ThemeManager.get_color("secondary_button")
	_hover_style.bg_color = ThemeManager.get_color("accent")

func set_active(active: bool) -> void:
	is_active = active
	if pill:
		pill.set_state_animated(pill.PillState.ACTIVE if active else pill.PillState.HIDDEN)

func _on_pressed() -> void:
	dm_pressed.emit()
