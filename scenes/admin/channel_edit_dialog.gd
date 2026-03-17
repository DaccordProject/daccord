extends ModalBase

signal saved

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _channel_id: String = ""
var _dirty: bool = false

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _topic_input: LineEdit = $CenterContainer/Panel/VBox/TopicInput
@onready var _nsfw_check: CheckBox = $CenterContainer/Panel/VBox/NsfwRow/NsfwCheck
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/Buttons/SaveButton

func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 380, 0)
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_topic_input.text_changed.connect(func(_t: String): _dirty = true)
	_nsfw_check.toggled.connect(func(_b: bool): _dirty = true)

func setup(channel: Dictionary) -> void:
	_channel_id = channel.get("id", "")
	_name_input.text = channel.get("name", "")
	_topic_input.text = channel.get("topic", "")
	_nsfw_check.button_pressed = channel.get("nsfw", false)
	_dirty = false

func _on_save() -> void:
	_error_label.visible = false
	var data := {
		"name": _name_input.text.strip_edges(),
		"topic": _topic_input.text.strip_edges(),
		"nsfw": _nsfw_check.button_pressed,
	}

	var result: RestResult = await _with_button_loading(
		_save_btn, tr("Save"),
		func() -> RestResult:
			return await Client.admin.update_channel(_channel_id, data)
	)

	if not _show_rest_error(result, tr("Failed to update channel")):
		_dirty = false
		saved.emit()
		queue_free()

func _try_close() -> void:
	_try_close_dirty(_dirty, ConfirmDialogScene)

func _close() -> void:
	_try_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()
