extends ColorRect

signal profile_created(slug: String)

@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _password_input: LineEdit = $CenterContainer/Panel/VBox/PasswordInput
@onready var _confirm_input: LineEdit = $CenterContainer/Panel/VBox/ConfirmInput
@onready var _confirm_label: Label = $CenterContainer/Panel/VBox/ConfirmLabel
@onready var _scratch_radio: CheckBox = $CenterContainer/Panel/VBox/ScratchRadio
@onready var _copy_radio: CheckBox = $CenterContainer/Panel/VBox/CopyRadio
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/CreateButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel


func _ready() -> void:
	_password_input.text_changed.connect(_on_password_changed)
	_scratch_radio.pressed.connect(func() -> void:
		_copy_radio.button_pressed = false
	)
	_copy_radio.pressed.connect(func() -> void:
		_scratch_radio.button_pressed = false
	)
	_create_btn.pressed.connect(_on_create)
	_name_input.text_submitted.connect(func(_t: String) -> void:
		_password_input.grab_focus()
	)

	await get_tree().process_frame
	_name_input.grab_focus()


func _on_password_changed(new_text: String) -> void:
	var has_pw: bool = not new_text.strip_edges().is_empty()
	_confirm_label.visible = has_pw
	_confirm_input.visible = has_pw


func _on_create() -> void:
	var pname := _name_input.text.strip_edges()
	if pname.is_empty():
		_show_error("Profile name is required.")
		return
	if pname.length() > 32:
		_show_error("Name must be 32 characters or less.")
		return

	var pw := _password_input.text.strip_edges()
	if not pw.is_empty():
		var confirm := _confirm_input.text.strip_edges()
		if pw != confirm:
			_show_error("Passwords do not match.")
			return

	var copy: bool = _copy_radio.button_pressed
	var slug: String = Config.profiles.create(pname, pw, copy)
	profile_created.emit(slug)
	queue_free()


func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
