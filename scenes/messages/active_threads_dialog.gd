extends ModalBase

var _channel_id: String = ""
var _scroll: ScrollContainer
var _list: VBoxContainer
var _loading_label: Label
var _empty_label: Label

func _ready() -> void:
	_setup_modal(tr("Active Threads"), 480.0, 400.0)

	_loading_label = Label.new()
	_loading_label.text = tr("Loading threads...")
	_loading_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content_container.add_child(_loading_label)

	_empty_label = Label.new()
	_empty_label.text = tr("No active threads")
	_empty_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	content_container.add_child(_empty_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_container.add_child(_scroll)

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_scroll.add_child(_list)

func open(channel_id: String) -> void:
	_channel_id = channel_id
	_loading_label.visible = true
	_empty_label.visible = false
	var threads: Array = await Client.fetch.fetch_active_threads(channel_id)
	if not is_instance_valid(self):
		return
	_loading_label.visible = false
	if threads.is_empty():
		_empty_label.visible = true
		return
	for msg in threads:
		var item := _create_thread_item(msg)
		_list.add_child(item)

func _create_thread_item(msg: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeManager.get_color("input_bg")
	style.set_corner_radius_all(4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# Author + timestamp row
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var author: Dictionary = msg.get("author", {})
	var author_label := Label.new()
	author_label.text = author.get("display_name", tr("Unknown"))
	author_label.add_theme_font_size_override("font_size", 13)
	author_label.add_theme_color_override("font_color", author.get("color", Color.WHITE))
	header.add_child(author_label)

	var time_label := Label.new()
	time_label.text = msg.get("timestamp", "")
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	header.add_child(time_label)

	# Content preview
	var content: String = msg.get("content", "")
	if content.length() > 100:
		content = content.substr(0, 100) + "..."
	var content_label := Label.new()
	content_label.text = content
	content_label.add_theme_font_size_override("font_size", 13)
	content_label.add_theme_color_override("font_color", ThemeManager.get_color("text_body"))
	content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(content_label)

	# Reply count
	var reply_count: int = msg.get("reply_count", 0)
	if reply_count > 0:
		var count_label := Label.new()
		var suffix: String = tr("reply") if reply_count == 1 else tr("replies")
		count_label.text = tr("%d %s") % [reply_count, suffix]
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
		vbox.add_child(count_label)

	var msg_id: String = msg.get("id", "")
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			AppState.open_thread(msg_id)
			_close()
	)

	return panel
