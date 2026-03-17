extends ModalBase

signal auth_completed(
	base_url: String, token: String,
	username: String, password: String,
	display_name: String,
)
signal guest_requested(base_url: String)

enum Mode { SIGN_IN, REGISTER }

const ChangePasswordDialogScene := preload(
	"res://scenes/sidebar/guild_bar/change_password_dialog.tscn"
)
const PasswordField = preload("res://scenes/user/password_field.gd")

var _mode: Mode = Mode.SIGN_IN
var _base_url: String = ""
var _prefill_username: String = ""
var _prev_username: String = ""
var _mfa_ticket: String = ""
var _tos_enabled: bool = false
var _tos_text: String = ""
var _tos_url: String = ""
var _tos_version: int = 0
var _tos_checkbox: CheckBox
var _tos_link_btn: Button

@onready var _sign_in_btn: Button = $CenterContainer/Panel/VBox/ModeToggle/SignInBtn
@onready var _register_btn: Button = $CenterContainer/Panel/VBox/ModeToggle/RegisterBtn
@onready var _username_input: LineEdit = $CenterContainer/Panel/VBox/UsernameInput
@onready var _password_input: PasswordField = $CenterContainer/Panel/VBox/PasswordRow/PasswordInput
@onready var _generate_btn: Button = $CenterContainer/Panel/VBox/PasswordRow/GenerateBtn
@onready var _password_hint: Label = $CenterContainer/Panel/VBox/PasswordHint
@onready var _display_name_label: Label = $CenterContainer/Panel/VBox/DisplayNameLabel
@onready var _display_name_input: LineEdit = $CenterContainer/Panel/VBox/DisplayNameInput
@onready var _mfa_label: Label = $CenterContainer/Panel/VBox/MfaLabel
@onready var _mfa_input: LineEdit = $CenterContainer/Panel/VBox/MfaInput
@onready var _submit_btn: Button = $CenterContainer/Panel/VBox/SubmitButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _guest_btn: Button = $CenterContainer/Panel/VBox/GuestButton


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 400, 0)
	_sign_in_btn.pressed.connect(func(): _set_mode(Mode.SIGN_IN))
	_register_btn.pressed.connect(func(): _set_mode(Mode.REGISTER))
	_submit_btn.pressed.connect(_on_submit)
	_generate_btn.pressed.connect(_on_generate_password)
	_username_input.text_changed.connect(_on_username_changed)
	_username_input.text_submitted.connect(func(_t): _password_input.grab_focus())
	_password_input.text_submitted.connect(func(_t): _on_submit())
	_mfa_input.text_submitted.connect(func(_t): _on_submit())
	_guest_btn.pressed.connect(_on_guest_pressed)

	# ToS checkbox (built programmatically, hidden until settings fetched)
	var tos_row := HBoxContainer.new()
	tos_row.name = "TosRow"
	tos_row.add_theme_constant_override("separation", 4)
	_tos_checkbox = CheckBox.new()
	_tos_checkbox.text = tr("I agree to the ")
	_tos_checkbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tos_row.add_child(_tos_checkbox)
	_tos_link_btn = Button.new()
	_tos_link_btn.text = tr("Terms of Service")
	_tos_link_btn.flat = true
	_tos_link_btn.add_theme_color_override(
		"font_color", ThemeManager.get_color("link")
	)
	_tos_link_btn.add_theme_color_override(
		"font_hover_color", ThemeManager.get_color("link")
	)
	_tos_link_btn.pressed.connect(_on_tos_link_pressed)
	tos_row.add_child(_tos_link_btn)
	var vbox: VBoxContainer = $CenterContainer/Panel/VBox
	# Insert before SubmitButton
	vbox.add_child(tos_row)
	vbox.move_child(tos_row, _submit_btn.get_index())
	tos_row.visible = false

	_set_mode(Mode.SIGN_IN)

	if not _prefill_username.is_empty():
		_username_input.text = _prefill_username
		_prev_username = _prefill_username

	await get_tree().process_frame
	if not _prefill_username.is_empty():
		_password_input.grab_focus()
	else:
		_username_input.grab_focus()


