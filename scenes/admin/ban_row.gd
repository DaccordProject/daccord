extends HBoxContainer

signal unban_requested(user_id: String, username: String)
signal toggled(pressed: bool, user_id: String)

var user_id: String = ""
var _username: String = ""

@onready var _checkbox: CheckBox = $CheckBox
@onready var _name_label: Label = $NameLabel
@onready var _reason_label: Label = $ReasonLabel
@onready var _unban_btn: Button = $UnbanButton

func _ready() -> void:
	_checkbox.toggled.connect(func(pressed: bool): toggled.emit(pressed, user_id))
	_unban_btn.pressed.connect(func(): unban_requested.emit(user_id, _username))

func setup(ban: Dictionary, selected: bool) -> void:
	var user_data = ban.get("user", {})
	if user_data is Dictionary:
		_username = str(user_data.get("username", user_data.get("display_name", "Unknown")))
		user_id = str(user_data.get("id", ""))
	else:
		_username = str(ban.get("user_id", ""))
		user_id = str(ban.get("user_id", ""))

	set_meta("user_id", user_id)
	_name_label.text = _username
	_checkbox.button_pressed = selected

	var reason: String = str(ban.get("reason", ""))
	if not reason.is_empty() and reason != "null":
		_reason_label.text = reason
		_reason_label.visible = true
	else:
		_reason_label.visible = false
