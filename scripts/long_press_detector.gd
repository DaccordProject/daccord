class_name LongPressDetector
extends RefCounted

const LONG_PRESS_DURATION := 0.5
const DRAG_THRESHOLD := 10.0

var _control: Control
var _callback: Callable
var _timer: Timer
var _start_pos: Vector2
var _is_pressed: bool = false

func _init(control: Control, callback: Callable) -> void:
	_control = control
	_callback = callback
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = LONG_PRESS_DURATION
	_timer.timeout.connect(_on_timer_timeout)
	_control.add_child(_timer)
	_control.gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_pressed = true
			_start_pos = event.position
			_timer.start()
		else:
			_cancel()
	elif event is InputEventScreenDrag:
		if _is_pressed and event.position.distance_to(_start_pos) > DRAG_THRESHOLD:
			_cancel()

func _cancel() -> void:
	_is_pressed = false
	_timer.stop()

func _on_timer_timeout() -> void:
	if _is_pressed:
		_is_pressed = false
		_callback.call(Vector2i(int(_start_pos.x), int(_start_pos.y)))
