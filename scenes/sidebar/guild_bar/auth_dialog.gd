extends ColorRect

signal auth_completed(
	base_url: String, token: String,
	username: String, password: String,
	display_name: String,
)

enum Mode { SIGN_IN, REGISTER }

var _mode: Mode = Mode.SIGN_IN
var _base_url: String = ""
var _prefill_username: String = ""
var _prev_username: String = ""

@onready var _sign_in_btn: Button = $CenterContainer/Panel/VBox/ModeToggle/SignInBtn
@onready var _register_btn: Button = $CenterContainer/Panel/VBox/ModeToggle/RegisterBtn
@onready var _username_input: LineEdit = $CenterContainer/Panel/VBox/UsernameInput
@onready var _password_input: LineEdit = $CenterContainer/Panel/VBox/PasswordRow/PasswordInput
@onready var _generate_btn: Button = $CenterContainer/Panel/VBox/PasswordRow/GenerateBtn
@onready var _view_btn: Button = $CenterContainer/Panel/VBox/PasswordRow/ViewBtn
@onready var _password_hint: Label = $CenterContainer/Panel/VBox/PasswordHint
@onready var _display_name_label: Label = $CenterContainer/Panel/VBox/DisplayNameLabel
@onready var _display_name_input: LineEdit = $CenterContainer/Panel/VBox/DisplayNameInput
@onready var _submit_btn: Button = $CenterContainer/Panel/VBox/SubmitButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel


func _ready() -> void:
	_sign_in_btn.pressed.connect(func(): _set_mode(Mode.SIGN_IN))
	_register_btn.pressed.connect(func(): _set_mode(Mode.REGISTER))
	_submit_btn.pressed.connect(_on_submit)
	_generate_btn.pressed.connect(_on_generate_password)
	_view_btn.pressed.connect(_on_toggle_password_view)
	_username_input.text_changed.connect(_on_username_changed)
	_username_input.text_submitted.connect(func(_t): _password_input.grab_focus())
	_password_input.text_submitted.connect(func(_t): _on_submit())

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

	if m == Mode.SIGN_IN:
		_sign_in_btn.disabled = true
		_register_btn.disabled = false
		_display_name_label.visible = false
		_display_name_input.visible = false
		_generate_btn.visible = false
		_view_btn.visible = false
		_password_hint.visible = false
		_password_input.secret = true
		_view_btn.text = "View"
		_submit_btn.text = "Sign In"
	else:
		_sign_in_btn.disabled = false
		_register_btn.disabled = true
		_display_name_label.visible = true
		_display_name_input.visible = true
		_generate_btn.visible = true
		_view_btn.visible = true
		_password_hint.visible = true
		_submit_btn.text = "Register"


func _on_submit() -> void:
	var username := _username_input.text.strip_edges()
	var password := _password_input.text.strip_edges()

	if username.is_empty():
		_show_error("Username is required.")
		return
	if password.is_empty():
		_show_error("Password is required.")
		return
	if _mode == Mode.REGISTER and password.length() < 8:
		_show_error("Password must be at least 8 characters.")
		return

	_error_label.visible = false
	_submit_btn.disabled = true
	_submit_btn.text = "Connecting..."

	var result := await _try_auth(username, password)

	# HTTPS connection-level failure -- prompt user before downgrading to HTTP
	if not result.ok and result.status_code == 0 and _base_url.begins_with("https://"):
		var http_url := _base_url.replace("https://", "http://")
		var confirmed := await _show_http_warning(http_url)
		if confirmed:
			_base_url = http_url
			result = await _try_auth(username, password)
		# If not confirmed, fall through to the error handler below

	_submit_btn.disabled = false
	_submit_btn.text = "Sign In" if _mode == Mode.SIGN_IN else "Register"

	if not result.ok:
		var err_msg: String = result.error.message if result.error else "Authentication failed"
		_show_error(err_msg)
		return

	var token: String = result.data.get("token", "") if result.data is Dictionary else ""
	if token.is_empty():
		_show_error("No token received from server.")
		return

	var dn := ""
	if _mode == Mode.REGISTER:
		dn = _display_name_input.text.strip_edges()
	auth_completed.emit(_base_url, token, username, password, dn)
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
	_view_btn.text = "Hide"


func _on_toggle_password_view() -> void:
	_password_input.secret = not _password_input.secret
	_view_btn.text = "View" if _password_input.secret else "Hide"


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


func _show_http_warning(http_url: String) -> bool:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = (
		"HTTPS connection failed. Do you want to connect over insecure HTTP?\n\n"
		+ "URL: %s\n\n"
		+ "WARNING: Your credentials will be sent in plaintext. "
		+ "Only use this for trusted local networks."
	) % http_url
	dialog.title = "Insecure Connection"
	dialog.ok_button_text = "Connect Anyway"
	dialog.cancel_button_text = "Cancel"
	add_child(dialog)
	dialog.popup_centered()
	var result := [false]
	dialog.confirmed.connect(func(): result[0] = true)
	dialog.canceled.connect(func(): result[0] = false)
	await dialog.visibility_changed
	dialog.queue_free()
	return result[0]


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
