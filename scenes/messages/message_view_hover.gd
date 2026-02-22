extends RefCounted
## Action bar hover state machine for MessageView.
## Manages hover detection, action bar positioning, and hide/show logic.

var _view: Control # parent MessageView
var _action_bar: PanelContainer
var _hovered_message: Control = null
var _hover_timer: Timer
var _hover_hide_pending: bool = false


func _init(view: Control, action_bar: PanelContainer) -> void:
	_view = view
	_action_bar = action_bar
	# Hover debounce timer
	_hover_timer = Timer.new()
	_hover_timer.wait_time = 0.1
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	view.add_child(_hover_timer)


func process() -> void:
	if not _action_bar.visible or _hovered_message == null:
		return
	if not is_instance_valid(_hovered_message):
		hide_action_bar()
		return
	position_action_bar()


func on_msg_hovered(msg_node: Control) -> void:
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		return
	# Suppress bar when message is being edited
	var mc = msg_node.get("message_content")
	if mc and mc.is_editing():
		return

	_hover_timer.stop()
	_hover_hide_pending = false

	# Clear previous hover highlight
	if _hovered_message and is_instance_valid(_hovered_message) \
			and _hovered_message != msg_node:
		if _hovered_message.has_method("set_hovered"):
			_hovered_message.set_hovered(false)

	_hovered_message = msg_node
	if msg_node.has_method("set_hovered"):
		msg_node.set_hovered(true)

	var msg_data: Dictionary = msg_node.get("_message_data")
	if msg_data == null:
		msg_data = {}
	_action_bar.show_for_message(msg_node, msg_data)
	position_action_bar()


func on_msg_unhovered(_msg_node: Control) -> void:
	_hover_hide_pending = true
	_hover_timer.start()


func on_action_bar_unhovered() -> void:
	_hover_hide_pending = true
	_hover_timer.start()


func _on_hover_timer_timeout() -> void:
	if not _hover_hide_pending:
		return
	if _action_bar.is_bar_hovered():
		_hover_hide_pending = false
		return
	hide_action_bar()


func hide_action_bar() -> void:
	_hover_timer.stop()
	_hover_hide_pending = false
	_action_bar.hide_bar()
	if _hovered_message and is_instance_valid(_hovered_message):
		if _hovered_message.has_method("set_hovered"):
			_hovered_message.set_hovered(false)
	_hovered_message = null


func position_action_bar() -> void:
	if _hovered_message == null or not is_instance_valid(_hovered_message):
		return

	var msg_rect: Rect2 = _hovered_message.get_global_rect()
	var scroll_container: ScrollContainer = _view.get("scroll_container")
	var scroll_rect: Rect2 = scroll_container.get_global_rect()

	# Hide if message scrolled out of view
	var msg_bottom := msg_rect.position.y + msg_rect.size.y
	var scroll_bottom := scroll_rect.position.y + scroll_rect.size.y
	if msg_bottom < scroll_rect.position.y \
			or msg_rect.position.y > scroll_bottom:
		_action_bar.visible = false
		return
	_action_bar.visible = true

	var bar_size := _action_bar.size
	# Position at top-right of message, offset up by half bar height
	var x := msg_rect.position.x + msg_rect.size.x - bar_size.x - 8
	var y := msg_rect.position.y - bar_size.y * 0.5
	# Clamp within scroll container bounds
	y = clampf(
		y, scroll_rect.position.y,
		scroll_rect.position.y + scroll_rect.size.y - bar_size.y,
	)
	_action_bar.position = Vector2(x, y)


func on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	if mode == AppState.LayoutMode.COMPACT:
		hide_action_bar()
