extends PanelContainer

var _is_error: bool = false
var _pending_text: String = ""

@onready var label: Label = $Label


func setup(text: String, is_error: bool = false) -> void:
	_is_error = is_error
	_pending_text = text
	if label:
		_apply(text)


func _ready() -> void:
	visible = false
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
	if not _pending_text.is_empty():
		_apply(_pending_text)


func _apply(text: String) -> void:
	label.text = text
	var text_color := Color(0.92, 0.92, 0.92)
	if _is_error:
		text_color = Color(1.0, 0.86, 0.86)
	label.add_theme_color_override("font_color", text_color)
	if is_inside_tree():
		call_deferred("_show_and_dismiss")


func _show_and_dismiss() -> void:
	var parent_ctrl: Control = get_parent_control()
	if not parent_ctrl:
		queue_free()
		return
	var my_size: Vector2 = get_combined_minimum_size()
	size = my_size
	position = Vector2(
		(parent_ctrl.size.x - my_size.x) / 2.0,
		parent_ctrl.size.y - my_size.y - 20.0
	)
	visible = true
	_start_dismiss()


func _start_dismiss() -> void:
	var tween := create_tween()
	tween.tween_interval(4.0)
	if Config.get_reduced_motion():
		tween.tween_callback(queue_free)
	else:
		tween.tween_property(self, "modulate:a", 0.0, 1.0)
		tween.tween_callback(queue_free)
