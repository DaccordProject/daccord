extends RefCounted

## Developer settings page — test API and MCP server toggles.

const SettingsBase := preload("res://scenes/user/settings_base.gd")

var _host: Control
var _page_vbox: Callable
var _section_label: Callable

# Test API controls
var _test_api_toggle: CheckButton
var _test_api_status: Label
var _test_api_port_spin: SpinBox
var _test_api_token_label: Label

# MCP controls
var _mcp_toggle: CheckButton
var _mcp_status: Label
var _mcp_port_spin: SpinBox
var _mcp_token_label: Label


func _init(
	host: Control, page_vbox: Callable, section_label: Callable,
) -> void:
	_host = host
	_page_vbox = page_vbox
	_section_label = section_label


func build() -> VBoxContainer:
	var vbox: VBoxContainer = _page_vbox.call(tr("Developer"))

	# Header
	var desc := Label.new()
	desc.text = tr(
		"Tools for testing and AI integration. "
		+ "These bind to localhost only."
	)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override(
		"font_color", ThemeManager.get_color("text_muted")
	)
	vbox.add_child(desc)

	vbox.add_child(HSeparator.new())

	# --- Test API section ---
	vbox.add_child(_section_label.call(tr("TEST API")))

	_test_api_toggle = CheckButton.new()
	_test_api_toggle.text = tr("Enable Test API")
	_test_api_toggle.button_pressed = (
		Config.developer.get_test_api_enabled()
	)
	_test_api_toggle.toggled.connect(_on_test_api_toggled)
	vbox.add_child(_test_api_toggle)

	_test_api_status = Label.new()
	ThemeManager.style_label(_test_api_status, 12, "text_muted")
	_update_test_api_status()
	vbox.add_child(_test_api_status)

	# Port
	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	var port_label := Label.new()
	port_label.text = tr("Port")
	port_row.add_child(port_label)
	_test_api_port_spin = SpinBox.new()
	_test_api_port_spin.min_value = 1024
	_test_api_port_spin.max_value = 65535
	_test_api_port_spin.step = 1
	_test_api_port_spin.value = Config.developer.get_test_api_port()
	_test_api_port_spin.value_changed.connect(
		func(val: float) -> void:
			Config.developer.set_test_api_port(int(val))
	)
	port_row.add_child(_test_api_port_spin)
	vbox.add_child(port_row)

	# Token display
	_test_api_token_label = Label.new()
	ThemeManager.style_label(_test_api_token_label, 12, "text_muted")
	_update_token_display(
		_test_api_token_label,
		Config.developer.get_test_api_token()
	)
	vbox.add_child(_test_api_token_label)

	# Token buttons
	var token_row := HBoxContainer.new()
	token_row.add_theme_constant_override("separation", 8)
	var copy_btn := SettingsBase.create_secondary_button(
		tr("Copy Token")
	)
	copy_btn.pressed.connect(func() -> void:
		var token: String = Config.developer.get_test_api_token()
		if not token.is_empty():
			DisplayServer.clipboard_set(token)
	)
	token_row.add_child(copy_btn)

	var rotate_btn := SettingsBase.create_secondary_button(
		tr("Rotate Token")
	)
	rotate_btn.pressed.connect(func() -> void:
		var new_token: String = _generate_token()
		Config.developer.set_test_api_token(new_token)
		_update_token_display(
			_test_api_token_label, new_token
		)
	)
	token_row.add_child(rotate_btn)
	vbox.add_child(token_row)

	var no_auth_note := Label.new()
	no_auth_note.text = tr(
		"No authentication required for local testing. "
		+ "Token is optional."
	)
	no_auth_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ThemeManager.style_label(no_auth_note, 11, "text_muted")
	vbox.add_child(no_auth_note)

	vbox.add_child(HSeparator.new())

	# --- MCP Server section ---
	vbox.add_child(_section_label.call(tr("MCP SERVER")))

	_mcp_toggle = CheckButton.new()
	_mcp_toggle.text = tr("Enable MCP Server")
	_mcp_toggle.button_pressed = Config.developer.get_mcp_enabled()
	_mcp_toggle.toggled.connect(_on_mcp_toggled)
	vbox.add_child(_mcp_toggle)

	_mcp_status = Label.new()
	ThemeManager.style_label(_mcp_status, 12, "text_muted")
	_update_mcp_status()
	vbox.add_child(_mcp_status)

	# MCP Port
	var mcp_port_row := HBoxContainer.new()
	mcp_port_row.add_theme_constant_override("separation", 8)
	var mcp_port_label := Label.new()
	mcp_port_label.text = tr("Port")
	mcp_port_row.add_child(mcp_port_label)
	_mcp_port_spin = SpinBox.new()
	_mcp_port_spin.min_value = 1024
	_mcp_port_spin.max_value = 65535
	_mcp_port_spin.step = 1
	_mcp_port_spin.value = Config.developer.get_mcp_port()
	_mcp_port_spin.value_changed.connect(
		func(val: float) -> void:
			Config.developer.set_mcp_port(int(val))
	)
	mcp_port_row.add_child(_mcp_port_spin)
	vbox.add_child(mcp_port_row)

	# MCP Token display
	_mcp_token_label = Label.new()
	ThemeManager.style_label(_mcp_token_label, 12, "text_muted")
	_update_token_display(
		_mcp_token_label, Config.developer.get_mcp_token()
	)
	vbox.add_child(_mcp_token_label)

	# MCP Token buttons
	var mcp_token_row := HBoxContainer.new()
	mcp_token_row.add_theme_constant_override("separation", 8)
	var mcp_copy_btn := SettingsBase.create_secondary_button(
		tr("Copy Token")
	)
	mcp_copy_btn.pressed.connect(func() -> void:
		var token: String = Config.developer.get_mcp_token()
		if not token.is_empty():
			DisplayServer.clipboard_set(token)
	)
	mcp_token_row.add_child(mcp_copy_btn)

	var mcp_rotate_btn := SettingsBase.create_secondary_button(
		tr("Rotate Token")
	)
	mcp_rotate_btn.pressed.connect(func() -> void:
		var new_token: String = _generate_token()
		Config.developer.set_mcp_token(new_token)
		_update_token_display(_mcp_token_label, new_token)
	)
	mcp_token_row.add_child(mcp_rotate_btn)
	vbox.add_child(mcp_token_row)

	# Tool groups
	vbox.add_child(_section_label.call(tr("MCP TOOL GROUPS")))
	var groups := ["read", "navigate", "screenshot", "message", "moderate", "voice"]
	var allowed: PackedStringArray = (
		Config.developer.get_mcp_allowed_groups()
	)
	for group_name in groups:
		var cb := CheckBox.new()
		cb.text = group_name
		cb.button_pressed = group_name in allowed
		cb.toggled.connect(
			_on_group_toggled.bind(group_name)
		)
		vbox.add_child(cb)

	vbox.add_child(HSeparator.new())

	# CLI override notice
	var cli_note := Label.new()
	cli_note.text = tr(
		"These can also be enabled via --test-api "
		+ "and --test-api-port flags for CI use."
	)
	cli_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ThemeManager.style_label(cli_note, 11, "text_muted")
	vbox.add_child(cli_note)

	return vbox


