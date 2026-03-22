extends RefCounted

const EDGE_SWIPE_ZONE := 20.0
const SWIPE_THRESHOLD := 80.0
const SWIPE_DEAD_ZONE := 10.0
const VELOCITY_THRESHOLD := 400.0
const SNAP_PROGRESS := 0.5

var is_close_tracking: bool:
	get: return _close_swipe_tracking

var is_member_close_tracking: bool:
	get: return _member_close_swipe_tracking

var _edge_swipe_tracking := false
var _edge_swipe_start_x := 0.0
var _swipe_active := false
var _swipe_last_x := 0.0
var _swipe_velocity := 0.0
var _swipe_last_time := 0.0
var _close_swipe_tracking := false
var _close_swipe_start_x := 0.0
# Right-edge member drawer tracking
var _right_edge_tracking := false
var _right_edge_start_x := 0.0
var _right_swipe_active := false
var _member_close_swipe_tracking := false
var _member_close_start_x := 0.0
var _member_close_active := false
# Thread swipe-back tracking
var _thread_swipe_tracking := false
var _thread_swipe_start_x := 0.0
var _thread_swipe_active := false

var _w: Control # main window reference
var _cached_edge_zone: float = -1.0


func _init(window: Control) -> void:
	_w = window


func _get_edge_zone() -> float:
	if _cached_edge_zone > 0.0:
		return _cached_edge_zone
	var zone: float = EDGE_SWIPE_ZONE
	if OS.has_feature("mobile"):
		var screen: int = DisplayServer.window_get_current_screen(
			DisplayServer.MAIN_WINDOW_ID
		)
		var dpi: int = DisplayServer.screen_get_dpi(screen)
		if dpi > 160:
			var csf: float = _w.get_window().content_scale_factor
			if csf > 0.0:
				zone = EDGE_SWIPE_ZONE * clampf(
					float(dpi) / 160.0 / csf, 1.0, 2.0
				)
	_cached_edge_zone = zone
	return zone


func handle_input(event: InputEvent) -> void:
	# Thread swipe-back takes priority in COMPACT mode with thread visible
	if (AppState.thread_panel_visible
			and not AppState.sidebar_drawer_open
			and not AppState.member_drawer_open):
		if _handle_thread_swipe_back(event):
			return

	if AppState.member_drawer_open:
		_handle_member_close_swipe(event)
	elif AppState.sidebar_drawer_open:
		_handle_close_swipe(event)
	else:
		_handle_open_swipe(event)
		if not _edge_swipe_tracking:
			_handle_right_edge_swipe(event)


# --- Open Swipe (left edge → sidebar drawer) ---

func _handle_open_swipe(event: InputEvent) -> void:
	var edge_zone: float = _get_edge_zone()

	# Touch events
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x <= edge_zone:
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
				and event.position.x <= edge_zone):
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
	if _w._drawer._drawer_tween:
		_w._drawer._drawer_tween.kill()
	var dw: float = _w._drawer.get_drawer_width()
	_w.drawer_backdrop.visible = true
	_w.drawer_container.visible = true
	_w.sidebar.visible = true
	_w.sidebar.offset_right = dw
	_w.sidebar.position.x = -dw
	_w.drawer_backdrop.modulate.a = 0.0


func _update_drawer_position(pos_x: float) -> void:
	var dw: float = _w._drawer.get_drawer_width()
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
	var dw: float = _w._drawer.get_drawer_width()
	var progress: float = clampf(
		(_w.sidebar.position.x + dw) / dw, 0.0, 1.0
	)
	if _should_snap_open(progress, _swipe_velocity):
		_snap_drawer_open(progress)
	else:
		_snap_drawer_closed(progress)


func _snap_drawer_open(progress: float) -> void:
	AppState.sidebar_drawer_open = true
	AppState.nav_history.push(&"drawer")
	if Config.get_reduced_motion():
		_w.sidebar.position.x = 0.0
		_w.drawer_backdrop.modulate.a = 1.0
		return
	var duration: float = maxf(0.2 * (1.0 - progress), 0.05)
	if _w._drawer._drawer_tween:
		_w._drawer._drawer_tween.kill()
	_w._drawer._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer._drawer_tween.tween_property(
		_w.sidebar, "position:x", 0.0, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 1.0, duration
	)


