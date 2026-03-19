extends ModalBase

## Admin dialog for managing installed plugins within a space.
## Lists plugins with name, runtime badge, version, and uninstall button.
## Provides upload for .daccord-plugin bundle files.

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _space_id: String = ""
var _conn_index: int = -1
var _all_plugins: Array = []

@onready var _plugin_list: VBoxContainer = %PluginList
@onready var _empty_label: Label = %EmptyLabel
@onready var _upload_btn: Button = %UploadButton
@onready var _error_label: Label = %ErrorLabel
@onready var _close_btn: Button = %CloseButton


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 520.0)
	_close_btn.pressed.connect(_close)
	_upload_btn.pressed.connect(_on_upload_pressed)

	# Style upload button like an action button
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = ThemeManager.get_color("accent")
	btn_style.set_corner_radius_all(4)
	btn_style.content_margin_left = 12.0
	btn_style.content_margin_right = 12.0
	btn_style.content_margin_top = 4.0
	btn_style.content_margin_bottom = 4.0
	_upload_btn.add_theme_stylebox_override("normal", btn_style)

	AppState.plugins_updated.connect(_on_plugins_updated)


func setup(space_id: String) -> void:
	_space_id = space_id
	_conn_index = Client.get_conn_index_for_space(space_id)
	_load_plugins()


func _load_plugins() -> void:
	_clear_children(_plugin_list)
	_error_label.visible = false
	_empty_label.visible = false

	if _conn_index < 0:
		_error_label.text = tr("Not connected to this server.")
		_error_label.visible = true
		return

	_all_plugins = Client.plugins.get_plugins(_conn_index)
	_rebuild_list()


func _rebuild_list() -> void:
	_clear_children(_plugin_list)

	if _all_plugins.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false

	for plugin in _all_plugins:
		var row := _build_plugin_row(plugin)
		_plugin_list.add_child(row)


