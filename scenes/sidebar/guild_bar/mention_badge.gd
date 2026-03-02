extends PanelContainer

var count: int = 0:
	set(value):
		count = value
		if count_label:
			count_label.text = str(value)
		visible = value > 0

@onready var count_label: Label = $Count

func _ready() -> void:
	add_to_group("themed")
	count_label.add_theme_font_size_override("font_size", 11)
	_apply_theme()
	visible = count > 0

func _apply_theme() -> void:
	count_label.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
