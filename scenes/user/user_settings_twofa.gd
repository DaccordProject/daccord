class_name UserSettingsTwofa
extends RefCounted

## Builds and manages the 2FA settings page within UserSettings.

var _status_label: Label
var _enable_btn: Button
var _disable_btn: Button
var _code_input: LineEdit
var _verify_btn: Button
var _secret_label: Label
var _backup_label: Label
var _error: Label
var _pw_input: LineEdit

func build(
	page_vbox: VBoxContainer,
	section_label_fn: Callable,
	error_label_fn: Callable,
) -> void:
	_status_label = Label.new()
	_status_label.text = "Two-factor authentication is not enabled."
	page_vbox.add_child(_status_label)

	_enable_btn = Button.new()
	_enable_btn.text = "Enable 2FA"
	_enable_btn.pressed.connect(_on_enable)
	page_vbox.add_child(_enable_btn)

	_secret_label = Label.new()
	_secret_label.visible = false
	_secret_label.add_theme_font_size_override("font_size", 13)
	page_vbox.add_child(_secret_label)

	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(code_row)

	_code_input = LineEdit.new()
	_code_input.placeholder_text = "6-digit code"
	_code_input.max_length = 6
	_code_input.visible = false
	code_row.add_child(_code_input)

	_verify_btn = Button.new()
	_verify_btn.text = "Verify"
	_verify_btn.visible = false
	_verify_btn.pressed.connect(_on_verify)
	code_row.add_child(_verify_btn)

	_backup_label = Label.new()
	_backup_label.visible = false
	_backup_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_backup_label.add_theme_font_size_override("font_size", 13)
	page_vbox.add_child(_backup_label)

	page_vbox.add_child(section_label_fn.call("DISABLE 2FA"))
	_pw_input = LineEdit.new()
	_pw_input.secret = true
	_pw_input.placeholder_text = "Password"
	_pw_input.visible = false
	page_vbox.add_child(_pw_input)

	_disable_btn = Button.new()
	_disable_btn.text = "Disable 2FA"
	_disable_btn.visible = false
	_disable_btn.pressed.connect(_on_disable)
	page_vbox.add_child(_disable_btn)

	_error = error_label_fn.call()
	page_vbox.add_child(_error)

func _on_enable() -> void:
	_error.visible = false
	_enable_btn.disabled = true
	var client: AccordClient = Client._first_connected_client()
	if client == null:
		_error.text = "Not connected"
		_error.visible = true
		_enable_btn.disabled = false
		return
	var result: RestResult = await client.auth.enable_2fa({})
	_enable_btn.disabled = false
	if result.ok and result.data is Dictionary:
		var secret: String = result.data.get("secret", "")
		_secret_label.text = "Secret: " + secret
		_secret_label.visible = true
		_code_input.visible = true
		_verify_btn.visible = true
		_enable_btn.visible = false
	else:
		var err: String = (
			result.error.message if result.error else "Failed"
		)
		_error.text = err
		_error.visible = true

func _on_verify() -> void:
	_error.visible = false
	var code: String = _code_input.text.strip_edges()
	if code.length() != 6:
		_error.text = "Enter a 6-digit code"
		_error.visible = true
		return
	_verify_btn.disabled = true
	var client: AccordClient = Client._first_connected_client()
	if client == null:
		_error.text = "Not connected"
		_error.visible = true
		_verify_btn.disabled = false
		return
	var result: RestResult = await client.auth.verify_2fa(
		{"code": code}
	)
	_verify_btn.disabled = false
	if result.ok:
		_status_label.text = (
			"Two-factor authentication is enabled."
		)
		_secret_label.visible = false
		_code_input.visible = false
		_verify_btn.visible = false
		_pw_input.visible = true
		_disable_btn.visible = true
		if result.data is Dictionary:
			var codes: Array = result.data.get(
				"backup_codes", []
			)
			if codes.size() > 0:
				_backup_label.text = (
					"Backup codes (save these):\n"
					+ "\n".join(codes)
				)
				_backup_label.visible = true
	else:
		var err: String = (
			result.error.message
			if result.error else "Verification failed"
		)
		_error.text = err
		_error.visible = true

func _on_disable() -> void:
	_error.visible = false
	var pw: String = _pw_input.text
	if pw.is_empty():
		_error.text = "Password is required"
		_error.visible = true
		return
	_disable_btn.disabled = true
	var client: AccordClient = Client._first_connected_client()
	if client == null:
		_error.text = "Not connected"
		_error.visible = true
		_disable_btn.disabled = false
		return
	var result: RestResult = await client.auth.disable_2fa(
		{"password": pw}
	)
	_disable_btn.disabled = false
	if result.ok:
		_status_label.text = (
			"Two-factor authentication is not enabled."
		)
		_pw_input.visible = false
		_pw_input.text = ""
		_disable_btn.visible = false
		_enable_btn.visible = true
		_backup_label.visible = false
	else:
		var err: String = (
			result.error.message
			if result.error else "Failed to disable 2FA"
		)
		_error.text = err
		_error.visible = true
