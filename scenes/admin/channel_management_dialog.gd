extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""
var _editing_channel_id: String = ""

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _channel_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/ChannelList
@onready var _create_toggle: Button = $CenterContainer/Panel/VBox/CreateToggle
@onready var _create_form: VBoxContainer = $CenterContainer/Panel/VBox/CreateForm
@onready var _create_name: LineEdit = $CenterContainer/Panel/VBox/CreateForm/CreateNameInput
@onready var _create_type: OptionButton = $CenterContainer/Panel/VBox/CreateForm/CreateTypeOption
@onready var _create_parent: OptionButton = \
	$CenterContainer/Panel/VBox/CreateForm/CreateParentOption
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/CreateForm/CreateButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_create_toggle.pressed.connect(_toggle_create_form)
	_create_btn.pressed.connect(_on_create)
	_create_form.visible = false

	_create_type.add_item("Text", 0)
	_create_type.add_item("Voice", 1)
	_create_type.add_item("Announcement", 2)
	_create_type.add_item("Forum", 3)
	_create_type.add_item("Category", 4)

	AppState.channels_updated.connect(_on_channels_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_rebuild_list()
	_rebuild_parent_options()

func _rebuild_list() -> void:
	for child in _channel_list.get_children():
		child.queue_free()

	var channels: Array = Client.get_channels_for_guild(_guild_id)
	channels.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.get("name", "") < b.get("name", "")
	)

	for ch in channels:
		var row := _create_channel_row(ch)
		_channel_list.add_child(row)

