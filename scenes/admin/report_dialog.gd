extends ModalBase

const CATEGORIES := [
	["csam", "CSAM / Child exploitation"],
	["terrorism", "Terrorism / Extremism"],
	["fraud", "Fraud / Scam"],
	["hate", "Hate crime / Hate speech"],
	["violence", "Threats of violence"],
	["self_harm", "Encouraging suicide / Self-harm"],
	["other", "Other illegal content"],
]

var _space_id: String = ""
var _target_type: String = ""
var _target_id: String = ""
var _channel_id: String = ""

@onready var _title_label: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _category_option: OptionButton = $CenterContainer/Panel/VBox/CategoryOption
@onready var _description_input: TextEdit = $CenterContainer/Panel/VBox/DescriptionInput
@onready var _submit_btn: Button = $CenterContainer/Panel/VBox/SubmitButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _success_label: Label = $CenterContainer/Panel/VBox/SuccessLabel

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 420, 0)
	_close_btn.pressed.connect(_close)
	_submit_btn.pressed.connect(_on_submit)
	for i in CATEGORIES.size():
		_category_option.add_item(CATEGORIES[i][1], i)

func setup_message(space_id: String, channel_id: String, message_id: String) -> void:
	_space_id = space_id
	_channel_id = channel_id
	_target_type = "message"
	_target_id = message_id
	if _title_label:
		_title_label.text = "Report Message"

func setup_user(space_id: String, user_id: String, display_name: String) -> void:
	_space_id = space_id
	_target_type = "user"
	_target_id = user_id
	if _title_label:
		_title_label.text = "Report %s" % display_name

func _on_submit() -> void:
	_submit_btn.disabled = true
	_submit_btn.text = "Submitting..."
	_error_label.visible = false
	_success_label.visible = false

	var cat_idx: int = _category_option.selected
	if cat_idx < 0 or cat_idx >= CATEGORIES.size():
		_show_error("Please select a category.")
		return

	var data: Dictionary = {
		"target_type": _target_type,
		"target_id": _target_id,
		"category": CATEGORIES[cat_idx][0],
	}
	if not _channel_id.is_empty():
		data["channel_id"] = _channel_id
	var desc: String = _description_input.text.strip_edges()
	if not desc.is_empty():
		data["description"] = desc

	var result: RestResult = await Client.admin.create_report(
		_space_id, data
	)

	if result == null or not result.ok:
		var err_msg: String = "Failed to submit report"
		if result != null and result.error:
			err_msg = result.error.message
		_show_error(err_msg)
		return

	_success_label.text = "Report submitted. Thank you."
	_success_label.visible = true
	_submit_btn.visible = false
	_category_option.disabled = true
	_description_input.editable = false
	await get_tree().create_timer(1.5).timeout
	_close()

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true
	_submit_btn.disabled = false
	_submit_btn.text = "Submit Report"
