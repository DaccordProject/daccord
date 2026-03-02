extends Control

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("themed")
	label.add_theme_font_size_override("font_size", 11)
	_apply_theme()
	label.uppercase = true

func _apply_theme() -> void:
	label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))

func setup(data: Dictionary) -> void:
	label.text = data.get("label", "")
