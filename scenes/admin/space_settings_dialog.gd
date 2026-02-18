extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""
var _dirty: bool = false

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _desc_input: TextEdit = $CenterContainer/Panel/VBox/DescInput
@onready var _verification_btn: OptionButton = \
	$CenterContainer/Panel/VBox/VerificationRow/VerificationOption
@onready var _notifications_btn: OptionButton = \
	$CenterContainer/Panel/VBox/NotificationsRow/NotificationsOption
@onready var _public_check: CheckBox = $CenterContainer/Panel/VBox/PublicRow/PublicCheck
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/SaveRow/SaveButton
@onready var _delete_btn: Button = $CenterContainer/Panel/VBox/DangerZone/DeleteButton
@onready var _danger_zone: VBoxContainer = $CenterContainer/Panel/VBox/DangerZone
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_delete_btn.pressed.connect(_on_delete)
	_verification_btn.add_item("None", 0)
	_verification_btn.add_item("Low", 1)
	_verification_btn.add_item("Medium", 2)
	_verification_btn.add_item("High", 3)
	_notifications_btn.add_item("All Messages", 0)
	_notifications_btn.add_item("Mentions Only", 1)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_desc_input.text_changed.connect(func(): _dirty = true)
	_verification_btn.item_selected.connect(func(_i: int): _dirty = true)
	_notifications_btn.item_selected.connect(func(_i: int): _dirty = true)
	_public_check.toggled.connect(func(_b: bool): _dirty = true)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	var guild: Dictionary = Client.get_guild_by_id(guild_id)

	if _name_input:
		_name_input.text = guild.get("name", "")
	if _desc_input:
		_desc_input.text = guild.get("description", "")

	var ver: String = guild.get("verification_level", "none")
	match ver:
		"low": _verification_btn.select(1)
		"medium": _verification_btn.select(2)
		"high": _verification_btn.select(3)
		_: _verification_btn.select(0)

	var notif: String = guild.get("default_notifications", "all")
	if notif == "mentions":
		_notifications_btn.select(1)
	else:
		_notifications_btn.select(0)

	_public_check.button_pressed = guild.get("public", false)

	# Only the owner can see the danger zone
	_danger_zone.visible = Client.is_space_owner(guild_id)
	_dirty = false

func _on_save() -> void:
	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	var ver_levels := ["none", "low", "medium", "high"]
	var notif_levels := ["all", "mentions"]

	var data := {
		"name": _name_input.text.strip_edges(),
		"description": _desc_input.text.strip_edges(),
		"verification_level": ver_levels[_verification_btn.selected],
		"default_notifications": notif_levels[_notifications_btn.selected],
	}

	# Public is a feature flag - send it only if the server supports it
	# For now we include it as a top-level field
	if _public_check.button_pressed:
		data["features"] = ["public"]
	else:
		data["features"] = []

	var result: RestResult = await Client.admin.update_space(_guild_id, data)
	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var err_msg: String = "Failed to update space"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_dirty = false
		queue_free()

func _on_delete() -> void:
	var guild: Dictionary = Client.get_guild_by_id(_guild_id)
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Server",
		"Are you sure you want to delete '%s'? This cannot be undone." % guild.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		var result: RestResult = await Client.admin.delete_space(_guild_id)
		if result != null and result.ok:
			_dirty = false
			queue_free()
	)

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
