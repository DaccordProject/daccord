class_name MainWindowDrawer
extends RefCounted

## Manages sidebar drawer positioning, animation, and toggling.

const BASE_DRAWER_WIDTH := 308.0
const MIN_BACKDROP_TAP_TARGET := 60.0

var sidebar: Control
var drawer_container: Control
var drawer_backdrop: Control
var layout_hbox: Control

var member_list: Control
var member_drawer_container: Control
var member_drawer_backdrop: Control
var content_body: Control

var _view: Control # parent MainWindow
var _sidebar_in_drawer: bool = false
var _member_in_drawer: bool = false
var _drawer_tween: Tween
var _member_drawer_tween: Tween


func _init(
	view: Control,
	p_sidebar: Control,
	p_drawer_container: Control,
	p_drawer_backdrop: Control,
	p_layout_hbox: Control,
) -> void:
	_view = view
	sidebar = p_sidebar
	drawer_container = p_drawer_container
	drawer_backdrop = p_drawer_backdrop
	layout_hbox = p_layout_hbox


func is_in_drawer() -> bool:
	return _sidebar_in_drawer


func move_sidebar_to_layout() -> void:
	if not _sidebar_in_drawer:
		return
	_sidebar_in_drawer = false
	drawer_container.remove_child(sidebar)
	layout_hbox.add_child(sidebar)
	layout_hbox.move_child(sidebar, 0)


func get_drawer_width() -> float:
	var vp_width: float = _view.get_viewport().get_visible_rect().size.x
	return minf(BASE_DRAWER_WIDTH, vp_width - MIN_BACKDROP_TAP_TARGET)


func move_sidebar_to_drawer() -> void:
	if _sidebar_in_drawer:
		return
	_sidebar_in_drawer = true
	layout_hbox.remove_child(sidebar)
	drawer_container.add_child(sidebar)
	sidebar.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	sidebar.offset_right = get_drawer_width()


func on_sidebar_drawer_toggled(is_open: bool) -> void:
	if is_open:
		open_drawer()
	else:
		close_drawer()


func open_drawer() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	var dw := get_drawer_width()
	drawer_backdrop.visible = true
	drawer_container.visible = true
	sidebar.visible = true
	sidebar.offset_right = dw
	if Config.get_reduced_motion():
		sidebar.position.x = 0.0
		drawer_backdrop.modulate.a = 1.0
		return
	sidebar.position.x = -dw
	drawer_backdrop.modulate.a = 0.0
	_drawer_tween = _view.create_tween().set_parallel(true)
	_drawer_tween.tween_property(
		sidebar, "position:x", 0.0, 0.2
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_drawer_tween.tween_property(
		drawer_backdrop, "modulate:a", 1.0, 0.2
	)


func close_drawer() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	if Config.get_reduced_motion():
		hide_drawer_nodes()
		return
	var dw := get_drawer_width()
	_drawer_tween = _view.create_tween().set_parallel(true)
	_drawer_tween.tween_property(
		sidebar, "position:x", -dw, 0.2
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_drawer_tween.tween_property(
		drawer_backdrop, "modulate:a", 0.0, 0.2
	)
	_drawer_tween.chain().tween_callback(hide_drawer_nodes)


func close_drawer_immediate() -> void:
	if _drawer_tween:
		_drawer_tween.kill()
	hide_drawer_nodes()


func hide_drawer_nodes() -> void:
	drawer_backdrop.visible = false
	drawer_container.visible = false
	AppState.sidebar_drawer_open = false
	AppState.nav_history.remove(&"drawer")


# --- Member List Drawer (right side) ---

func is_member_in_drawer() -> bool:
	return _member_in_drawer


func get_member_drawer_width() -> float:
	var vp_width: float = _view.get_viewport().get_visible_rect().size.x
	return minf(BASE_DRAWER_WIDTH, vp_width - MIN_BACKDROP_TAP_TARGET)


func move_member_to_drawer() -> void:
	if _member_in_drawer:
		return
	_member_in_drawer = true
	content_body.remove_child(member_list)
	member_drawer_container.add_child(member_list)
	member_list.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	var dw := get_member_drawer_width()
	member_list.offset_left = -dw
	member_list.visible = false


func move_member_to_layout() -> void:
	if not _member_in_drawer:
		return
	_member_in_drawer = false
	member_drawer_container.remove_child(member_list)
	content_body.add_child(member_list)


func on_member_drawer_toggled(is_open: bool) -> void:
	if is_open:
		open_member_drawer()
	else:
		close_member_drawer()


func open_member_drawer() -> void:
	if _member_drawer_tween:
		_member_drawer_tween.kill()
	var dw := get_member_drawer_width()
	member_drawer_backdrop.visible = true
	member_drawer_container.visible = true
	member_list.visible = true
	member_list.offset_left = -dw
	member_list.custom_minimum_size.x = dw
	var vp_width: float = _view.get_viewport().get_visible_rect().size.x
	if Config.get_reduced_motion():
		member_list.position.x = vp_width - dw
		member_drawer_backdrop.modulate.a = 1.0
		return
	member_list.position.x = vp_width
	member_drawer_backdrop.modulate.a = 0.0
	_member_drawer_tween = _view.create_tween().set_parallel(true)
	_member_drawer_tween.tween_property(
		member_list, "position:x", vp_width - dw, 0.2
	).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_member_drawer_tween.tween_property(
		member_drawer_backdrop, "modulate:a", 1.0, 0.2
	)


func close_member_drawer() -> void:
	if _member_drawer_tween:
		_member_drawer_tween.kill()
	if Config.get_reduced_motion():
		hide_member_drawer_nodes()
		return
	var vp_width: float = _view.get_viewport().get_visible_rect().size.x
	_member_drawer_tween = _view.create_tween().set_parallel(true)
	_member_drawer_tween.tween_property(
		member_list, "position:x", vp_width, 0.2
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_member_drawer_tween.tween_property(
		member_drawer_backdrop, "modulate:a", 0.0, 0.2
	)
	_member_drawer_tween.chain().tween_callback(hide_member_drawer_nodes)


func close_member_drawer_immediate() -> void:
	if _member_drawer_tween:
		_member_drawer_tween.kill()
	hide_member_drawer_nodes()


func hide_member_drawer_nodes() -> void:
	member_drawer_backdrop.visible = false
	member_drawer_container.visible = false
	member_list.visible = false
	AppState.member_drawer_open = false
	AppState.nav_history.remove(&"member_drawer")
