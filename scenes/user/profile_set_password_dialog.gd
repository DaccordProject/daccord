extends ColorRect

var _slug: String = ""
var _has_existing_pw: bool = false

@onready var _current_label: Label = $CenterContainer/Panel/VBox/CurrentLabel
@onready var _current_input: LineEdit = $CenterContainer/Panel/VBox/CurrentInput
@onready var _new_input: LineEdit = $CenterContainer/Panel/VBox/NewInput
@onready var _confirm_input: LineEdit = $CenterContainer/Panel/VBox/ConfirmInput
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/SaveButton
@onready var _remove_btn: Button = $CenterContainer/Panel/VBox/RemoveButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel


func setup(slug: String, has_password: bool) -> void:
	_slug = slug
	_has_existing_pw = has_password


func _ready() -> void:
	_save_btn.pressed.connect(_on_save)
	_remove_btn.pressed.connect(_on_remove)

	# Show/hide current password field based on whether one exists
	_current_label.visible = _has_existing_pw
	_current_input.visible = _has_existing_pw
	_remove_btn.visible = _has_existing_pw

	await get_tree().process_frame
	if _has_existing_pw:
		_current_input.grab_focus()
	else:
		_new_input.grab_focus()


func _on_save() -> void:
	var old_pw := ""
	if _has_existing_pw:
		old_pw = _current_input.text.strip_edges()
		if old_pw.is_empty():
			_show_error("Current password is required.")
			return

	var new_pw := _new_input.text.strip_edges()
	if new_pw.is_empty():
		_show_error("New password is required.")
		return

	var confirm := _confirm_input.text.strip_edges()
	if new_pw != confirm:
		_show_error("Passwords do not match.")
		return

	if Config.profiles.set_password(_slug, old_pw, new_pw):
		queue_free()
	else:
		_show_error("Current password is incorrect.")
		_current_input.text = ""


func _on_remove() -> void:
	var old_pw := _current_input.text.strip_edges()
	if old_pw.is_empty():
		_show_error("Current password is required to remove it.")
		return
	if Config.profiles.set_password(_slug, old_pw, ""):
		queue_free()
	else:
		_show_error("Current password is incorrect.")
		_current_input.text = ""


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
