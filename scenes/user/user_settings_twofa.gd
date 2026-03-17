class_name UserSettingsTwofa
extends RefCounted

## Builds and manages the 2FA settings page within UserSettings.

var _status_label: Label
var _enable_btn: Button
var _disable_btn: Button
var _enable_pw_input: LineEdit
var _code_input: LineEdit
var _verify_btn: Button
var _secret_label: Label
var _secret_copy_btn: Button
var _uri_label: Label
var _uri_copy_btn: Button
var _backup_label: Label
var _backup_copy_btn: Button
var _show_backup_btn: Button
var _backup_pw_input: LineEdit
var _error: Label
var _pw_input: LineEdit
var _accord_client: AccordClient = null

func build(
	page_vbox: VBoxContainer,
	section_label_fn: Callable,
	error_label_fn: Callable,
	accord_client: AccordClient = null,
	user: Dictionary = {},
) -> void:
	_accord_client = accord_client
	_status_label = Label.new()
	_status_label.text = tr("Two-factor authentication is not enabled.")
	page_vbox.add_child(_status_label)

	# Enable section: password + button
	_enable_pw_input = LineEdit.new()
	_enable_pw_input.secret = true
	_enable_pw_input.placeholder_text = tr("Password (required to enable)")
	page_vbox.add_child(_enable_pw_input)

	_enable_btn = SettingsBase.create_action_button(tr("Enable 2FA"))
	_enable_btn.pressed.connect(_on_enable)
	page_vbox.add_child(_enable_btn)

	var secret_row := HBoxContainer.new()
	secret_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(secret_row)

	_secret_label = Label.new()
	_secret_label.visible = false
	_secret_label.add_theme_font_size_override("font_size", 13)
	secret_row.add_child(_secret_label)

	_secret_copy_btn = SettingsBase.create_secondary_button(tr("Copy"))
	_secret_copy_btn.visible = false
	_secret_copy_btn.pressed.connect(_on_copy_secret)
	secret_row.add_child(_secret_copy_btn)

	var uri_row := HBoxContainer.new()
	uri_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(uri_row)

	_uri_label = Label.new()
	_uri_label.visible = false
	_uri_label.add_theme_font_size_override("font_size", 11)
	_uri_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	uri_row.add_child(_uri_label)

	_uri_copy_btn = SettingsBase.create_secondary_button(tr("Copy URI"))
	_uri_copy_btn.visible = false
	_uri_copy_btn.pressed.connect(_on_copy_uri)
	uri_row.add_child(_uri_copy_btn)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(code_row)

	_code_input = LineEdit.new()
	_code_input.placeholder_text = tr("6-digit code")
	_code_input.max_length = 6
	_code_input.visible = false
	code_row.add_child(_code_input)

	_verify_btn = SettingsBase.create_action_button(tr("Verify"))
	_verify_btn.visible = false
	_verify_btn.pressed.connect(_on_verify)
	code_row.add_child(_verify_btn)

	var backup_row := HBoxContainer.new()
	backup_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(backup_row)

	_backup_label = Label.new()
	_backup_label.visible = false
	_backup_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_backup_label.add_theme_font_size_override("font_size", 13)
	backup_row.add_child(_backup_label)

	_backup_copy_btn = SettingsBase.create_secondary_button(tr("Copy"))
	_backup_copy_btn.visible = false
	_backup_copy_btn.pressed.connect(_on_copy_backup)
	backup_row.add_child(_backup_copy_btn)

	# Regenerate backup codes section
	_backup_pw_input = LineEdit.new()
	_backup_pw_input.secret = true
	_backup_pw_input.placeholder_text = tr("Password (to regenerate codes)")
	_backup_pw_input.visible = false
	page_vbox.add_child(_backup_pw_input)

	_show_backup_btn = SettingsBase.create_secondary_button(
		tr("Regenerate Backup Codes")
	)
	_show_backup_btn.visible = false
	_show_backup_btn.pressed.connect(_on_show_backup)
	page_vbox.add_child(_show_backup_btn)

	page_vbox.add_child(section_label_fn.call(tr("DISABLE 2FA")))
	_pw_input = LineEdit.new()
	_pw_input.secret = true
	_pw_input.placeholder_text = tr("Password")
	_pw_input.visible = false
	page_vbox.add_child(_pw_input)

	_disable_btn = SettingsBase.create_danger_button(tr("Disable 2FA"))
	_disable_btn.visible = false
	_disable_btn.pressed.connect(_on_disable)
	page_vbox.add_child(_disable_btn)

	_error = error_label_fn.call()
	page_vbox.add_child(_error)

	# Check initial 2FA status from user data
	if user.get("mfa_enabled", false):
		_show_enabled_state()
	# Refresh from server to get authoritative status
	_refresh_mfa_status()

func _refresh_mfa_status() -> void:
	var client: AccordClient = _get_client()
	if client == null:
		return
	var result: RestResult = await client.users.get_me()
	if not result.ok:
		return
	if not result.data is AccordUser:
		return
	var fetched_user: AccordUser = result.data
	if fetched_user.mfa_enabled:
		_show_enabled_state()
	else:
		_show_disabled_state()

func _show_enabled_state() -> void:
	_status_label.text = tr("Two-factor authentication is enabled.")
	_enable_btn.visible = false
	_enable_pw_input.visible = false
	_pw_input.visible = true
	_disable_btn.visible = true
	_backup_pw_input.visible = true
	_show_backup_btn.visible = true

