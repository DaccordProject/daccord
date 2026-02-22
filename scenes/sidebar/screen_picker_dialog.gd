extends ColorRect

signal source_selected(source_type: String, source_id: int)

var _accord_stream = Engine.get_singleton("AccordStream")

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _tab_bar: TabBar = $CenterContainer/Panel/VBox/TabBar
@onready var _source_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/SourceList

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_tab_bar.tab_changed.connect(_on_tab_changed)
	gui_input.connect(_on_backdrop_input)
	_populate_screens()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _on_tab_changed(tab: int) -> void:
	if tab == 0:
		_populate_screens()
	else:
		_populate_windows()

func _populate_screens() -> void:
	_clear_list()
	var screens: Array = _accord_stream.get_screens()
	if screens.is_empty():
		_add_empty_label("No screens found")
		return
	for s in screens:
		var sid: int = s.get("id", 0)
		var title: String = s.get("title", "Screen %d" % sid)
		var w: int = s.get("width", 0)
		var h: int = s.get("height", 0)
		_add_source_button(
			title, "%dx%d" % [w, h], "screen", sid
		)

func _populate_windows() -> void:
	_clear_list()
	var windows: Array = _accord_stream.get_windows()
	if windows.is_empty():
		_add_empty_label("No windows found")
		return
	for w in windows:
		var wid: int = w.get("id", 0)
		var title: String = w.get("title", "Window %d" % wid)
		var ww: int = w.get("width", 0)
		var wh: int = w.get("height", 0)
		_add_source_button(
			title, "%dx%d" % [ww, wh], "window", wid
		)

func _add_source_button(
	title: String, resolution: String,
	source_type: String, source_id: int,
) -> void:
	var btn := Button.new()
	btn.text = "%s  (%s)" % [title, resolution]
	btn.custom_minimum_size = Vector2(0, 40)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(func():
		source_selected.emit(source_type, source_id)
		_close()
	)
	_source_list.add_child(btn)

func _add_empty_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	_source_list.add_child(lbl)

func _clear_list() -> void:
	for child in _source_list.get_children():
		child.queue_free()

func _close() -> void:
	queue_free()
