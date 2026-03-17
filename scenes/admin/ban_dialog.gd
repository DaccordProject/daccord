extends ModalBase

signal ban_confirmed(user_id: String, reason: String)

const PURGE_OPTIONS := [
	[0, "Don't delete any"],
	[3600, "Last hour"],
	[21600, "Last 6 hours"],
	[43200, "Last 12 hours"],
	[86400, "Last 24 hours"],
	[259200, "Last 3 days"],
	[604800, "Last 7 days"],
]

var _space_id: String = ""
var _user_id: String = ""
var _display_name: String = ""
var _confirmed: bool = false

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _reason_input: LineEdit = $CenterContainer/Panel/VBox/ReasonInput
@onready var _purge_option: OptionButton = $CenterContainer/Panel/VBox/PurgeOption
@onready var _summary_label: Label = $CenterContainer/Panel/VBox/SummaryLabel
@onready var _ban_btn: Button = $CenterContainer/Panel/VBox/BanButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 380, 0)
	_close_btn.pressed.connect(_close)
	_ban_btn.pressed.connect(_on_ban_pressed)
	_reason_input.text_submitted.connect(func(_t: String): _on_ban_pressed())
	for opt in PURGE_OPTIONS:
		_purge_option.add_item(tr(opt[1]))

func setup(space_id: String, user_id: String, display_name: String) -> void:
	_space_id = space_id
	_user_id = user_id
	_display_name = display_name
	if _title_label:
		_title_label.text = tr("Ban %s") % display_name

func _on_ban_pressed() -> void:
	var reason: String = _reason_input.text.strip_edges()

	if not _confirmed:
		# First press: show summary and ask for confirmation
		_confirmed = true
		_reason_input.editable = false
		_purge_option.disabled = true
		_ban_btn.text = tr("Confirm Ban")
		var summary: String = tr("Ban %s from this server") % _display_name
		if not reason.is_empty():
			summary += "\n" + tr("Reason: %s") % reason
		var purge_idx: int = _purge_option.selected
		if purge_idx > 0:
			summary += "\n" + tr("Purge: %s") % tr(PURGE_OPTIONS[purge_idx][1])
		_summary_label.text = summary
		_summary_label.visible = true
		return

	# Second press: execute ban
	_error_label.visible = false
	var data: Dictionary = {}
	if not reason.is_empty():
		data["reason"] = reason
	var purge_idx: int = _purge_option.selected
	if purge_idx > 0 and purge_idx < PURGE_OPTIONS.size():
		data["delete_message_seconds"] = PURGE_OPTIONS[purge_idx][0]

	var result: RestResult = await _with_button_loading(
		_ban_btn, tr("Ban"),
		func() -> RestResult:
			return await Client.admin.ban_member(
				_space_id, _user_id, data
			)
	)

	if _show_rest_error(result, tr("Failed to ban user")):
		# Reset confirmation state on failure
		_confirmed = false
		_reason_input.editable = true
		_purge_option.disabled = false
		_summary_label.visible = false
	else:
		ban_confirmed.emit(_user_id, reason)
		_close()

