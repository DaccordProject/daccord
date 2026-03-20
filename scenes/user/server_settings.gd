extends SettingsBase

## Per-server account settings panel.
## Pages: My Account, Notifications, Change Password, Delete Account,
##        Two-Factor Auth, Connections, Privacy & Data.

var _space_id: String = ""
var _accord_client: AccordClient = null
var _server_user: Dictionary = {}
var _server_name: String = ""

# Delegates
var _profile: UserSettingsProfile
var _danger: UserSettingsDanger
var _twofa: UserSettingsTwofa

func setup(space_id: String) -> void:
	_space_id = space_id
	_accord_client = Client._client_for_space(space_id)
	_server_user = Client.get_user_for_space(space_id)
	var space: Dictionary = Client.get_space_by_id(space_id)
	_server_name = space.get("name", tr("Server"))

func _get_subtitle() -> String:
	return _server_name

func _get_modal_size() -> Vector2:
	return Vector2(780, 540)

func _get_sections() -> Array:
	return [
		tr("My Account"), tr("Notifications"), tr("Change Password"),
		tr("Delete Account"), tr("Two-Factor Auth"), tr("Connections"),
		tr("Privacy & Data"),
	]

func _build_pages() -> Array:
	return [
		_build_account_page(),
		_build_notifications_page(),
		_build_password_page(),
		_build_delete_page(),
		_build_twofa_page(),
		_build_connections_page(),
		_build_privacy_page(),
	]

# --- My Account page ---

func _build_account_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("My Account"))

	var user: Dictionary = _server_user
	var username_row := _labeled_value(
		tr("USERNAME"), user.get("username", "")
	)
	vbox.add_child(username_row)

	var created: String = user.get("created_at", "")
	if not created.is_empty():
		var t_idx := created.find("T")
		var date_str: String = created.substr(0, t_idx) if t_idx != -1 else created
		vbox.add_child(_labeled_value(tr("ACCOUNT CREATED"), date_str))

	var sep := HSeparator.new()
	vbox.add_child(sep)

	# Editable profile fields (avatar, display name, bio, accent color)
	_profile = UserSettingsProfile.new()
	_profile.build(
		vbox, _section_label, _error_label, self,
		_accord_client, _server_user,
	)

	return vbox

# --- Notifications page (per-server) ---

func _build_notifications_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Notifications"))

	# Server mute toggle
	var mute_cb := CheckBox.new()
	mute_cb.text = tr("Mute this server")
	mute_cb.button_pressed = Config.is_server_muted(_space_id)
	mute_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_server_muted(_space_id, pressed)
	)
	vbox.add_child(mute_cb)

	# Per-server suppress @everyone override
	vbox.add_child(_section_label(tr("SUPPRESS @EVERYONE")))
	var suppress_dropdown := OptionButton.new()
	suppress_dropdown.add_item(tr("Use global default"))
	suppress_dropdown.add_item(tr("Suppress on this server"))
	suppress_dropdown.add_item(tr("Don't suppress on this server"))
	var current_override: int = Config.get_server_suppress_everyone(_space_id)
	match current_override:
		-1: suppress_dropdown.selected = 0
		1: suppress_dropdown.selected = 1
		0: suppress_dropdown.selected = 2
	suppress_dropdown.item_selected.connect(func(idx: int) -> void:
		var val_map := [-1, 1, 0]
		Config.set_server_suppress_everyone(_space_id, val_map[idx])
	)
	vbox.add_child(suppress_dropdown)

	return vbox

# --- Change Password page ---

func _build_password_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Change Password"))
	_danger = UserSettingsDanger.new()
	_danger.build_password_page(
		vbox, _section_label, _error_label, _accord_client,
	)
	return vbox

# --- Delete Account page ---

func _build_delete_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Delete Account"))
	if _danger == null:
		_danger = UserSettingsDanger.new()
	_danger.build_delete_page(
		vbox, _section_label, _error_label, get_tree(),
		_accord_client,
	)
	return vbox

# --- 2FA page ---

func _build_twofa_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Two-Factor Authentication"))
	_twofa = UserSettingsTwofa.new()
	_twofa.build(
		vbox, _section_label, _error_label, _accord_client,
		_server_user,
	)
	return vbox

# --- Connections page ---

func _build_connections_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Connections"))

	var loading := Label.new()
	loading.text = tr("Loading connections...")
	loading.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(loading)

	_fetch_connections(vbox, loading)

	return vbox

