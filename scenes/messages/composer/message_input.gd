extends TextEdit


func _ready() -> void:
	var empty_style := StyleBoxEmpty.new()
	empty_style.content_margin_top = 10
	empty_style.content_margin_bottom = 10
	add_theme_stylebox_override("normal", empty_style)
	add_theme_stylebox_override("focus", empty_style)
