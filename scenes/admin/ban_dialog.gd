extends ColorRect

signal ban_confirmed(user_id: String, reason: String)

var _guild_id: String = ""
var _user_id: String = ""
var _display_name: String = ""
var _confirmed: bool = false

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _reason_input: LineEdit = $CenterContainer/Panel/VBox/ReasonInput
@onready var _summary_label: Label = $CenterContainer/Panel/VBox/SummaryLabel
@onready var _ban_btn: Button = $CenterContainer/Panel/VBox/BanButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_ban_btn.pressed.connect(_on_ban_pressed)
	_reason_input.text_submitted.connect(func(_t: String): _on_ban_pressed())

func setup(guild_id: String, user_id: String, display_name: String) -> void:
	_guild_id = guild_id
	_user_id = user_id
	_display_name = display_name
	if _title_label:
		_title_label.text = "Ban %s" % display_name

func _on_ban_pressed() -> void:
	var reason: String = _reason_input.text.strip_edges()

	if not _confirmed:
		# First press: show summary and ask for confirmation
		_confirmed = true
		_reason_input.editable = false
		_ban_btn.text = "Confirm Ban"
		var summary: String = "Ban %s from this server" % _display_name
		if not reason.is_empty():
			summary += "\nReason: %s" % reason
		_summary_label.text = summary
		_summary_label.visible = true
		return

	# Second press: execute ban
	_ban_btn.disabled = true
	_ban_btn.text = "Banning..."
	_error_label.visible = false

	var data: Dictionary = {}
	if not reason.is_empty():
		data["reason"] = reason

	var result: RestResult = await Client.admin.ban_member(_guild_id, _user_id, data)

	if result == null or not result.ok:
		var err_msg: String = "Failed to ban user"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		# Reset confirmation state on failure
		_confirmed = false
		_reason_input.editable = true
		_summary_label.visible = false
		_ban_btn.disabled = false
		_ban_btn.text = "Ban"
	else:
		ban_confirmed.emit(_user_id, reason)
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
