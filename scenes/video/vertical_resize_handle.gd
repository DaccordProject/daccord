extends Control

## Draggable handle between rows in a VBoxContainer.
## Resizes the target control's height on vertical drag.

const HANDLE_HEIGHT := 6.0
const DOUBLE_CLICK_MS := 400

var _target: Control
var _min_height: float
var _max_ratio: float
var _default_height: float

var _dragging: bool = false
var _drag_start_y: float = 0.0
var _drag_start_height: float = 0.0
var _hovered: bool = false
var _last_click_time: int = 0


func _init(
	target: Control, min_h: float,
	default_h: float, max_ratio: float = 0.7,
) -> void:
	_target = target
	_min_height = min_h
	_max_ratio = max_ratio
	_default_height = default_h
	custom_minimum_size.y = HANDLE_HEIGHT
	size_flags_vertical = 0
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_VSIZE
	mouse_filter = MOUSE_FILTER_STOP
	set_process_input(false)
	add_to_group("themed")


func _apply_theme() -> void:
	queue_redraw()


func _draw() -> void:
	var center_y: float = size.y / 2.0
	if _hovered or _dragging:
		draw_line(
			Vector2(4.0, center_y),
			Vector2(size.x - 4.0, center_y),
			ThemeManager.get_color("icon_default"), 2.0,
		)
	else:
		# Subtle resting indicator: three small dots so users can
		# discover the resize handle without hovering the 6px strip.
		var color: Color = ThemeManager.get_color("icon_default")
		color.a = 0.35
		var cx: float = size.x / 2.0
		for offset in [-8.0, 0.0, 8.0]:
			draw_circle(Vector2(cx + offset, center_y), 1.5, color)


func _gui_input(event: InputEvent) -> void:
	if not (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
	):
		return
	if event.pressed:
		var now: int = Time.get_ticks_msec()
		if now - _last_click_time < DOUBLE_CLICK_MS:
			_reset_to_default()
			_last_click_time = 0
			return
		_last_click_time = now
		_dragging = true
		_drag_start_y = event.global_position.y
		_drag_start_height = _target.size.y
		set_process_input(true)
		queue_redraw()
	else:
		_stop_drag()


func _input(event: InputEvent) -> void:
	if not _dragging:
		set_process_input(false)
		return
	if event is InputEventMouseMotion:
		var delta: float = (
			event.global_position.y - _drag_start_y
		)
		var effective_max: float = 99999.0
		if _max_ratio > 0.0 and is_inside_tree():
			effective_max = get_parent().size.y * _max_ratio
		effective_max = maxf(effective_max, _min_height)
		var new_height: float = clampf(
			_drag_start_height + delta,
			_min_height, effective_max,
		)
		_target.custom_minimum_size.y = new_height
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_LEFT
		and not event.pressed
	):
		_stop_drag()


func _stop_drag() -> void:
	_dragging = false
	set_process_input(false)
	queue_redraw()


func _reset_to_default() -> void:
	_target.custom_minimum_size.y = _default_height
	_dragging = false
	set_process_input(false)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hovered = true
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hovered = false
		queue_redraw()