func setup(base_url: String, prefill_username: String = "") -> void:
	_base_url = base_url
	_prefill_username = prefill_username


func _set_mode(m: Mode) -> void:
	_mode = m
	_error_label.visible = false
	_mfa_ticket = ""
	_exit_mfa_mode()

	if m == Mode.SIGN_IN:
		_sign_in_btn.disabled = true
		_register_btn.disabled = false
		_display_name_label.visible = false
		_display_name_input.visible = false
		_generate_btn.visible = false
		_password_hint.visible = false
		_password_input.secret = true
		_submit_btn.text = tr("Sign In")
		_tos_checkbox.get_parent().visible = false
	else:
		_sign_in_btn.disabled = false
		_register_btn.disabled = true
		_display_name_label.visible = true
		_display_name_input.visible = true
		_generate_btn.visible = true
		_password_hint.visible = true
		_submit_btn.text = tr("Register")
		_tos_checkbox.get_parent().visible = _tos_enabled
		_tos_checkbox.button_pressed = false
		if not _tos_enabled and _tos_version == 0:
			_fetch_tos_settings()


func _enter_mfa_mode() -> void:
	_mfa_label.visible = true
	_mfa_input.visible = true
	_mfa_input.text = ""
	_submit_btn.text = tr("Verify")
	_mfa_input.grab_focus()


func _exit_mfa_mode() -> void:
	_mfa_label.visible = false
	_mfa_input.visible = false
	_mfa_input.text = ""


func _on_submit() -> void:
	# MFA step
	if not _mfa_ticket.is_empty():
		_on_submit_mfa()
		return

	var username := _username_input.text.strip_edges()
	var password := _password_input.text.strip_edges()

	var validation_error := _validate_credentials(username, password)
	if not validation_error.is_empty():
		_show_error(validation_error)
		return

	_error_label.visible = false
	_submit_btn.disabled = true
	_submit_btn.text = tr("Connecting...")

	var result := await _try_auth(username, password)

	_submit_btn.disabled = false
	_submit_btn.text = tr("Sign In") if _mode == Mode.SIGN_IN else tr("Register")

	if not result.ok:
		var err_msg: String = result.error.message if result.error else tr("Authentication failed")
		_show_error(err_msg)
		return

	if not result.data is Dictionary:
		_show_error(tr("Unexpected response from server."))
		return

	_handle_auth_result(result, username)


func _validate_credentials(username: String, password: String) -> String:
	if username.is_empty():
		return tr("Username is required.")
	if password.is_empty():
		return tr("Password is required.")
	if _mode == Mode.REGISTER and password.length() < 8:
		return tr("Password must be at least 8 characters.")
	if _mode == Mode.REGISTER and _tos_enabled and not _tos_checkbox.button_pressed:
		return tr("You must accept the Terms of Service.")
	return ""


func _handle_auth_result(result: RestResult, username: String) -> void:
	# Check if MFA is required
	if result.data.get("mfa_required", false):
		_mfa_ticket = result.data.get("ticket", "")
		if _mfa_ticket.is_empty():
			_show_error(tr("Server requires 2FA but sent no ticket."))
			return
		_enter_mfa_mode()
		return

	var token: String = result.data.get("token", "")
	if token.is_empty():
		_show_error(tr("No token received from server."))
		return

	# Check if the server requires a password change before continuing
	if result.data.get("force_password_reset", false):
		_show_change_password_dialog(token, username)
		return

	var dn := ""
	if _mode == Mode.REGISTER:
		dn = _display_name_input.text.strip_edges()
	auth_completed.emit(
		_base_url, token, username,
		_password_input.text.strip_edges(), dn,
	)
	queue_free()


