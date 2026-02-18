extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _category_id: String = ""
var _dirty: bool = false

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel
@onready var _cancel_btn: Button = $CenterContainer/Panel/VBox/Buttons/CancelButton
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/Buttons/SaveButton

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_cancel_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_name_input.text_changed.connect(func(_t: String): _dirty = true)

func setup(category: Dictionary) -> void:
	_category_id = category.get("id", "")
	_name_input.text = category.get("name", "")
	_dirty = false

func _on_save() -> void:
	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	var data := {"name": _name_input.text.strip_edges()}
	var result: RestResult = await Client.admin.update_channel(_category_id, data)

	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var msg: String = "Failed to update category"
		if result != null and result.error:
			msg = result.error.message
		_error_label.text = msg
		_error_label.visible = true
	else:
		_dirty = false
		queue_free()

func _try_close() -> void:
	if _dirty:
		var dialog := ConfirmDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(
			"Unsaved Changes",
			"You have unsaved changes. Discard?",
			"Discard",
			true
		)
		dialog.confirmed.connect(func():
			_dirty = false
			queue_free()
		)
	else:
		queue_free()

func _close() -> void:
	_try_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()
