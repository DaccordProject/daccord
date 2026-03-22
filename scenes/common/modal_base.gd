class_name ModalBase
extends ColorRect

## Base class for all modal dialogs.
##
## Two usage patterns:
##
## 1) Code-built modals — call _setup_modal() from _ready(), then add children
##    to `content_container`:
##      func _ready() -> void:
##          modal_title = "My Dialog"
##          modal_width = 480.0
##          _setup_modal()
##          var label := Label.new()
##          content_container.add_child(label)
##
## 2) Scene-based modals — set up the node tree in .tscn, then call
##    _bind_modal_nodes() from _ready() to enable responsive sizing and shared
##    input handling. The .tscn must have: CenterContainer/Panel (PanelContainer).
##      func _ready() -> void:
##          _bind_modal_nodes($CenterContainer/Panel, 480.0)

signal closed()

## Preferred width of the modal panel. Shrinks on narrow viewports.
var modal_width: float = 400.0

## Preferred height (0 = auto, fits content).
var modal_height: float = 0.0

## References set by _setup_modal() or _bind_modal_nodes().
var content_container: VBoxContainer
var _modal_panel: PanelContainer
var _modal_title_label: Label
var _modal_close_btn: Button


## Call from _ready() for code-built modals. Creates the full node tree.
func _setup_modal(title: String = "", width: float = 400.0, height: float = 0.0,
		show_header: bool = true, padding: float = 24.0) -> void:
	modal_width = width
	modal_height = height

	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = ThemeManager.get_color("overlay")
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_modal_panel = PanelContainer.new()
	_modal_panel.custom_minimum_size = Vector2(width, height)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = ThemeManager.get_color("modal_bg")
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = padding
	panel_style.content_margin_right = padding
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_bottom = 20.0
	_modal_panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(_modal_panel)

	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 12)
	_modal_panel.add_child(outer_vbox)

	if show_header:
		var header := HBoxContainer.new()
		outer_vbox.add_child(header)

		_modal_title_label = Label.new()
		_modal_title_label.text = title
		_modal_title_label.add_theme_font_size_override("font_size", 20)
		_modal_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(_modal_title_label)

		_modal_close_btn = Button.new()
		_modal_close_btn.text = "\u2715"
		_modal_close_btn.flat = true
		_modal_close_btn.pressed.connect(_close)
		header.add_child(_modal_close_btn)

	content_container = VBoxContainer.new()
	content_container.name = "Content"
	content_container.add_theme_constant_override("separation", 12)
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(content_container)

	add_to_group("themed")
	_start_responsive()


## Call from _ready() for scene-based modals. Binds to existing .tscn nodes
## and adds responsive sizing. Pass the PanelContainer and its preferred width.
func _bind_modal_nodes(panel: PanelContainer, width: float = 400.0,
		height: float = 0.0) -> void:
	_modal_panel = panel
	modal_width = width
	modal_height = height
	add_to_group("themed")
	_apply_modal_theme()
	_start_responsive()


func _apply_theme() -> void:
	_apply_modal_theme()
	ThemeManager.apply_font_colors(self)


func _apply_modal_theme() -> void:
	color = ThemeManager.get_color("overlay")
	if is_instance_valid(_modal_panel):
		var style: StyleBox = _modal_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.bg_color = ThemeManager.get_color("modal_bg")


func set_modal_title(text: String) -> void:
	if _modal_title_label:
		_modal_title_label.text = text


## Show a REST error on _error_label if the result failed. Returns true on error.
## Requires the subclass to have an `_error_label: Label` node.
func _show_rest_error(result: RestResult, fallback: String) -> bool:
	if result != null and result.ok:
		return false
	var msg: String = fallback
	if result != null and result.error:
		msg = result.error.message
	if "_error_label" in self and _error_label_node() != null:
		_error_label_node().text = msg
		_error_label_node().visible = true
	return true


## Run an async action while showing a loading state on a button.
## Returns the result of the action callable.
func _with_button_loading(
	btn: Button, normal_text: String, action: Callable,
) -> Variant:
	btn.disabled = true
	btn.text = tr("Loading...")
	var result: Variant = await action.call()
	btn.disabled = false
	btn.text = normal_text
	return result


## Remove all children from a container node.
static func _clear_children(container: Node) -> void:
	NodeUtils.free_children(container)


## Try to close with unsaved-changes guard. Requires _dirty var in subclass.
## Pass a ConfirmDialog packed scene to show the discard prompt.
func _try_close_dirty(
	dirty: bool, confirm_scene: PackedScene,
) -> void:
	if dirty:
		var dialog: Node = confirm_scene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(
			tr("Unsaved Changes"),
			tr("You have unsaved changes. Discard?"),
			tr("Discard"),
			true
		)
		dialog.confirmed.connect(queue_free)
	else:
		queue_free()


## Helper to access _error_label in subclasses without requiring it here.
func _error_label_node() -> Label:
	return get("_error_label") as Label


func _close() -> void:
	closed.emit()
	queue_free()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_close()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _start_responsive() -> void:
	get_tree().root.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


func _on_viewport_resized() -> void:
	if not is_instance_valid(_modal_panel):
		return
	var vp_size: Vector2 = get_viewport_rect().size

	# Horizontal: shrink panel to fit viewport with 16px margins
	var max_w: float = maxf(vp_size.x - 32.0, 200.0)
	var w: float = minf(modal_width, max_w)

	# Vertical: cap height so modal doesn't overflow viewport
	var max_h: float = maxf(vp_size.y - 32.0, 200.0)
	var h: float = modal_height if modal_height > 0.0 else 0.0
	if h > 0.0:
		h = minf(h, max_h)

	_modal_panel.custom_minimum_size = Vector2(w, h)
	_modal_panel.clip_contents = true

	# For auto-height modals, clamp if content grew too tall
	if modal_height <= 0.0 and _modal_panel.size.y > max_h:
		_modal_panel.custom_minimum_size.y = max_h
	# Hard-cap: if panel exceeds viewport bounds, force-shrink via size
	if _modal_panel.size.x > max_w or _modal_panel.size.y > max_h:
		_modal_panel.set_deferred("size", Vector2(
			minf(_modal_panel.size.x, max_w),
			minf(_modal_panel.size.y, max_h)))


func _exit_tree() -> void:
	if get_tree() and get_tree().root.size_changed.is_connected(_on_viewport_resized):
		get_tree().root.size_changed.disconnect(_on_viewport_resized)
