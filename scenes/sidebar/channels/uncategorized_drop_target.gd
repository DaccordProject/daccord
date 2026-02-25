extends Control

signal channel_dropped(channel_data: Dictionary)

var space_id: String = ""
var _drop_hovered: bool = false

func setup(new_space_id: String) -> void:
	space_id = new_space_id

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "channel":
		_clear_drop_indicator()
		return false
	var ch_data: Dictionary = data.get("channel_data", {})
	if ch_data.get("space_id", "") != space_id:
		_clear_drop_indicator()
		return false
	_drop_hovered = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_indicator()
	if not data is Dictionary:
		return
	var ch_data: Dictionary = data.get("channel_data", {})
	if ch_data.is_empty():
		return
	channel_dropped.emit(ch_data)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_indicator()

func _clear_drop_indicator() -> void:
	if _drop_hovered:
		_drop_hovered = false
		queue_redraw()

func _draw() -> void:
	if not _drop_hovered:
		return
	var line_color := Color(0.34, 0.52, 0.89)
	var mid_y: float = size.y / 2.0
	draw_line(Vector2(0, mid_y), Vector2(size.x, mid_y), line_color, 2.0)
