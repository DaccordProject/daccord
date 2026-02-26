extends ColorRect

signal source_selected(source: Dictionary)

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _source_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/SourceList

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	gui_input.connect(_on_backdrop_input)
	var status: Dictionary = LiveKitScreenCapture.check_permissions()
	if status.get("status", "") == "PERMISSION_ERROR":
		_add_error_label(status.get("summary", "Screen capture permission denied"))
	else:
		_populate_sources()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _populate_sources() -> void:
	_clear_list()
	# Screens section
	var monitors: Array = LiveKitScreenCapture.get_monitors()
	if monitors.size() > 0:
		_add_section_label("Screens")
		for monitor in monitors:
			var source: Dictionary = {}
			source.merge(monitor)
			source["_type"] = "monitor"
			var name: String = monitor.get("name", "Unknown")
			var w: int = monitor.get("width", 0)
			var h: int = monitor.get("height", 0)
			_add_source_button(name, "%dx%d" % [w, h], source)
	# Windows section
	var windows: Array = LiveKitScreenCapture.get_windows()
	if windows.size() > 0:
		_add_section_label("Windows")
		for window in windows:
			var source: Dictionary = {}
			source.merge(window)
			source["_type"] = "window"
			var name: String = window.get("name", "Unknown")
			var w: int = window.get("width", 0)
			var h: int = window.get("height", 0)
			_add_source_button(name, "%dx%d" % [w, h], source)
	if monitors.size() == 0 and windows.size() == 0:
		_add_empty_label("No screens or windows found")

func _add_source_button(
	title: String, resolution: String, source: Dictionary,
) -> void:
	var btn := Button.new()
	btn.text = "%s  (%s)" % [title, resolution]
	btn.custom_minimum_size = Vector2(0, 40)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func():
		source_selected.emit(source)
		_close()
	)
	_source_list.add_child(btn)

func _add_section_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override(
		"font_color", Color(0.72, 0.74, 0.78)
	)
	_source_list.add_child(lbl)

func _add_empty_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_source_list.add_child(lbl)

func _add_error_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	_source_list.add_child(lbl)

func _clear_list() -> void:
	for child in _source_list.get_children():
		child.queue_free()

func _close() -> void:
	queue_free()
