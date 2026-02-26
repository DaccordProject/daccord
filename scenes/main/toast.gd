extends PanelContainer

var _is_error: bool = false

@onready var label: Label = $Label


func setup(text: String, is_error: bool = false) -> void:
	_is_error = is_error
	if label:
		_apply(text)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	anchor_bottom = 1.0
	anchor_top = 1.0
	offset_top = -60.0
	offset_bottom = -20.0
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()
	style.bg_color = (
		Color(0.28, 0.12, 0.12, 0.95)
		if _is_error
		else Color(0.18, 0.19, 0.21, 0.95)
	)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", style)
	if label and not label.text.is_empty():
		_start_dismiss()


func _apply(text: String) -> void:
	label.text = text
	var text_color := Color(0.92, 0.92, 0.92)
	if _is_error:
		text_color = Color(1.0, 0.86, 0.86)
	label.add_theme_color_override("font_color", text_color)
	if is_inside_tree():
		_start_dismiss()


func _start_dismiss() -> void:
	var tween := create_tween()
	tween.tween_interval(4.0)
	if Config.get_reduced_motion():
		tween.tween_callback(queue_free)
	else:
		tween.tween_property(self, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)