func _fetch_connections(
	vbox: VBoxContainer, loading: Label,
) -> void:
	if _accord_client == null:
		loading.text = tr("Not connected")
		return
	var result: RestResult = await _accord_client.users.list_connections()
	loading.visible = false
	if not result.ok:
		var err_lbl := Label.new()
		err_lbl.text = tr("Failed to load connections")
		err_lbl.add_theme_color_override(
			"font_color", ThemeManager.get_color("error")
		)
		vbox.add_child(err_lbl)
		return
	var connections: Array = result.data if result.data is Array else []
	if connections.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = tr("No connections linked.")
		none_lbl.add_theme_color_override(
			"font_color", ThemeManager.get_color("text_muted")
		)
		vbox.add_child(none_lbl)
		return
	for conn in connections:
		if conn is Dictionary:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			var service := Label.new()
			service.text = str(conn.get("type", "Unknown"))
			service.add_theme_font_size_override("font_size", 14)
			row.add_child(service)
			var name_lbl := Label.new()
			name_lbl.text = str(conn.get("name", ""))
			name_lbl.add_theme_color_override(
				"font_color", ThemeManager.get_color("text_muted")
			)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name_lbl)
			var disconnect_btn := SettingsBase.create_danger_button(
				tr("Disconnect")
			)
			var conn_id: String = str(conn.get("id", ""))
			disconnect_btn.pressed.connect(
				_on_disconnect_connection.bind(conn_id, row)
			)
			row.add_child(disconnect_btn)
			vbox.add_child(row)

func _on_disconnect_connection(
	conn_id: String, row: HBoxContainer,
) -> void:
	if _accord_client == null or conn_id.is_empty():
		return
	var result: RestResult = await _accord_client.rest.make_request(
		"DELETE", "/users/@me/connections/" + conn_id
	)
	if result.ok:
		row.queue_free()

# --- Privacy & Data page ---

func _build_privacy_page() -> VBoxContainer:
	var vbox := _page_vbox(tr("Privacy & Data"))

	# Data export section
	vbox.add_child(_section_label(tr("DATA EXPORT")))
	var export_desc := Label.new()
	export_desc.text = tr(
		"Download a copy of your personal data stored on this "
		+ "server, including your profile, messages, and "
		+ "relationships. The export is provided as a JSON file."
	)
	export_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	export_desc.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(export_desc)

	var export_btn := SettingsBase.create_action_button(
		tr("Request Data Export")
	)
	var export_status := Label.new()
	export_status.visible = false
	export_btn.pressed.connect(
		_on_request_data_export.bind(export_btn, export_status)
	)
	vbox.add_child(export_btn)
	vbox.add_child(export_status)

	vbox.add_child(HSeparator.new())

	# Data deletion info
	vbox.add_child(_section_label(tr("DATA DELETION")))
	var delete_desc := Label.new()
	delete_desc.text = tr(
		"When you delete your account, all personal data is "
		+ "permanently removed from the server. This includes your "
		+ "profile, messages, reactions, memberships, tokens, and "
		+ "applications. This action cannot be undone."
	)
	delete_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	delete_desc.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(delete_desc)

	vbox.add_child(HSeparator.new())

	# Data retention info
	vbox.add_child(_section_label(tr("DATA RETENTION")))
	var retention_desc := Label.new()
	retention_desc.text = tr(
		"Data is retained for as long as your account exists. "
		+ "There is no automatic expiration of messages or "
		+ "attachments. Server administrators may configure "
		+ "their own retention policies."
	)
	retention_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	retention_desc.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(retention_desc)

	return vbox

func _on_request_data_export(
	btn: Button, status_label: Label,
) -> void:
	if _accord_client == null:
		return
	btn.disabled = true
	btn.text = tr("Exporting...")
	status_label.visible = false

	var result: RestResult = await _accord_client.users.request_data_export()
	if not result.ok:
		btn.disabled = false
		btn.text = tr("Request Data Export")
		status_label.text = tr("Export failed. Please try again.")
		status_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("error")
		)
		status_label.visible = true
		return

	# Open save dialog for the JSON export
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; JSON files"])
	dialog.current_file = "daccord-data-export.json"
	add_child(dialog)
	dialog.popup_centered(Vector2i(600, 400))

	var path: String = await dialog.file_selected
	dialog.queue_free()

	if path.is_empty():
		btn.disabled = false
		btn.text = tr("Request Data Export")
		return

	# Write the export data to the chosen file
	var json_str: String = JSON.stringify(result.data, "\t")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		status_label.text = tr("Failed to write file.")
		status_label.add_theme_color_override(
			"font_color", ThemeManager.get_color("error")
		)
		status_label.visible = true
		btn.disabled = false
		btn.text = tr("Request Data Export")
		return

	file.store_string(json_str)
	file.close()

	status_label.text = tr("Data exported successfully.")
	status_label.add_theme_color_override(
		"font_color", ThemeManager.get_color("success")
	)
	status_label.visible = true
	btn.disabled = false
	btn.text = tr("Request Data Export")
