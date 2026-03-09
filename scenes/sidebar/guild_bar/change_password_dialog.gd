extends ModalBase

## Shown when the server requires the user to change their password
## (force_password_reset flag). Blocks auth completion until resolved.

signal password_changed(new_token: String)

var _base_url: String = ""
var _token: String = ""
var _username: String = ""

@onready var _description: Label = $CenterContainer/Panel/VBox/Description
@onready var _old_input: PasswordField = $CenterContainer/Panel/VBox/OldInput
@onready var _new_input: PasswordField = $CenterContainer/Panel/VBox/NewInput
@onready var _confirm_input: PasswordField = $CenterContainer/Panel/VBox/ConfirmInput
@onready var _submit_btn: Button = $CenterContainer/Panel/VBox/SubmitButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel


func setup(base_url: String, token: String, username: String) -> void:
	_base_url = base_url
	_token = token
	_username = username


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 400, 0)
	_submit_btn.pressed.connect(_on_submit)
	_old_input.text_submitted.connect(func(_t): _new_input.grab_focus())
	_new_input.text_submitted.connect(func(_t): _confirm_input.grab_focus())
	_confirm_input.text_submitted.connect(func(_t): _on_submit())

	_description.text = "The server requires you to change your password before continuing."

	await get_tree().process_frame
	_old_input.grab_focus()


## Override _close to prevent dismissal — user must change password.
func _close() -> void:
	pass


func _gui_input(_event: InputEvent) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()


func _on_submit() -> void:
	var old_pw := _old_input.text.strip_edges()
	var new_pw := _new_input.text.strip_edges()
	var confirm := _confirm_input.text.strip_edges()

	if old_pw.is_empty():
		_show_error("Current password is required.")
		return
	if new_pw.is_empty():
		_show_error("New password is required.")
		return
	if new_pw.length() < 8:
		_show_error("New password must be at least 8 characters.")
		return
	if new_pw != confirm:
		_show_error("Passwords do not match.")
		return

	_error_label.visible = false
	_submit_btn.disabled = true
	_submit_btn.text = "Changing..."

	var api_url := _base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = _token
	rest.token_type = "Bearer"
	add_child(rest)

	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.change_password({
		"old_password": old_pw,
		"new_password": new_pw,
	})
	rest.queue_free()

	_submit_btn.disabled = false
	_submit_btn.text = "Change Password"

	if not result.ok:
		var err_msg: String = result.error.message if result.error else "Password change failed"
		_show_error(err_msg)
		return

	password_changed.emit(_token)
	queue_free()


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
