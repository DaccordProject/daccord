extends ColorRect

signal password_verified(slug: String)

var _slug: String = ""

@onready var _profile_label: Label = $CenterContainer/Panel/VBox/ProfileLabel
@onready var _password_input: LineEdit = $CenterContainer/Panel/VBox/PasswordInput
@onready var _unlock_btn: Button = $CenterContainer/Panel/VBox/UnlockButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel


func setup(slug: String, profile_name: String) -> void:
	_slug = slug
	if is_inside_tree():
		_profile_label.text = "Unlock \"%s\"" % profile_name


func _ready() -> void:
	_unlock_btn.pressed.connect(_on_unlock)
	_password_input.text_submitted.connect(func(_t: String) -> void:
		_on_unlock()
	)

	await get_tree().process_frame
	_password_input.grab_focus()

	# Apply deferred setup values
	if not _slug.is_empty() and _profile_label != null:
		pass # setup() already ran before _ready if called after add_child


func _on_unlock() -> void:
	var pw := _password_input.text.strip_edges()
	if pw.is_empty():
		_show_error("Password is required.")
		return
	if Config.profiles.verify_password(_slug, pw):
		password_verified.emit(_slug)
		queue_free()
	else:
		_show_error("Incorrect password.")
		_password_input.text = ""


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