func _on_test_api_toggled(pressed: bool) -> void:
	Config.developer.set_test_api_enabled(pressed)
	if pressed and Config.developer.get_test_api_token().is_empty():
		var token: String = _generate_token()
		Config.developer.set_test_api_token(token)
		_update_token_display(_test_api_token_label, token)
	_update_test_api_status()


func _on_mcp_toggled(pressed: bool) -> void:
	Config.developer.set_mcp_enabled(pressed)
	if pressed and Config.developer.get_mcp_token().is_empty():
		var token: String = _generate_token()
		Config.developer.set_mcp_token(token)
		_update_token_display(_mcp_token_label, token)
	_update_mcp_status()


func _on_group_toggled(pressed: bool, group_name: String) -> void:
	var groups: PackedStringArray = (
		Config.developer.get_mcp_allowed_groups()
	)
	if pressed and group_name not in groups:
		groups.append(group_name)
	elif not pressed:
		var idx: int = groups.find(group_name)
		if idx >= 0:
			groups.remove_at(idx)
	Config.developer.set_mcp_allowed_groups(groups)


func _update_test_api_status() -> void:
	if _test_api_status == null:
		return
	if Client.test_api != null and Client.test_api.is_listening():
		_test_api_status.text = tr(
			"Listening on 127.0.0.1:%d"
		) % Config.developer.get_test_api_port()
	elif Config.developer.get_test_api_enabled():
		_test_api_status.text = tr(
			"Enabled (restart to activate)"
		)
	else:
		_test_api_status.text = tr("Stopped")


func _update_mcp_status() -> void:
	if _mcp_status == null:
		return
	if Client.mcp != null and Client.mcp.is_listening():
		_mcp_status.text = tr(
			"Listening on 127.0.0.1:%d"
		) % Config.developer.get_mcp_port()
	elif Config.developer.get_mcp_enabled():
		_mcp_status.text = tr(
			"Enabled (restart to activate)"
		)
	else:
		_mcp_status.text = tr("Stopped")


func _update_token_display(label: Label, token: String) -> void:
	if token.is_empty():
		label.text = tr("No token configured")
	elif token.length() >= 8:
		label.text = "dk_%s...%s" % [
			token.left(4), token.right(4)
		]
	else:
		label.text = "dk_%s..." % token.left(4)


func _generate_token() -> String:
	var crypto := Crypto.new()
	var bytes: PackedByteArray = crypto.generate_random_bytes(32)
	return bytes.hex_encode()
