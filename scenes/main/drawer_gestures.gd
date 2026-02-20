extends RefCounted

const EDGE_SWIPE_ZONE := 20.0
const SWIPE_THRESHOLD := 80.0
const SWIPE_DEAD_ZONE := 10.0
const VELOCITY_THRESHOLD := 400.0
const SNAP_PROGRESS := 0.5

var is_close_tracking: bool:
	get: return _close_swipe_tracking

var _edge_swipe_tracking := false
var _edge_swipe_start_x := 0.0
var _swipe_active := false
var _swipe_last_x := 0.0
var _swipe_velocity := 0.0
var _swipe_last_time := 0.0
var _close_swipe_tracking := false
var _close_swipe_start_x := 0.0

var _w: Control # main window reference


func _init(window: Control) -> void:
	_w = window


func handle_input(event: InputEvent) -> void:
	if not AppState.sidebar_drawer_open:
		_handle_open_swipe(event)
	else:
		_handle_close_swipe(event)


# --- Open Swipe ---

func _handle_open_swipe(event: InputEvent) -> void:
	# Touch events
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x <= EDGE_SWIPE_ZONE:
			_edge_swipe_tracking = true
			_edge_swipe_start_x = event.position.x
			_swipe_active = false
			_swipe_last_x = event.position.x
			_swipe_last_time = Time.get_ticks_msec() / 1000.0
			_swipe_velocity = 0.0
		elif not event.pressed:
			if _swipe_active:
				_finish_open_swipe()
			elif _edge_swipe_tracking:
				var disp: float = event.position.x - _edge_swipe_start_x
				if disp >= SWIPE_THRESHOLD:
					AppState.toggle_sidebar_drawer()
			_reset_open_swipe()
	elif event is InputEventScreenDrag and _edge_swipe_tracking:
		var disp: float = event.position.x - _edge_swipe_start_x
		if not _swipe_active and disp >= SWIPE_DEAD_ZONE:
			_swipe_active = true
			_begin_drawer_tracking()
		if _swipe_active:
			_update_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()

	# Mouse events (desktop testing)
	if event is InputEventMouseButton:
		if (event.pressed and event.button_index == MOUSE_BUTTON_LEFT
				and event.position.x <= EDGE_SWIPE_ZONE):
			_edge_swipe_tracking = true
			_edge_swipe_start_x = event.position.x
			_swipe_active = false
			_swipe_last_x = event.position.x
			_swipe_last_time = Time.get_ticks_msec() / 1000.0
			_swipe_velocity = 0.0
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _swipe_active:
				_finish_open_swipe()
			elif _edge_swipe_tracking:
				var disp: float = event.position.x - _edge_swipe_start_x
				if disp >= SWIPE_THRESHOLD:
					AppState.toggle_sidebar_drawer()
			_reset_open_swipe()
	elif event is InputEventMouseMotion and _edge_swipe_tracking:
		var disp: float = event.position.x - _edge_swipe_start_x
		if not _swipe_active and disp >= SWIPE_DEAD_ZONE:
			_swipe_active = true
			_begin_drawer_tracking()
		if _swipe_active:
			_update_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()


func _reset_open_swipe() -> void:
	_edge_swipe_tracking = false
	_swipe_active = false


func _begin_drawer_tracking() -> void:
	if _w._drawer_tween:
		_w._drawer_tween.kill()
	var dw: float = _w._get_drawer_width()
	_w.drawer_backdrop.visible = true
	_w.drawer_container.visible = true
	_w.sidebar.visible = true
	_w.sidebar.offset_right = dw
	_w.sidebar.position.x = -dw
	_w.drawer_backdrop.modulate.a = 0.0


func _update_drawer_position(pos_x: float) -> void:
	var dw: float = _w._get_drawer_width()
	var progress: float = clampf(
		(pos_x - _edge_swipe_start_x) / dw, 0.0, 1.0
	)
	_w.sidebar.position.x = -dw + (dw * progress)
	_w.drawer_backdrop.modulate.a = progress
	# Track velocity
	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _swipe_last_time
	if dt > 0.001:
		_swipe_velocity = (pos_x - _swipe_last_x) / dt
	_swipe_last_x = pos_x
	_swipe_last_time = now


func _finish_open_swipe() -> void:
	var dw: float = _w._get_drawer_width()
	var progress: float = clampf(
		(_w.sidebar.position.x + dw) / dw, 0.0, 1.0
	)
	if _should_snap_open(progress, _swipe_velocity):
		_snap_drawer_open(progress)
	else:
		_snap_drawer_closed(progress)