func _on_submit_mfa() -> void:
	var code := _mfa_input.text.strip_edges()
	if code.is_empty():
		_show_error(tr("Enter your 2FA code."))
		return

	_error_label.visible = false
	_submit_btn.disabled = true
	_submit_btn.text = tr("Verifying...")

	var api_url := _base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	add_child(rest)

	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.login_mfa({
		"ticket": _mfa_ticket, "code": code,
	})
	rest.queue_free()

	_submit_btn.disabled = false
	_submit_btn.text = tr("Verify")

	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error else tr("MFA verification failed")
		)
		_show_error(err_msg)
		return

	var token: String = (
		result.data.get("token", "")
		if result.data is Dictionary else ""
	)
	if token.is_empty():
		_show_error(tr("No token received from server."))
		return

	# Check if the server requires a password change after MFA
	var force_reset: bool = (
		result.data.get("force_password_reset", false)
		if result.data is Dictionary else false
	)
	var username := _username_input.text.strip_edges()
	if force_reset:
		_show_change_password_dialog(token, username)
		return

	auth_completed.emit(
		_base_url, token, username,
		_password_input.text.strip_edges(), "",
	)
	queue_free()


func _on_generate_password() -> void:
	const CHARS := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%&*"
	# Use CSPRNG for password generation (minor modular bias from byte % length is acceptable)
	var random_bytes := Crypto.new().generate_random_bytes(12)
	var password := ""
	for i in 12:
		password += CHARS[random_bytes[i] % CHARS.length()]
	_password_input.text = password
	_password_input.secret = false


func _on_username_changed(new_text: String) -> void:
	var display := _display_name_input.text.strip_edges()
	if display.is_empty() or display == _prev_username:
		_display_name_input.text = new_text.strip_edges()
	_prev_username = new_text.strip_edges()


func _try_auth(username: String, password: String) -> RestResult:
	var api_url := _base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	add_child(rest)

	var auth: AuthApi = AuthApi.new(rest)
	var result: RestResult

	if _mode == Mode.SIGN_IN:
		result = await auth.login({"username": username, "password": password})
	else:
		var display_name := _display_name_input.text.strip_edges()
		if display_name.is_empty():
			display_name = username
		var data := {"username": username, "password": password, "display_name": display_name}
		result = await auth.register(data)

	rest.queue_free()
	return result


func _show_change_password_dialog(token: String, username: String) -> void:
	var dialog: Node = ChangePasswordDialogScene.instantiate()
	dialog.setup(_base_url, token, username)
	dialog.password_changed.connect(func(t: String):
		auth_completed.emit(
			_base_url, t, username,
			"", "",
		)
		queue_free()
	)
	get_parent().add_child(dialog)


func _on_guest_pressed() -> void:
	_error_label.visible = false
	_guest_btn.disabled = true
	_guest_btn.text = tr("Connecting...")

	var api_url := _base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	add_child(rest)

	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.guest()
	rest.queue_free()

	_guest_btn.disabled = false
	_guest_btn.text = tr("Browse without account")

	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error else tr("Guest access not available")
		)
		_show_error(err_msg)
		return

	if not result.data is Dictionary:
		_show_error(tr("Unexpected response from server."))
		return

	guest_requested.emit(_base_url)
	queue_free()


func _fetch_tos_settings() -> void:
	if _base_url.is_empty():
		return
	var api_url := _base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	add_child(rest)
	var result: RestResult = await rest.make_request("GET", "/settings")
	rest.queue_free()
	if result == null or not result.ok:
		return
	var data: Dictionary = result.data if result.data is Dictionary else {}
	var settings: Dictionary = data.get("data", data)
	_tos_enabled = settings.get("tos_enabled", false)
	_tos_text = settings.get("tos_text", "")
	_tos_version = settings.get("tos_version", 0)
	_tos_url = settings.get("tos_url", "")
	if _mode == Mode.REGISTER:
		_tos_checkbox.get_parent().visible = _tos_enabled


func _on_tos_link_pressed() -> void:
	if not _tos_url.is_empty():
		OS.shell_open(_tos_url)
		return
	if _tos_text.is_empty():
		return
	# Show inline ToS dialog
	var dialog := AcceptDialog.new()
	dialog.title = tr("Terms of Service")
	dialog.dialog_text = _tos_text
	dialog.dialog_autowrap = true
	dialog.min_size = Vector2i(500, 400)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
