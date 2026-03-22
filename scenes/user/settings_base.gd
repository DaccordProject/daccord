class_name SettingsBase
extends ModalBase

## Shared base class for modal settings panels.
## Subclasses override _get_sections(), _build_pages(), _get_modal_size(),
## and optionally _get_subtitle() to customise the nav and content.

## Threshold below which sidebar collapses to a dropdown.
const _NAV_COMPACT_THRESHOLD: float = 600.0

var initial_page: int = 0

var _nav_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _current_page: int = 0
var _nav_panel: PanelContainer
var _body_hbox: HBoxContainer

## Compact-mode nav: dropdown replaces sidebar on narrow viewports.
var _nav_dropdown: OptionButton
var _nav_dropdown_margin: MarginContainer
var _is_compact_nav: bool = false

func _ready() -> void:
	var modal_size: Vector2 = _get_modal_size()
	_setup_modal("", modal_size.x, modal_size.y, false, 0.0)

	# Override panel style (settings uses slightly different bg)
	_modal_panel.add_theme_stylebox_override("panel",
		ThemeManager.make_flat_style("settings_bg", 8)
	)

	# Settings has its own header with smaller font and gray text
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var header_margin := MarginContainer.new()
	ThemeManager.set_margins(header_margin, 16, 8, 8, 0)
	header_margin.add_child(header)
	content_container.add_child(header_margin)

	var header_title := Label.new()
	header_title.text = tr("Settings")
	ThemeManager.style_label(header_title, 14, "text_muted")
	header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_title)

	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.flat = true
	ThemeManager.style_label(close_btn, 16, "text_muted")
	close_btn.add_theme_color_override(
		"font_hover_color", ThemeManager.get_color("text_white")
	)
	close_btn.pressed.connect(_close)
	header.add_child(close_btn)

	# Compact-mode nav dropdown (hidden by default)
	_nav_dropdown = OptionButton.new()
	_nav_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nav_dropdown.item_selected.connect(_on_nav_dropdown_selected)
	_nav_dropdown_margin = MarginContainer.new()
	ThemeManager.set_margins(_nav_dropdown_margin, 12, 12, 0, 0)
	_nav_dropdown_margin.add_child(_nav_dropdown)
	_nav_dropdown_margin.visible = false
	content_container.add_child(_nav_dropdown_margin)

	# Body: nav + content side by side
	_body_hbox = HBoxContainer.new()
	_body_hbox.add_theme_constant_override("separation", 0)
	_body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_child(_body_hbox)

	# Left nav panel
	_nav_panel = PanelContainer.new()
	_nav_panel.custom_minimum_size = Vector2(180, 0)
	var nav_style := ThemeManager.make_flat_style("nav_bg")
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
	ThemeManager.set_margins(nav_margin, 8, 8, 12, 12)
	nav_margin.add_child(nav_vbox)
	nav_scroll.add_child(nav_margin)

	# Optional subtitle (e.g. server name)
	var subtitle: String = _get_subtitle()
	if not subtitle.is_empty():
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		ThemeManager.style_label(sub_lbl, 11, "text_muted")
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
		_nav_dropdown.add_item(sections[i])

	# Right content area
	var content_scroll := ScrollContainer.new()
	content_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_hbox.add_child(content_scroll)

	var content_margin := MarginContainer.new()
	ThemeManager.set_margins(content_margin, 24, 24, 20, 20)
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


func _on_nav_dropdown_selected(index: int) -> void:
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
	if _nav_dropdown and _nav_dropdown.selected != index:
		_nav_dropdown.selected = index


func _on_viewport_resized() -> void:
	super._on_viewport_resized()
	_update_compact_nav()


func _update_compact_nav() -> void:
	if not is_instance_valid(_nav_panel):
		return
	var vp_w: float = get_viewport_rect().size.x
	var should_compact: bool = vp_w < _NAV_COMPACT_THRESHOLD
	if should_compact == _is_compact_nav:
		return
	_is_compact_nav = should_compact
	_nav_panel.visible = not should_compact
	_nav_dropdown_margin.visible = should_compact

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
	ThemeManager.style_label(lbl, 11, "text_muted")
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
	ThemeManager.style_label(lbl, 13, "error")
	lbl.visible = false
	return lbl

static func create_action_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	ThemeManager.style_button(btn, "accent", "accent_hover", "accent_pressed", 4, [16, 6, 16, 6])
	return btn

static func create_secondary_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	ThemeManager.style_button(
		btn, "secondary_button", "secondary_button_hover",
		"secondary_button_pressed", 4, [16, 6, 16, 6]
	)
	return btn

static func create_danger_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	ThemeManager.style_button(btn, "error", "error_hover", "error_pressed", 4, [16, 6, 16, 6])
	return btn
