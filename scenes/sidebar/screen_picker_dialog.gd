extends ModalBase

signal source_selected(source: Dictionary)

const THUMB_WIDTH: int = 80
const THUMB_HEIGHT: int = 45

var _preview_panel: VBoxContainer
var _preview_tex: TextureRect
var _preview_label: Label
var _selected_source: Dictionary = {}

@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _title: Label = \
	$CenterContainer/Panel/VBox/Header/Title
@onready var _scroll: ScrollContainer = \
	$CenterContainer/Panel/VBox/Scroll
@onready var _source_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Scroll/SourceList

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 520, 480)
	_close_btn.pressed.connect(_close)
	_build_preview_panel()
	if OS.get_name() == "Web":
		_add_error_label(
			tr("Screen sharing is not supported in the web client")
		)
		return
	var status: Dictionary = \
		LiveKitScreenCapture.check_permissions()
	if status.get("status", -1) \
			== LiveKitScreenCapture.PERMISSION_ERROR:
		_add_error_label(
			status.get(
				"summary",
				tr("Screen capture permission denied"),
			)
		)
	else:
		_populate_sources()

# -- Preview / confirmation panel -----------------------------------------

func _build_preview_panel() -> void:
	_preview_panel = VBoxContainer.new()
	_preview_panel.add_theme_constant_override(
		"separation", 12
	)
	_preview_panel.size_flags_vertical = \
		Control.SIZE_EXPAND_FILL
	_preview_panel.visible = false
	$CenterContainer/Panel/VBox.add_child(_preview_panel)
	# Preview image
	_preview_tex = TextureRect.new()
	_preview_tex.stretch_mode = \
		TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_tex.expand_mode = \
		TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_preview_tex.custom_minimum_size = Vector2(0, 225)
	_preview_tex.size_flags_horizontal = \
		Control.SIZE_EXPAND_FILL
	_preview_tex.size_flags_vertical = \
		Control.SIZE_EXPAND_FILL
	_preview_panel.add_child(_preview_tex)
	# Source name + resolution
	_preview_label = Label.new()
	_preview_label.horizontal_alignment = \
		HORIZONTAL_ALIGNMENT_CENTER
	ThemeManager.style_label(_preview_label, 14, "text_body")
	_preview_panel.add_child(_preview_label)
	# Back / Start Sharing buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_panel.add_child(btn_row)
	var back_btn := Button.new()
	back_btn.text = tr("Back")
	back_btn.custom_minimum_size = Vector2(100, 36)
	back_btn.pressed.connect(_show_source_list)
	btn_row.add_child(back_btn)
	var share_btn := Button.new()
	share_btn.text = tr("Start Sharing")
	share_btn.custom_minimum_size = Vector2(140, 36)
	share_btn.add_theme_stylebox_override(
		"normal",
		ThemeManager.make_flat_style(
			"accent", 6, [12, 8, 12, 8]
		),
	)
	share_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	share_btn.pressed.connect(_confirm_share)
	btn_row.add_child(share_btn)

func _show_source_list() -> void:
	_preview_panel.visible = false
	_scroll.visible = true
	_title.text = tr("Share Your Screen")

func _show_preview(source: Dictionary) -> void:
	_selected_source = source
	_scroll.visible = false
	_preview_panel.visible = true
	var sname: String = source.get("name", tr("Unknown"))
	var w: int = source.get("width", 0)
	var h: int = source.get("height", 0)
	_preview_label.text = "%s  (%dx%d)" % [sname, w, h]
	_title.text = tr("Preview")
	var image: Image = _capture_screenshot(source)
	if image != null:
		_preview_tex.texture = \
			ImageTexture.create_from_image(image)
	else:
		_preview_tex.texture = null

func _confirm_share() -> void:
	source_selected.emit(_selected_source)
	_close()

# -- Source list -----------------------------------------------------------

func _populate_sources() -> void:
	_clear_list()
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	if monitors.size() > 0:
		_add_section_label(tr("Screens"))
		for monitor in monitors:
			var source: Dictionary = {}
			source.merge(monitor)
			source["_type"] = "monitor"
			var sname: String = monitor.get(
				"name", tr("Unknown")
			)
			var w: int = monitor.get("width", 0)
			var h: int = monitor.get("height", 0)
			_add_source_button(
				sname, "%dx%d" % [w, h], source
			)
	var windows: Array = LiveKitScreenCapture.get_windows()
	if windows.size() > 0:
		_add_section_label(tr("Windows"))
		for window in windows:
			var source: Dictionary = {}
			source.merge(window)
			source["_type"] = "window"
			var sname: String = window.get(
				"name", tr("Unknown")
			)
			var w: int = window.get("width", 0)
			var h: int = window.get("height", 0)
			_add_source_button(
				sname, "%dx%d" % [w, h], source
			)
	if not monitors and not windows:
		_add_empty_label(tr("No screens or windows found"))

func _add_source_button(
	title: String, resolution: String,
	source: Dictionary,
) -> void:
	var btn := Button.new()
	btn.text = "  %s  (%s)" % [title, resolution]
	btn.custom_minimum_size = Vector2(0, 56)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var image: Image = _capture_screenshot(source)
	if image != null:
		image.resize(
			THUMB_WIDTH, THUMB_HEIGHT,
			Image.INTERPOLATE_BILINEAR,
		)
		btn.icon = ImageTexture.create_from_image(image)
	btn.pressed.connect(_show_preview.bind(source))
	_source_list.add_child(btn)

func _capture_screenshot(source: Dictionary) -> Image:
	var source_type: String = source.get("_type", "monitor")
	var capture = null
	if source_type == "window":
		capture = LiveKitScreenCapture.create_for_window(
			source
		)
	else:
		capture = LiveKitScreenCapture.create_for_monitor(
			source
		)
	if capture == null:
		return null
	var image: Image = capture.screenshot()
	capture.close()
	return image

# -- Helper labels ---------------------------------------------------------

func _add_section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	ThemeManager.style_label(lbl, 13, "text_body")
	_source_list.add_child(lbl)

func _add_empty_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_source_list.add_child(lbl)

func _add_error_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override(
		"font_color", ThemeManager.get_color("error")
	)
	_source_list.add_child(lbl)

func _clear_list() -> void:
	NodeUtils.free_children(_source_list)