func _snap_drawer_closed(progress: float) -> void:
	if Config.get_reduced_motion():
		_w._drawer.hide_drawer_nodes()
		return
	var dw: float = _w._drawer.get_drawer_width()
	var duration: float = maxf(0.2 * progress, 0.05)
	if _w._drawer._drawer_tween:
		_w._drawer._drawer_tween.kill()
	_w._drawer._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer._drawer_tween.tween_property(
		_w.sidebar, "position:x", -dw, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer._drawer_tween.chain().tween_callback(_w._hide_drawer_nodes)


# --- Close Swipe (sidebar drawer) ---

func _handle_close_swipe(event: InputEvent) -> void:
	var dw: float = _w._drawer.get_drawer_width()

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
	var dw: float = _w._drawer.get_drawer_width()
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
	var dw: float = _w._drawer.get_drawer_width()
	var close_progress: float = clampf(
		-_w.sidebar.position.x / dw, 0.0, 1.0
	)
	if _should_snap_open(1.0 - close_progress, _swipe_velocity):
		_snap_drawer_open(1.0 - close_progress)
	else:
		AppState.sidebar_drawer_open = false
		AppState.nav_history.remove(&"drawer")
		_snap_drawer_closed_from_close(close_progress)


func _snap_drawer_closed_from_close(close_progress: float) -> void:
	if Config.get_reduced_motion():
		_w._drawer.hide_drawer_nodes()
		return
	var dw: float = _w._drawer.get_drawer_width()
	var duration: float = maxf(0.2 * (1.0 - close_progress), 0.05)
	if _w._drawer._drawer_tween:
		_w._drawer._drawer_tween.kill()
	_w._drawer._drawer_tween = _w.create_tween().set_parallel(true)
	_w._drawer._drawer_tween.tween_property(
		_w.sidebar, "position:x", -dw, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._drawer_tween.tween_property(
		_w.drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer._drawer_tween.chain().tween_callback(_w._hide_drawer_nodes)


# --- Right-Edge Swipe (member list drawer) ---

func _handle_right_edge_swipe(event: InputEvent) -> void:
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var edge_zone: float = _get_edge_zone()
	var right_edge: float = vp_width - edge_zone

	# Touch events
	if event is InputEventScreenTouch:
		if event.pressed and event.position.x >= right_edge:
			_right_edge_tracking = true
			_right_edge_start_x = event.position.x
			_right_swipe_active = false
			_swipe_last_x = event.position.x
			_swipe_last_time = Time.get_ticks_msec() / 1000.0
			_swipe_velocity = 0.0
		elif not event.pressed:
			if _right_swipe_active:
				_finish_member_open_swipe()
			elif _right_edge_tracking:
				var disp: float = (
					_right_edge_start_x - event.position.x
				)
				if disp >= SWIPE_THRESHOLD:
					AppState.toggle_member_drawer()
			_reset_right_edge()
	elif event is InputEventScreenDrag and _right_edge_tracking:
		var disp: float = _right_edge_start_x - event.position.x
		if not _right_swipe_active and disp >= SWIPE_DEAD_ZONE:
			_right_swipe_active = true
			_begin_member_drawer_tracking()
		if _right_swipe_active:
			_update_member_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()

	# Mouse events (desktop testing)
	if event is InputEventMouseButton:
		if (event.pressed and event.button_index == MOUSE_BUTTON_LEFT
				and event.position.x >= right_edge):
			_right_edge_tracking = true
			_right_edge_start_x = event.position.x
			_right_swipe_active = false
			_swipe_last_x = event.position.x
			_swipe_last_time = Time.get_ticks_msec() / 1000.0
			_swipe_velocity = 0.0
		elif (not event.pressed
				and event.button_index == MOUSE_BUTTON_LEFT):
			if _right_swipe_active:
				_finish_member_open_swipe()
			elif _right_edge_tracking:
				var disp: float = (
					_right_edge_start_x - event.position.x
				)
				if disp >= SWIPE_THRESHOLD:
					AppState.toggle_member_drawer()
			_reset_right_edge()
	elif event is InputEventMouseMotion and _right_edge_tracking:
		var disp: float = _right_edge_start_x - event.position.x
		if not _right_swipe_active and disp >= SWIPE_DEAD_ZONE:
			_right_swipe_active = true
			_begin_member_drawer_tracking()
		if _right_swipe_active:
			_update_member_drawer_position(event.position.x)
			_w.get_viewport().set_input_as_handled()


func _reset_right_edge() -> void:
	_right_edge_tracking = false
	_right_swipe_active = false


func _begin_member_drawer_tracking() -> void:
	if _w._drawer._member_drawer_tween:
		_w._drawer._member_drawer_tween.kill()
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	_w.member_drawer_backdrop.visible = true
	_w.member_drawer_container.visible = true
	_w.member_list.visible = true
	_w.member_list.custom_minimum_size.x = dw
	_w.member_list.offset_left = -dw
	_w.member_list.position.x = vp_width
	_w.member_drawer_backdrop.modulate.a = 0.0


func _update_member_drawer_position(pos_x: float) -> void:
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var progress: float = clampf(
		(_right_edge_start_x - pos_x) / dw, 0.0, 1.0
	)
	_w.member_list.position.x = vp_width - (dw * progress)
	_w.member_drawer_backdrop.modulate.a = progress
	# Track velocity
	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _swipe_last_time
	if dt > 0.001:
		_swipe_velocity = (pos_x - _swipe_last_x) / dt
	_swipe_last_x = pos_x
	_swipe_last_time = now


func _finish_member_open_swipe() -> void:
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var progress: float = clampf(
		(vp_width - _w.member_list.position.x) / dw, 0.0, 1.0
	)
	# Velocity is negative (leftward) when opening the member drawer
	if _should_snap_open(progress, -_swipe_velocity):
		_snap_member_open(progress)
	else:
		_snap_member_closed(progress)


func _snap_member_open(progress: float) -> void:
	AppState.member_drawer_open = true
	AppState.nav_history.push(&"member_drawer")
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var target_x: float = vp_width - dw
	if Config.get_reduced_motion():
		_w.member_list.position.x = target_x
		_w.member_drawer_backdrop.modulate.a = 1.0
		return
	var duration: float = maxf(0.2 * (1.0 - progress), 0.05)
	if _w._drawer._member_drawer_tween:
		_w._drawer._member_drawer_tween.kill()
	_w._drawer._member_drawer_tween = (
		_w.create_tween().set_parallel(true)
	)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_list, "position:x", target_x, duration
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_drawer_backdrop, "modulate:a", 1.0, duration
	)


func _snap_member_closed(progress: float) -> void:
	if Config.get_reduced_motion():
		_w._drawer.hide_member_drawer_nodes()
		return
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var duration: float = maxf(0.2 * progress, 0.05)
	if _w._drawer._member_drawer_tween:
		_w._drawer._member_drawer_tween.kill()
	_w._drawer._member_drawer_tween = (
		_w.create_tween().set_parallel(true)
	)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_list, "position:x", vp_width, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer._member_drawer_tween.chain().tween_callback(
		_w._hide_member_drawer_nodes
	)


# --- Member Drawer Close Swipe ---

func _handle_member_close_swipe(event: InputEvent) -> void:
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var drawer_left: float = vp_width - dw

	# Touch events
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < drawer_left:
				_member_close_swipe_tracking = true
				_member_close_start_x = event.position.x
				_member_close_active = false
				_swipe_last_x = event.position.x
				_swipe_last_time = Time.get_ticks_msec() / 1000.0
				_swipe_velocity = 0.0
				_w.get_viewport().set_input_as_handled()
		elif not event.pressed:
			if _member_close_active:
				_finish_member_close_swipe()
			elif _member_close_swipe_tracking:
				AppState.close_member_drawer()
			_reset_member_close()
	elif event is InputEventScreenDrag and _member_close_swipe_tracking:
		var disp: float = event.position.x - _member_close_start_x
		if not _member_close_active and disp >= SWIPE_DEAD_ZONE:
			_member_close_active = true
		if _member_close_active:
			_update_member_close_position(event.position.x)
			_w.get_viewport().set_input_as_handled()

	# Mouse events (desktop testing)
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if event.position.x < drawer_left:
				_member_close_swipe_tracking = true
				_member_close_start_x = event.position.x
				_member_close_active = false
				_swipe_last_x = event.position.x
				_swipe_last_time = Time.get_ticks_msec() / 1000.0
				_swipe_velocity = 0.0
				_w.get_viewport().set_input_as_handled()
		elif (not event.pressed
				and event.button_index == MOUSE_BUTTON_LEFT):
			if _member_close_active:
				_finish_member_close_swipe()
			elif _member_close_swipe_tracking:
				AppState.close_member_drawer()
			_reset_member_close()
	elif event is InputEventMouseMotion and _member_close_swipe_tracking:
		var disp: float = event.position.x - _member_close_start_x
		if not _member_close_active and disp >= SWIPE_DEAD_ZONE:
			_member_close_active = true
		if _member_close_active:
			_update_member_close_position(event.position.x)
			_w.get_viewport().set_input_as_handled()


func _reset_member_close() -> void:
	_member_close_swipe_tracking = false
	_member_close_active = false


func _update_member_close_position(pos_x: float) -> void:
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var close_progress: float = clampf(
		(pos_x - _member_close_start_x) / dw, 0.0, 1.0
	)
	_w.member_list.position.x = (
		(vp_width - dw) + (dw * close_progress)
	)
	_w.member_drawer_backdrop.modulate.a = 1.0 - close_progress
	# Track velocity
	var now: float = Time.get_ticks_msec() / 1000.0
	var dt: float = now - _swipe_last_time
	if dt > 0.001:
		_swipe_velocity = (pos_x - _swipe_last_x) / dt
	_swipe_last_x = pos_x
	_swipe_last_time = now


func _finish_member_close_swipe() -> void:
	var dw: float = _w._drawer.get_member_drawer_width()
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var close_progress: float = clampf(
		(_w.member_list.position.x - (vp_width - dw)) / dw,
		0.0, 1.0,
	)
	# Positive velocity means rightward (closing)
	if _should_snap_open(1.0 - close_progress, -_swipe_velocity):
		_snap_member_open(1.0 - close_progress)
	else:
		AppState.member_drawer_open = false
		AppState.nav_history.remove(&"member_drawer")
		_snap_member_closed_from_close(close_progress)


func _snap_member_closed_from_close(
	close_progress: float,
) -> void:
	if Config.get_reduced_motion():
		_w._drawer.hide_member_drawer_nodes()
		return
	var vp_width: float = _w.get_viewport().get_visible_rect().size.x
	var duration: float = maxf(
		0.2 * (1.0 - close_progress), 0.05
	)
	if _w._drawer._member_drawer_tween:
		_w._drawer._member_drawer_tween.kill()
	_w._drawer._member_drawer_tween = (
		_w.create_tween().set_parallel(true)
	)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_list, "position:x", vp_width, duration
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_w._drawer._member_drawer_tween.tween_property(
		_w.member_drawer_backdrop, "modulate:a", 0.0, duration
	)
	_w._drawer._member_drawer_tween.chain().tween_callback(
		_w._hide_member_drawer_nodes
	)


# --- Thread Swipe-Back (COMPACT mode) ---

func _handle_thread_swipe_back(event: InputEvent) -> bool:
	var edge_zone: float = _get_edge_zone()

	# Touch events
	if event is InputEventScreenTouch:
		return _thread_swipe_touch(event, edge_zone)
	if event is InputEventScreenDrag and _thread_swipe_tracking:
		return _thread_swipe_drag(
			event.position.x - _thread_swipe_start_x
		)

	# Mouse events (desktop testing)
	if event is InputEventMouseButton:
		return _thread_swipe_mouse_btn(event, edge_zone)
	if event is InputEventMouseMotion and _thread_swipe_tracking:
		return _thread_swipe_drag(
			event.position.x - _thread_swipe_start_x
		)

	return false


func _thread_swipe_touch(
	event: InputEventScreenTouch, edge_zone: float,
) -> bool:
	if event.pressed and event.position.x <= edge_zone:
		_thread_swipe_tracking = true
		_thread_swipe_start_x = event.position.x
		_thread_swipe_active = false
		return true
	if not event.pressed and _thread_swipe_tracking:
		return _thread_swipe_release(event.position.x)
	return false


func _thread_swipe_mouse_btn(
	event: InputEventMouseButton, edge_zone: float,
) -> bool:
	if (event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.position.x <= edge_zone):
		_thread_swipe_tracking = true
		_thread_swipe_start_x = event.position.x
		_thread_swipe_active = false
		return true
	if (not event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT
			and _thread_swipe_tracking):
		return _thread_swipe_release(event.position.x)
	return false


func _thread_swipe_release(end_x: float) -> bool:
	if _thread_swipe_active:
		AppState.close_thread()
		_reset_thread_swipe()
		return true
	var disp: float = end_x - _thread_swipe_start_x
	if disp >= SWIPE_THRESHOLD:
		AppState.close_thread()
		_reset_thread_swipe()
		return true
	_reset_thread_swipe()
	return false


func _thread_swipe_drag(disp: float) -> bool:
	if not _thread_swipe_active and disp >= SWIPE_DEAD_ZONE:
		_thread_swipe_active = true
	if _thread_swipe_active:
		_w.get_viewport().set_input_as_handled()
		return true
	return false


func _reset_thread_swipe() -> void:
	_thread_swipe_tracking = false
	_thread_swipe_active = false


func _should_snap_open(progress: float, velocity: float) -> bool:
	if absf(velocity) > VELOCITY_THRESHOLD:
		return velocity > 0.0
	return progress >= SNAP_PROGRESS
