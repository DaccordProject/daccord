extends ColorRect

var _space_id: String = ""
var _user_id: String = ""

@onready var _title_label: Label = \
	$CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _nick_input: LineEdit = \
	$CenterContainer/Panel/VBox/NickInput
@onready var _reset_btn: Button = \
	$CenterContainer/Panel/VBox/Buttons/ResetButton
@onready var _save_btn: Button = \
	$CenterContainer/Panel/VBox/Buttons/SaveButton
@onready var _error_label: Label = \
	$CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_reset_btn.pressed.connect(_on_reset)
	_nick_input.text_submitted.connect(
		func(_t: String): _on_save()
	)

func setup(
	space_id: String, user_id: String,
	display_name: String, current_nick: String
) -> void:
	_space_id = space_id
	_user_id = user_id
	if _title_label:
		_title_label.text = "Nickname: %s" % display_name
	if _nick_input:
		_nick_input.text = current_nick
		_nick_input.placeholder_text = display_name

func _on_save() -> void:
	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	var nick: String = _nick_input.text.strip_edges()
	var data: Dictionary = {"nick": nick if not nick.is_empty() else ""}

	var result: RestResult = await Client.admin.update_member(
		_space_id, _user_id, data
	)
	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var err_msg: String = "Failed to update nickname"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_close()

func _on_reset() -> void:
	_nick_input.text = ""
	_on_save()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
