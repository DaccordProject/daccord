extends ModalBase

const PasswordField = preload("res://scenes/user/password_field.gd")

var _user_id: String = ""

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _description: Label = $CenterContainer/Panel/VBox/Description
@onready var _password_input: PasswordField = $CenterContainer/Panel/VBox/PasswordInput
@onready var _submit_btn: Button = $CenterContainer/Panel/VBox/SubmitButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 400, 0)
	_close_btn.pressed.connect(_close)
	_submit_btn.pressed.connect(_on_submit)
	_password_input.text_submitted.connect(func(_t: String): _on_submit())

	await get_tree().process_frame
	_password_input.grab_focus()

func setup(user_id: String, display_name: String) -> void:
	_user_id = user_id
	if _title_label:
		_title_label.text = tr("Reset Password")
	if _description:
		_description.text = (
			tr("Set a temporary password for '%s'.") % display_name
			+ "\n" + tr("This will revoke all their sessions and disable 2FA. ")
			+ tr("They will be required to change their password on next login.")
		)

func _on_submit() -> void:
	var pw := _password_input.text.strip_edges()

	if pw.length() < 8:
		_show_error(tr("Password must be at least 8 characters."))
		return
	if pw.length() > 128:
		_show_error(tr("Password must be at most 128 characters."))
		return

	_error_label.visible = false
	var result: RestResult = await _with_button_loading(
		_submit_btn, tr("Reset Password"),
		func() -> RestResult:
			return await Client.admin.reset_user_password(
				_user_id, pw
			)
	)

	if not _show_rest_error(result, tr("Failed to reset password")):
		_close()

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