func _build_plugin_row(plugin: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := ThemeManager.make_flat_style("input_bg", 4)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	# Left: plugin info
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	# Name row with runtime badge
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	info.add_child(name_row)

	var name_label := Label.new()
	name_label.text = plugin.get("name", tr("Unknown Plugin"))
	name_label.add_theme_font_size_override("font_size", 15)
	name_row.add_child(name_label)

	# Runtime badge
	var runtime: String = plugin.get("runtime", "")
	if not runtime.is_empty():
		var badge := Label.new()
		badge.text = runtime.capitalize()
		badge.add_theme_font_size_override("font_size", 10)
		var badge_color: Color
		if runtime == "scripted":
			badge_color = ThemeManager.get_color("success")
		else:
			badge_color = ThemeManager.get_color("accent")
		badge.add_theme_color_override("font_color", badge_color)
		name_row.add_child(badge)

	# Description + version + type
	var detail_parts: Array = []
	var version: String = plugin.get("version", "")
	if not version.is_empty():
		detail_parts.append("v" + version)
	var ptype: String = plugin.get("type", "")
	if not ptype.is_empty():
		detail_parts.append(ptype)
	var desc: String = plugin.get("description", "")
	if not desc.is_empty():
		detail_parts.append(desc)

	if not detail_parts.is_empty():
		var detail := Label.new()
		detail.text = " · ".join(detail_parts)
		ThemeManager.style_label(detail, 12, "text_muted")
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		info.add_child(detail)

	# Uninstall button
	var plugin_id: String = str(plugin.get("id", ""))
	var delete_btn := SettingsBase.create_danger_button(tr("Uninstall"))
	delete_btn.pressed.connect(
		_on_delete_plugin.bind(plugin_id, plugin.get("name", ""))
	)
	hbox.add_child(delete_btn)

	return panel


func _on_upload_pressed() -> void:
	if OS.get_name() == "Web":
		_error_label.text = tr("Plugin upload is not supported on web.")
		_error_label.visible = true
		return

	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray([
		"*.daccord-plugin ; Daccord Plugin Bundle",
		"*.zip ; ZIP Archive",
	])
	fd.file_selected.connect(_on_file_selected)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error_label.text = tr("Failed to open file.")
		_error_label.visible = true
		return

	var bytes := file.get_buffer(file.get_length())
	file.close()

	if bytes.is_empty():
		_error_label.text = tr("File is empty.")
		_error_label.visible = true
		return

	# Extract plugin.json manifest from the ZIP bundle
	var manifest: Dictionary = _extract_manifest(bytes)
	if manifest.is_empty():
		_error_label.text = tr(
			"Invalid plugin bundle: missing or invalid plugin.json."
		)
		_error_label.visible = true
		return

	_upload_btn.disabled = true
	_upload_btn.text = tr("Uploading...")
	_error_label.visible = false

	var conn: Dictionary = Client._connections[_conn_index]
	if conn == null or conn.get("client") == null:
		_upload_btn.disabled = false
		_upload_btn.text = tr("Upload Plugin")
		_error_label.text = tr("Not connected.")
		_error_label.visible = true
		return

	var client: AccordClient = conn["client"]
	var result: RestResult = await client.plugins.install_plugin(
		_space_id, manifest, bytes, path.get_file()
	)

	_upload_btn.disabled = false
	_upload_btn.text = tr("Upload Plugin")

	if result == null or not result.ok:
		var err_msg: String = tr("Failed to install plugin")
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return
	if result.data != null:
		_all_plugins.append(result.data.to_dict())
		_rebuild_list()


func _extract_manifest(zip_bytes: PackedByteArray) -> Dictionary:
	var tmp_path: String = "user://tmp_plugin_upload.zip"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_buffer(zip_bytes)
	f.close()
	var reader := ZIPReader.new()
	var err: Error = reader.open(tmp_path)
	if err != OK:
		DirAccess.remove_absolute(tmp_path)
		return {}
	var files: PackedStringArray = reader.get_files()
	var manifest_path := ""
	for file in files:
		if file == "plugin.json" or file.ends_with("/plugin.json"):
			manifest_path = file
			break
	if manifest_path.is_empty():
		reader.close()
		DirAccess.remove_absolute(tmp_path)
		return {}
	var manifest_bytes: PackedByteArray = reader.read_file(
		manifest_path
	)
	reader.close()
	DirAccess.remove_absolute(tmp_path)
	if manifest_bytes.is_empty():
		return {}
	var json := JSON.new()
	var parse_err: Error = json.parse(
		manifest_bytes.get_string_from_utf8()
	)
	if parse_err != OK or not (json.data is Dictionary):
		return {}
	return json.data


func _on_delete_plugin(
	plugin_id: String, plugin_name: String,
) -> void:
	DialogHelper.confirm(ConfirmDialogScene, get_tree(),
		tr("Uninstall Plugin"),
		tr("Are you sure you want to uninstall '%s'? Any active sessions will be ended.") % plugin_name,
		tr("Uninstall"), true,
		func() -> void:
			var conn: Dictionary = Client._connections[_conn_index]
			if conn == null or conn.get("client") == null:
				return
			var client: AccordClient = conn["client"]
			var result: RestResult = await client.plugins.delete_plugin(
				_space_id, plugin_id
			)
			if result == null or not result.ok:
				var err_msg: String = tr("Failed to uninstall plugin")
				if result != null and result.error:
					err_msg = result.error.message
				_error_label.text = err_msg
				_error_label.visible = true
				return
			_all_plugins = _all_plugins.filter(
				func(p: Dictionary) -> bool:
					return str(p.get("id", "")) != plugin_id
			)
			_rebuild_list()
	)


func _on_plugins_updated() -> void:
	if _conn_index >= 0:
		_all_plugins = Client.plugins.get_plugins(_conn_index)
		_rebuild_list()
