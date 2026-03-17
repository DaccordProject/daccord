extends ModalBase

## Modal dialog listing available activities for the current server.
## Shown when the user presses the rocket button in the voice bar.

signal activity_launched(plugin_id: String, channel_id: String)

var _list: VBoxContainer
var _empty_label: Label
var _loading_label: Label
var _space_id: String = ""
var _channel_id: String = ""


func _ready() -> void:
	_setup_modal(tr("Activities"), 480.0, 0.0, true, 24.0)

	_loading_label = Label.new()
	_loading_label.text = tr("Loading...")
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	content_container.add_child(_loading_label)

	_empty_label = Label.new()
	_empty_label.text = tr("No activities installed on this server.")
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	_empty_label.visible = false
	content_container.add_child(_empty_label)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	AppState.plugins_updated.connect(_refresh_list)


func setup(space_id: String, channel_id: String) -> void:
	_space_id = space_id
	_channel_id = channel_id
	_refresh_list()


func _refresh_list() -> void:
	for child in _list.get_children():
		child.queue_free()

	var conn_idx: int = Client.get_conn_index_for_space(_space_id)
	if conn_idx == -1:
		_loading_label.visible = false
		_empty_label.visible = true
		return

	var plugin_list: Array = Client.plugins.get_plugins(conn_idx)
	# Filter to activities only
	var activities: Array = plugin_list.filter(
		func(p: Dictionary) -> bool:
			return p.get("type", "") == "activity"
	)

	_loading_label.visible = false
	_empty_label.visible = activities.is_empty()

	for plugin in activities:
		var card := _create_activity_card(plugin)
		_list.add_child(card)


func _create_activity_card(plugin: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var style := ThemeManager.make_flat_style("input_bg", 6, [12, 10, 12, 10])
	card.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)

	# Info column
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = plugin.get("name", tr("Unknown"))
	name_label.add_theme_font_size_override("font_size", 16)
	info.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = plugin.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc_label)

	# Meta row: runtime badge + participant count
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	info.add_child(meta)

	var runtime_label := Label.new()
	var rt: String = plugin.get("runtime", "scripted")
	runtime_label.text = rt.capitalize()
	runtime_label.add_theme_font_size_override("font_size", 11)
	runtime_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	meta.add_child(runtime_label)

	var max_p: int = plugin.get("max_participants", 0)
	if max_p > 0:
		var p_label := Label.new()
		p_label.text = tr("%d players max") % max_p
		p_label.add_theme_font_size_override("font_size", 11)
		p_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		meta.add_child(p_label)

	var version_str: String = plugin.get("version", "")
	if not version_str.is_empty():
		var v_label := Label.new()
		v_label.text = "v" + version_str
		v_label.add_theme_font_size_override("font_size", 11)
		v_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		meta.add_child(v_label)

	# Launch button
	var launch_btn := Button.new()
	launch_btn.text = tr("Launch")
	launch_btn.custom_minimum_size = Vector2(80, 36)
	var btn_style := ThemeManager.make_flat_style("accent", 4, [12, 6, 12, 6])
	launch_btn.add_theme_stylebox_override("normal", btn_style)
	launch_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_white")
	)
	launch_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pid: String = plugin.get("id", "")
	launch_btn.pressed.connect(func() -> void: _on_launch(pid))
	hbox.add_child(launch_btn)

	return card


func _on_launch(plugin_id: String) -> void:
	activity_launched.emit(plugin_id, _channel_id)
	_close()
