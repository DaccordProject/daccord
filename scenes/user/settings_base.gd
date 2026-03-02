class_name SettingsBase
extends ModalBase

## Shared base class for modal settings panels.
## Subclasses override _get_sections(), _build_pages(), _get_modal_size(),
## and optionally _get_subtitle() to customise the nav and content.

var initial_page: int = 0

var _nav_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_page: int = 0
var _nav_panel: PanelContainer
var _body_hbox: HBoxContainer

func _ready() -> void:
	var modal_size: Vector2 = _get_modal_size()
	_setup_modal("", modal_size.x, modal_size.y, false, 0.0)

	# Override panel style (settings uses slightly different bg)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = ThemeManager.get_color("settings_bg")
	panel_style.set_corner_radius_all(8)
	_modal_panel.add_theme_stylebox_override("panel", panel_style)

	# Settings has its own header with smaller font and gray text
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 16)
	header_margin.add_theme_constant_override("margin_right", 8)
	header_margin.add_theme_constant_override("margin_top", 8)
	header_margin.add_theme_constant_override("margin_bottom", 0)
	header_margin.add_child(header)
	content_container.add_child(header_margin)

	var header_title := Label.new()
	header_title.text = "Settings"
	header_title.add_theme_font_size_override("font_size", 14)
	header_title.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_title)

	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	close_btn.add_theme_color_override(
		"font_hover_color", ThemeManager.get_color("text_white")
	)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# Body: nav + content side by side
	_body_hbox = HBoxContainer.new()
	_body_hbox.add_theme_constant_override("separation", 0)
	_body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_child(_body_hbox)

	# Left nav panel
	_nav_panel = PanelContainer.new()
	_nav_panel.custom_minimum_size = Vector2(180, 0)
	var nav_style := StyleBoxFlat.new()
	nav_style.bg_color = ThemeManager.get_color("nav_bg")
	nav_style.corner_radius_bottom_left = 8
	_nav_panel.add_theme_stylebox_override("panel", nav_style)
	_body_hbox.add_child(_nav_panel)

	var nav_scroll := ScrollContainer.new()
	nav_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_nav_panel.add_child(nav_scroll)

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
			"font_color", ThemeManager.get_color("text_muted")
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
	_body_hbox.add_child(content_scroll)

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
				"font_color", ThemeManager.get_color("text_white")
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
		"font_color", ThemeManager.get_color("text_muted")
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
		"font_color", ThemeManager.get_color("error")
	)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.visible = false
	return lbl

static func create_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeManager.get_color("accent")
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = ThemeManager.get_color("accent_hover")
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = ThemeManager.get_color("accent_pressed")
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left = 16
	pressed.content_margin_right = 16
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

static func create_secondary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeManager.get_color("secondary_button")
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = ThemeManager.get_color("secondary_button_hover")
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = ThemeManager.get_color("secondary_button_pressed")
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left = 16
	pressed.content_margin_right = 16
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

static func create_danger_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	var normal := StyleBoxFlat.new()
	normal.bg_color = ThemeManager.get_color("error")
	normal.set_corner_radius_all(4)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = ThemeManager.get_color("error_hover")
	hover.set_corner_radius_all(4)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	hover.content_margin_top = 6
	hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = ThemeManager.get_color("error_pressed")
	pressed.set_corner_radius_all(4)
	pressed.content_margin_left = 16
	pressed.content_margin_right = 16
	pressed.content_margin_top = 6
	pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn
