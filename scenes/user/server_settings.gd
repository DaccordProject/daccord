extends SettingsBase

## Per-server account settings panel.
## Pages: My Account, Notifications, Change Password, Delete Account,
##        Two-Factor Auth, Connections.

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
	_server_name = space.get("name", "Server")

func _get_subtitle() -> String:
	return _server_name

func _get_modal_size() -> Vector2:
	return Vector2(780, 540)

func _get_sections() -> Array:
	return [
		"My Account", "Notifications", "Change Password",
		"Delete Account", "Two-Factor Auth", "Connections",
	]

func _build_pages() -> Array:
	return [
		_build_account_page(),
		_build_notifications_page(),
		_build_password_page(),
		_build_delete_page(),
		_build_twofa_page(),
		_build_connections_page(),
	]

# --- My Account page ---

func _build_account_page() -> VBoxContainer:
	var vbox := _page_vbox("My Account")

	var user: Dictionary = _server_user
	var username_row := _labeled_value(
		"USERNAME", user.get("username", "")
	)
	vbox.add_child(username_row)

	var created: String = user.get("created_at", "")
	if not created.is_empty():
		var t_idx := created.find("T")
		var date_str: String = created.substr(0, t_idx) if t_idx != -1 else created
		vbox.add_child(_labeled_value("ACCOUNT CREATED", date_str))

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
	var vbox := _page_vbox("Notifications")

	# Server mute toggle
	var mute_cb := CheckBox.new()
	mute_cb.text = "Mute this server"
	mute_cb.button_pressed = Config.is_server_muted(_space_id)
	mute_cb.toggled.connect(func(pressed: bool) -> void:
		Config.set_server_muted(_space_id, pressed)
	)
	vbox.add_child(mute_cb)

	# Per-server suppress @everyone override
	vbox.add_child(_section_label("SUPPRESS @EVERYONE"))
	var suppress_dropdown := OptionButton.new()
	suppress_dropdown.add_item("Use global default")
	suppress_dropdown.add_item("Suppress on this server")
	suppress_dropdown.add_item("Don't suppress on this server")
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
	var vbox := _page_vbox("Change Password")
	_danger = UserSettingsDanger.new()
	_danger.build_password_page(
		vbox, _section_label, _error_label, _accord_client,
	)
	return vbox

# --- Delete Account page ---

func _build_delete_page() -> VBoxContainer:
	var vbox := _page_vbox("Delete Account")
	if _danger == null:
		_danger = UserSettingsDanger.new()
	_danger.build_delete_page(
		vbox, _section_label, _error_label, get_tree(),
		_accord_client,
	)
	return vbox

# --- 2FA page ---

func _build_twofa_page() -> VBoxContainer:
	var vbox := _page_vbox("Two-Factor Authentication")
	_twofa = UserSettingsTwofa.new()
	_twofa.build(
		vbox, _section_label, _error_label, _accord_client,
	)
	return vbox

# --- Connections page ---

func _build_connections_page() -> VBoxContainer:
	var vbox := _page_vbox("Connections")

	var loading := Label.new()
	loading.text = "Loading connections..."
	loading.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(loading)

	_fetch_connections(vbox, loading)

	return vbox

func _fetch_connections(
	vbox: VBoxContainer, loading: Label,
) -> void:
	if _accord_client == null:
		loading.text = "Not connected"
		return
	var result: RestResult = await _accord_client.users.list_connections()
	loading.visible = false
	if not result.ok:
		var err_lbl := Label.new()
		err_lbl.text = "Failed to load connections"
		err_lbl.add_theme_color_override(
			"font_color", Color(0.929, 0.259, 0.271)
		)
		vbox.add_child(err_lbl)
		return
	var connections: Array = result.data if result.data is Array else []
	if connections.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No connections linked."
		none_lbl.add_theme_color_override(
			"font_color", Color(0.58, 0.608, 0.643)
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
				"font_color", Color(0.58, 0.608, 0.643)
			)
			row.add_child(name_lbl)
			vbox.add_child(row)
