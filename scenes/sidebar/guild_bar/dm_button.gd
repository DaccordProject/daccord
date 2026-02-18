extends HBoxContainer

signal dm_pressed()

var is_active: bool = false

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $IconButton

func _ready() -> void:
	icon_button.pressed.connect(_on_pressed)
	icon_button.tooltip_text = "Direct Messages"
	# Style the button as a circle
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.212, 0.224, 0.247)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	icon_button.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.345, 0.396, 0.949)
	icon_button.add_theme_stylebox_override("hover", hover_style)

func set_active(active: bool) -> void:
	is_active = active
	if pill:
		pill.set_state_animated(pill.PillState.ACTIVE if active else pill.PillState.HIDDEN)

func _on_pressed() -> void:
	dm_pressed.emit()