func _snap_drawer_open(progress: float) -> void:
	AppState.sidebar_drawer_open = true
	if Config.get_reduced_motion():
		_w.sidebar.position.x = 0.0
		_w.drawer_backdrop.modulate.a = 1.0
		return
	var duration: float = maxf(0.2 * (1.0 - progress), 0.05)
	if _w._drawer_tween:
		_w._drawer_tween.kill()
	_w._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer_tween.tween_property(
		_w.sidebar, "position:x", 0.0, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_w._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 1.0, duration
	)


func _snap_drawer_closed(progress: float) -> void:
	if Config.get_reduced_motion():
		_w._hide_drawer_nodes()
		return
	var dw: float = _w._get_drawer_width()
	var duration: float = maxf(0.2 * progress, 0.05)
	if _w._drawer_tween:
		_w._drawer_tween.kill()
	_w._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer_tween.tween_property(
		_w.sidebar, "position:x", -dw, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer_tween.chain().tween_callback(_w._hide_drawer_nodes)


# --- Close Swipe ---

func _handle_close_swipe(event: InputEvent) -> void:
	var dw: float = _w._get_drawer_width()

	# Touch events
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x > dw:
				_close_swipe_tracking = true
				_close_swipe_start_x = event.position.x
				_swipe_active = false
				_swipe_last_x = event.position.x
				_swipe_last_time = Time.get_ticks_msec() / 1000.0
				_swipe_velocity = 0.0
				_w.get_viewport().set_input_as_handled()
		elif not event.pressed:
			if _swipe_active:
				_finish_close_swipe()
			elif _close_swipe_tracking:
				AppState.close_sidebar_drawer()
			_reset_close_swipe()
	elif event is InputEventScreenDrag and _close_swipe_tracking:
		var disp: float = _close_swipe_start_x - event.position.x
		if not _swipe_active and disp >= SWIPE_DEAD_ZONE:
			_swipe_active = true
		if _swipe_active:
			_update_close_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()

	# Mouse events (desktop testing)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.x > dw:
				_close_swipe_tracking = true
				_close_swipe_start_x = event.position.x
				_swipe_active = false
				_swipe_last_x = event.position.x
				_swipe_last_time = Time.get_ticks_msec() / 1000.0
				_swipe_velocity = 0.0
				_w.get_viewport().set_input_as_handled()
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _swipe_active:
				_finish_close_swipe()
			elif _close_swipe_tracking:
				AppState.close_sidebar_drawer()
			_reset_close_swipe()
	elif event is InputEventMouseMotion and _close_swipe_tracking:
		var disp: float = _close_swipe_start_x - event.position.x
		if not _swipe_active and disp >= SWIPE_DEAD_ZONE:
			_swipe_active = true
		if _swipe_active:
			_update_close_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()


func _reset_close_swipe() -> void:
	_close_swipe_tracking = false
	_swipe_active = false


func _update_close_drawer_position(pos_x: float) -> void:
	var dw: float = _w._get_drawer_width()
	var close_progress: float = clampf(
		(_close_swipe_start_x - pos_x) / dw, 0.0, 1.0
	)
	_w.sidebar.position.x = -dw * close_progress
	_w.drawer_backdrop.modulate.a = 1.0 - close_progress
	# Track velocity
	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _swipe_last_time
	if dt > 0.001:
		_swipe_velocity = (pos_x - _swipe_last_x) / dt
	_swipe_last_x = pos_x
	_swipe_last_time = now


func _finish_close_swipe() -> void:
	var dw: float = _w._get_drawer_width()
	var close_progress: float = clampf(
		-_w.sidebar.position.x / dw, 0.0, 1.0
	)
	if _should_snap_open(1.0 - close_progress, _swipe_velocity):
		_snap_drawer_open(1.0 - close_progress)
	else:
		AppState.sidebar_drawer_open = false
		_snap_drawer_closed_from_close(close_progress)


func _snap_drawer_closed_from_close(close_progress: float) -> void:
	if Config.get_reduced_motion():
		_w._hide_drawer_nodes()
		return
	var dw: float = _w._get_drawer_width()
	var duration: float = maxf(0.2 * (1.0 - close_progress), 0.05)
	if _w._drawer_tween:
		_w._drawer_tween.kill()
	_w._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer_tween.tween_property(
		_w.sidebar, "position:x", -dw, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer_tween.chain().tween_callback(_w._hide_drawer_nodes)


func _should_snap_open(progress: float, velocity: float) -> bool:
	if absf(velocity) > VELOCITY_THRESHOLD:
		return velocity > 0.0
	return progress >= SNAP_PROGRESS
