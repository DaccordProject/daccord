extends Control

@onready var label: Label = $Label

func _ready() -> void:
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	label.uppercase = true

func setup(data: Dictionary) -> void:
	label.text = data.get("label", "")