func _show_disabled_state() -> void:
	_status_label.text = tr("Two-factor authentication is not enabled.")
	_enable_btn.visible = true
	_enable_pw_input.visible = true
	_enable_pw_input.text = ""
	_pw_input.visible = false
	_pw_input.text = ""
	_disable_btn.visible = false
	_backup_pw_input.visible = false
	_backup_pw_input.text = ""
	_show_backup_btn.visible = false
	_backup_label.visible = false
	_backup_copy_btn.visible = false

func _get_client() -> AccordClient:
	if _accord_client != null:
		return _accord_client
	return Client._first_connected_client()

func _on_enable() -> void:
	_error.visible = false
	var pw: String = _enable_pw_input.text
	if pw.is_empty():
		_error.text = tr("Password is required")
		_error.visible = true
		return
	_enable_btn.disabled = true
	var client: AccordClient = _get_client()
	if client == null:
		_error.text = tr("Not connected")
		_error.visible = true
		_enable_btn.disabled = false
		return
	var result: RestResult = await client.auth.enable_2fa(
		{"password": pw}
	)
	_enable_btn.disabled = false
	if result.ok and result.data is Dictionary:
		var secret: String = result.data.get("secret", "")
		_secret_label.text = tr("Secret: %s") % secret
		_secret_label.visible = true
		_secret_copy_btn.visible = true
		var uri: String = result.data.get("otpauth_uri", "")
		if not uri.is_empty():
			_uri_label.text = tr("OTP URI: %s") % uri
			_uri_label.visible = true
			_uri_copy_btn.visible = true
		_code_input.visible = true
		_verify_btn.visible = true
		_enable_btn.visible = false
		_enable_pw_input.visible = false
	else:
		var err: String = (
			result.error.message if result.error else tr("Failed")
		)
		_error.text = err
		_error.visible = true

func _on_verify() -> void:
	_error.visible = false
	var code: String = _code_input.text.strip_edges()
	if code.length() != 6:
		_error.text = tr("Enter a 6-digit code")
		_error.visible = true
		return
	_verify_btn.disabled = true
	var client: AccordClient = _get_client()
	if client == null:
		_error.text = tr("Not connected")
		_error.visible = true
		_verify_btn.disabled = false
		return
	var result: RestResult = await client.auth.verify_2fa(
		{"code": code}
	)
	_verify_btn.disabled = false
	if result.ok:
		_secret_label.visible = false
		_secret_copy_btn.visible = false
		_uri_label.visible = false
		_uri_copy_btn.visible = false
		_code_input.visible = false
		_verify_btn.visible = false
		_show_enabled_state()
		if result.data is Dictionary:
			var codes: Array = result.data.get(
				"backup_codes", []
			)
			if codes.size() > 0:
				_display_backup_codes(codes)
	else:
		var err: String = (
			result.error.message
			if result.error else tr("Verification failed")
		)
		_error.text = err
		_error.visible = true

func _on_disable() -> void:
	_error.visible = false
	var pw: String = _pw_input.text
	if pw.is_empty():
		_error.text = tr("Password is required")
		_error.visible = true
		return
	_disable_btn.disabled = true
	var client: AccordClient = _get_client()
	if client == null:
		_error.text = tr("Not connected")
		_error.visible = true
		_disable_btn.disabled = false
		return
	var result: RestResult = await client.auth.disable_2fa(
		{"password": pw}
	)
	_disable_btn.disabled = false
	if result.ok:
		_show_disabled_state()
	else:
		var err: String = (
			result.error.message
			if result.error else tr("Failed to disable 2FA")
		)
		_error.text = err
		_error.visible = true

func _on_show_backup() -> void:
	_error.visible = false
	var pw: String = _backup_pw_input.text
	if pw.is_empty():
		_error.text = tr("Password is required to regenerate codes")
		_error.visible = true
		return
	_show_backup_btn.disabled = true
	var client: AccordClient = _get_client()
	if client == null:
		_error.text = tr("Not connected")
		_error.visible = true
		_show_backup_btn.disabled = false
		return
	var result: RestResult = await client.auth.regenerate_backup_codes(
		{"password": pw}
	)
	_show_backup_btn.disabled = false
	if result.ok and result.data is Dictionary:
		var codes: Array = result.data.get("backup_codes", [])
		if codes.size() > 0:
			_display_backup_codes(codes)
		else:
			_error.text = tr("No backup codes available")
			_error.visible = true
		_backup_pw_input.text = ""
	else:
		var err: String = (
			result.error.message
			if result.error else tr("Failed to regenerate backup codes")
		)
		_error.text = err
		_error.visible = true

func _display_backup_codes(codes: Array) -> void:
	_backup_label.text = (
		tr("Backup codes (save these):") + "\n"
		+ "\n".join(codes)
	)
	_backup_label.visible = true
	_backup_copy_btn.visible = true

func _on_copy_secret() -> void:
	var text: String = _secret_label.text
	var prefix: String = tr("Secret: %s") % ""
	if text.begins_with(prefix):
		text = text.substr(prefix.length())
	DisplayServer.clipboard_set(text)

func _on_copy_uri() -> void:
	var text: String = _uri_label.text
	var prefix: String = tr("OTP URI: %s") % ""
	if text.begins_with(prefix):
		text = text.substr(prefix.length())
	DisplayServer.clipboard_set(text)

func _on_copy_backup() -> void:
	var text: String = _backup_label.text
	var prefix: String = tr("Backup codes (save these):") + "\n"
	if text.begins_with(prefix):
		text = text.substr(prefix.length())
	DisplayServer.clipboard_set(text)
