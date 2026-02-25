class_name SettingsBase
extends ColorRect

## Shared base class for modal settings panels.
## Subclasses override _get_sections(), _build_pages(), _get_modal_size(),
## and optionally _get_subtitle() to customise the nav and content.

var initial_page: int = 0

var _nav_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_page: int = 0

func _ready() -> void:
	# Semi-transparent backdrop that dims the background
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Centered modal panel
	var modal_size: Vector2 = _get_modal_size()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = modal_size
	panel.size = modal_size
	panel.position = -modal_size / 2
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.188, 0.196, 0.212)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	add_child(panel)

	# Outer VBox: header bar + body
	var outer_vbox := VBoxContainer.new()
	outer_vbox.add_theme_constant_override("separation", 0)
	panel.add_child(outer_vbox)

	# Header bar with title and X close button
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 16)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_top", 8)
	header_margin.add_theme_constant_override("margin_bottom", 0)
	header_margin.add_child(header)
	outer_vbox.add_child(header_margin)

	var header_title := Label.new()
	header_title.text = "Settings"
	header_title.add_theme_font_size_override("font_size", 14)
	header_title.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_title)

	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	close_btn.add_theme_color_override(
		"font_hover_color", Color.WHITE
	)
	close_btn.pressed.connect(queue_free)
	header.add_child(close_btn)

	# Body: nav + content side by side
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_vbox.add_child(hbox)

	# Left nav panel
	var nav_panel := PanelContainer.new()
	nav_panel.custom_minimum_size = Vector2(180, 0)
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = Color(0.153, 0.161, 0.176)
	nav_style.corner_radius_bottom_left = 8
	nav_panel.add_theme_stylebox_override("panel", nav_style)
	hbox.add_child(nav_panel)

	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nav_panel.add_child(nav_scroll)

	var nav_vbox := VBoxContainer.new()
	nav_vbox.add_theme_constant_override("separation", 2)
	nav_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nav_margin := MarginContainer.new()
	nav_margin.add_theme_constant_override("margin_left", 8)
	nav_margin.add_theme_constant_override("margin_right", 8)
	nav_margin.add_theme_constant_override("margin_top", 12)
	nav_margin.add_theme_constant_override("margin_bottom", 12)
	nav_margin.add_child(nav_vbox)
	nav_scroll.add_child(nav_margin)

	# Optional subtitle (e.g. server name)
	var subtitle: String = _get_subtitle()
	if not subtitle.is_empty():
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.add_theme_font_size_override("font_size", 11)
		sub_lbl.add_theme_color_override(
			"font_color", Color(0.58, 0.608, 0.643)
		)
		nav_vbox.add_child(sub_lbl)
		var sub_sep := HSeparator.new()
		nav_vbox.add_child(sub_sep)

	var sections: Array = _get_sections()
	for i in sections.size():
		var btn := Button.new()
		btn.text = sections[i]
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_nav_pressed.bind(i))
		nav_vbox.add_child(btn)
		_nav_buttons.append(btn)

	# Right content area
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hbox.add_child(content_scroll)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", 24)
	content_margin.add_theme_constant_override("margin_right", 24)
	content_margin.add_theme_constant_override("margin_top", 20)
	content_margin.add_theme_constant_override("margin_bottom", 20)
	content_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_margin)

	var content_stack := VBoxContainer.new()
	content_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_margin.add_child(content_stack)

	# Build all pages (provided by subclass)
	for page in _build_pages():
		_pages.append(page)
	for page in _pages:
		content_stack.add_child(page)
		page.visible = false

	_show_page(initial_page)

func _on_nav_pressed(index: int) -> void:
	_show_page(index)

func _show_page(index: int) -> void:
	for i in _pages.size():
		_pages[i].visible = (i == index)
	_current_page = index
	for i in _nav_buttons.size():
		if i == index:
			_nav_buttons[i].add_theme_color_override(
				"font_color", Color.WHITE
			)
		else:
			_nav_buttons[i].remove_theme_color_override("font_color")

# --- Subclass hooks ---

func _get_sections() -> Array:
	return []

func _build_pages() -> Array:
	return []

func _get_subtitle() -> String:
	return ""

func _get_modal_size() -> Vector2:
	return Vector2(900, 620)

# --- Shared helper builders ---

func _page_vbox(title_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	var sep := HSeparator.new()
	vbox.add_child(sep)
	return vbox

func _section_label(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	return lbl

func _labeled_value(label_text: String, value_text: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.add_child(_section_label(label_text))
	var val := Label.new()
	val.text = value_text
	vbox.add_child(val)
	return vbox

func _error_label() -> Label:
	var lbl := Label.new()
	lbl.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.visible = false
	return lbl

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
