extends Control

## Draggable handle placed before a side panel in an HBoxContainer.
## Resizes the target panel horizontally on drag.

var _target: Control
var _min_width: float
var _max_width: float
var _max_ratio: float
var _default_width: float

var _dragging: bool = false
var _drag_start_x: float = 0.0
var _drag_start_width: float = 0.0
var _hovered: bool = false

const HANDLE_WIDTH := 6.0
const DOUBLE_CLICK_MS := 400
var _last_click_time: int = 0


func _init(
	target: Control, min_w: float, max_w: float,
	default_w: float, max_ratio: float = 0.0,
) -> void:
	_target = target
	_min_width = min_w
	_max_width = max_w
	_max_ratio = max_ratio
	_default_width = default_w
	custom_minimum_size.x = HANDLE_WIDTH
	size_flags_horizontal = 0
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_default_cursor_shape = CURSOR_HSIZE
	mouse_filter = MOUSE_FILTER_STOP
	set_process_input(false)
	# Track target visibility
	if _target.is_node_ready():
		visible = _target.visible
	_target.visibility_changed.connect(_on_target_visibility_changed)


func _on_target_visibility_changed() -> void:
	visible = _target.visible


func _draw() -> void:
	if _hovered or _dragging:
		var center_x: float = size.x / 2.0
		draw_line(
			Vector2(center_x, 4.0),
			Vector2(center_x, size.y - 4.0),
			Color(0.45, 0.47, 0.50, 0.8), 2.0,
		)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Double-click detection
			var now: int = Time.get_ticks_msec()
			if now - _last_click_time < DOUBLE_CLICK_MS:
				_reset_to_default()
				_last_click_time = 0
				return
			_last_click_time = now
			_dragging = true
			_drag_start_x = event.global_position.x
			_drag_start_width = _target.size.x
			set_process_input(true)
			queue_redraw()
		else:
			_stop_drag()


func _input(event: InputEvent) -> void:
	if not _dragging:
		set_process_input(false)
		return
	if event is InputEventMouseMotion:
		var delta: float = event.global_position.x - _drag_start_x
		var effective_max: float = _max_width
		if _max_ratio > 0.0 and is_inside_tree():
			effective_max = get_parent().size.x * _max_ratio
		if effective_max <= 0.0:
			effective_max = 99999.0
		effective_max = maxf(effective_max, _min_width)
		# Panel is to the right of the handle, so dragging left = wider
		var new_width: float = clampf(
			_drag_start_width - delta, _min_width, effective_max,
		)
		_target.custom_minimum_size.x = new_width
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_stop_drag()


func _stop_drag() -> void:
	_dragging = false
	set_process_input(false)
	queue_redraw()


func _reset_to_default() -> void:
	_target.custom_minimum_size.x = _default_width
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
