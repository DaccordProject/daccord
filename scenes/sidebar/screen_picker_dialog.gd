extends ColorRect

signal source_selected(source_type: String, source_id: int)

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _source_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/SourceList

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	gui_input.connect(_on_backdrop_input)
	_populate_screens()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _populate_screens() -> void:
	_clear_list()
	var count: int = DisplayServer.get_screen_count()
	if count == 0:
		_add_empty_label("No screens found")
		return
	for i in count:
		var size: Vector2i = DisplayServer.screen_get_size(i)
		var title := "Screen %d" % (i + 1)
		_add_source_button(
			title, "%dx%d" % [size.x, size.y], "screen", i
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
