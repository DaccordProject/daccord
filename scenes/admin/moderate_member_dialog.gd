extends ColorRect

# Duration options in seconds
const DURATIONS := [60, 300, 600, 3600, 86400, 604800]
const DURATION_LABELS := [
	"60 seconds", "5 minutes", "10 minutes",
	"1 hour", "1 day", "1 week"
]

var _space_id: String = ""
var _user_id: String = ""

@onready var _title_label: Label = \
	$CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _duration_option: OptionButton = \
	$CenterContainer/Panel/VBox/DurationOption
@onready var _remove_timeout_btn: Button = \
	$CenterContainer/Panel/VBox/RemoveTimeoutButton
@onready var _mute_check: CheckBox = \
	$CenterContainer/Panel/VBox/MuteCheck
@onready var _deaf_check: CheckBox = \
	$CenterContainer/Panel/VBox/DeafCheck
@onready var _apply_btn: Button = \
	$CenterContainer/Panel/VBox/ApplyButton
@onready var _error_label: Label = \
	$CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_apply_btn.pressed.connect(_on_apply)
	_remove_timeout_btn.pressed.connect(_on_remove_timeout)
	for label in DURATION_LABELS:
		_duration_option.add_item(label)

func setup(
	space_id: String, user_id: String,
	display_name: String, member_data: Dictionary
) -> void:
	_space_id = space_id
	_user_id = user_id
	if _title_label:
		_title_label.text = "Moderate %s" % display_name
	_mute_check.button_pressed = member_data.get("mute", false)
	_deaf_check.button_pressed = member_data.get("deaf", false)
	var timeout: String = member_data.get("timed_out_until", "")
	_remove_timeout_btn.visible = not timeout.is_empty()

func _on_apply() -> void:
	_apply_btn.disabled = true
	_apply_btn.text = "Applying..."
	_error_label.visible = false

	var data: Dictionary = {
		"mute": _mute_check.button_pressed,
		"deaf": _deaf_check.button_pressed,
	}

	# Compute timeout timestamp
	var dur_idx: int = _duration_option.selected
	if dur_idx >= 0 and dur_idx < DURATIONS.size():
		var unix: float = Time.get_unix_time_from_system()
		unix += DURATIONS[dur_idx]
		var dt: Dictionary = Time.get_datetime_dict_from_unix_time(
			int(unix)
		)
		data["communication_disabled_until"] = \
			"%04d-%02d-%02dT%02d:%02d:%02dZ" % [
				dt["year"], dt["month"], dt["day"],
				dt["hour"], dt["minute"], dt["second"],
			]

	var result: RestResult = await Client.admin.update_member(
		_space_id, _user_id, data
	)
	_apply_btn.disabled = false
	_apply_btn.text = "Apply"

	if result == null or not result.ok:
		var err_msg: String = "Failed to moderate member"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_close()

func _on_remove_timeout() -> void:
	_remove_timeout_btn.disabled = true
	_error_label.visible = false

	var data: Dictionary = {
		"communication_disabled_until": "",
	}
	var result: RestResult = await Client.admin.update_member(
		_space_id, _user_id, data
	)
	_remove_timeout_btn.disabled = false

	if result == null or not result.ok:
		var err_msg: String = "Failed to remove timeout"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_close()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