func _create_channel_row(ch: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.set_meta("channel_id", ch.get("id", ""))

	# Type icon
	var type_label := Label.new()
	var ch_type: int = ch.get("type", 0)
	match ch_type:
		ClientModels.ChannelType.TEXT: type_label.text = "#"
		ClientModels.ChannelType.VOICE: type_label.text = "V"
		ClientModels.ChannelType.ANNOUNCEMENT: type_label.text = "A"
		ClientModels.ChannelType.FORUM: type_label.text = "F"
		ClientModels.ChannelType.CATEGORY: type_label.text = "C"
	type_label.custom_minimum_size = Vector2(20, 0)
	type_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	row.add_child(type_label)

	# Name
	var name_label := Label.new()
	name_label.text = ch.get("name", "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	# Edit button
	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.flat = true
	edit_btn.add_theme_color_override("font_color", Color(0.345, 0.396, 0.949))
	edit_btn.pressed.connect(_on_edit_channel.bind(ch))
	row.add_child(edit_btn)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "Del"
	del_btn.flat = true
	del_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	del_btn.pressed.connect(_on_delete_channel.bind(ch))
	row.add_child(del_btn)

	return row

func _rebuild_parent_options() -> void:
	_create_parent.clear()
	_create_parent.add_item("None", 0)
	var channels: Array = Client.get_channels_for_guild(_guild_id)
	var idx: int = 1
	for ch in channels:
		if ch.get("type", 0) == ClientModels.ChannelType.CATEGORY:
			_create_parent.add_item(ch.get("name", ""), idx)
			_create_parent.set_item_metadata(idx, ch.get("id", ""))
			idx += 1

func _toggle_create_form() -> void:
	_create_form.visible = not _create_form.visible
	_create_toggle.text = "Cancel" if _create_form.visible else "Create Channel"

func _on_create() -> void:
	var ch_name: String = _create_name.text.strip_edges()
	if ch_name.is_empty():
		_show_error("Channel name cannot be empty.")
		return

	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var type_map := ["text", "voice", "announcement", "forum", "category"]
	var data := {
		"name": ch_name,
		"type": type_map[_create_type.selected],
	}

	var parent_idx: int = _create_parent.selected
	if parent_idx > 0:
		var parent_id = _create_parent.get_item_metadata(parent_idx)
		if parent_id is String and not parent_id.is_empty():
			data["parent_id"] = parent_id

	var result: RestResult = await Client.create_channel(_guild_id, data)
	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var err_msg: String = "Failed to create channel"
		if result != null and result.error:
			err_msg = result.error.message
		_show_error(err_msg)
	else:
		_create_name.text = ""
		_create_form.visible = false
		_create_toggle.text = "Create Channel"

func _on_edit_channel(ch: Dictionary) -> void:
	var channel_id: String = ch.get("id", "")
	# Show inline edit dialog
	var edit_dialog := _build_edit_dialog(ch)
	get_tree().root.add_child(edit_dialog)

func _build_edit_dialog(ch: Dictionary) -> ColorRect:
	var backdrop := ColorRect.new()
	backdrop.anchors_preset = Control.PRESET_FULL_RECT
	backdrop.color = Color(0, 0, 0, 0.6)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.anchors_preset = Control.PRESET_FULL_RECT
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.184, 0.192, 0.212)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_top = 20.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_bottom = 20.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Edit Channel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 18)
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "\u2715"
	close_btn.flat = true
	close_btn.pressed.connect(func(): backdrop.queue_free())
	header.add_child(close_btn)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = "CHANNEL NAME"
	name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	name_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(name_label)

	var name_input := LineEdit.new()
	name_input.custom_minimum_size = Vector2(0, 36)
	name_input.text = ch.get("name", "")
	vbox.add_child(name_input)

	var topic_label := Label.new()
	topic_label.text = "TOPIC"
	topic_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	topic_label.add_theme_font_size_override("font_size", 11)
	vbox.add_child(topic_label)

	var topic_input := LineEdit.new()
	topic_input.custom_minimum_size = Vector2(0, 36)
	topic_input.text = ch.get("topic", "")
	topic_input.placeholder_text = "Channel topic"
	vbox.add_child(topic_input)

	var nsfw_check := CheckBox.new()
	nsfw_check.text = "NSFW"
	nsfw_check.button_pressed = ch.get("nsfw", false)
	vbox.add_child(nsfw_check)

	var err_label := Label.new()
	err_label.visible = false
	err_label.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	err_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(err_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 8)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.flat = true
	cancel_btn.custom_minimum_size = Vector2(80, 36)
	cancel_btn.pressed.connect(func(): backdrop.queue_free())
	btn_row.add_child(cancel_btn)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(80, 36)
	var save_style := StyleBoxFlat.new()
	save_style.bg_color = Color(0.345, 0.396, 0.949)
	save_style.corner_radius_top_left = 4
	save_style.corner_radius_top_right = 4
	save_style.corner_radius_bottom_left = 4
	save_style.corner_radius_bottom_right = 4
	save_style.content_margin_left = 12.0
	save_style.content_margin_top = 4.0
	save_style.content_margin_right = 12.0
	save_style.content_margin_bottom = 4.0
	save_btn.add_theme_stylebox_override("normal", save_style)
	var channel_id: String = ch.get("id", "")
	save_btn.pressed.connect(func():
		save_btn.disabled = true
		save_btn.text = "Saving..."
		var data := {
			"name": name_input.text.strip_edges(),
			"topic": topic_input.text.strip_edges(),
			"nsfw": nsfw_check.button_pressed,
		}
		var result: RestResult = await Client.update_channel(channel_id, data)
		save_btn.disabled = false
		save_btn.text = "Save"
		if result == null or not result.ok:
			var msg: String = "Failed to update channel"
			if result != null and result.error:
				msg = result.error.message
			err_label.text = msg
			err_label.visible = true
		else:
			backdrop.queue_free()
	)
	btn_row.add_child(save_btn)
	vbox.add_child(btn_row)

	backdrop.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			backdrop.queue_free()
	)

	return backdrop

func _on_delete_channel(ch: Dictionary) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Channel",
		"Are you sure you want to delete #%s? This cannot be undone." % ch.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.delete_channel(ch.get("id", ""))
	)

func _on_channels_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_rebuild_list()
		_rebuild_parent_options()

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
