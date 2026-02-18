extends HBoxContainer

signal add_server_pressed()

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $IconButton

func _ready() -> void:
	icon_button.pressed.connect(_on_pressed)
	icon_button.tooltip_text = "Add a Server"
	# Style the button as a circle
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.212, 0.224, 0.247)
	style.corner_radius_top_left = 24
	style.corner_radius_top_right = 24
	style.corner_radius_bottom_left = 24
	style.corner_radius_bottom_right = 24
	icon_button.add_theme_stylebox_override("normal", style)
	var hover_style := style.duplicate()
	hover_style.bg_color = Color(0.176, 0.557, 0.384)
	icon_button.add_theme_stylebox_override("hover", hover_style)

func _on_pressed() -> void:
	add_server_pressed.emit()
