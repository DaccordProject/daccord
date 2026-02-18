extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _ban_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/BanList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	AppState.bans_updated.connect(_on_bans_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_load_bans()

func _load_bans() -> void:
	for child in _ban_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false

	var result: RestResult = await Client.get_bans(_guild_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load bans"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var bans: Array = result.data if result.data is Array else []
	if bans.is_empty():
		_empty_label.visible = true
		return

	for ban in bans:
		var ban_dict: Dictionary = ban if ban is Dictionary else {}
		var row := _create_ban_row(ban_dict)
		_ban_list.add_child(row)

func _create_ban_row(ban: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var user_data = ban.get("user", {})
	var username: String = ""
	var user_id: String = ""
	if user_data is Dictionary:
		username = str(user_data.get("username", user_data.get("display_name", "Unknown")))
		user_id = str(user_data.get("id", ""))
	else:
		user_id = str(ban.get("user_id", ""))
		username = user_id

	var name_label := Label.new()
	name_label.text = username
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)

	var reason: String = str(ban.get("reason", ""))
	if not reason.is_empty() and reason != "null":
		var reason_label := Label.new()
		reason_label.text = reason
		reason_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		reason_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.add_child(reason_label)

	var unban_btn := Button.new()
	unban_btn.text = "Unban"
	unban_btn.flat = true
	unban_btn.add_theme_color_override("font_color", Color(0.345, 0.396, 0.949))
	unban_btn.pressed.connect(_on_unban.bind(user_id, username))
	row.add_child(unban_btn)

	return row

func _on_unban(user_id: String, username: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Unban User",
		"Are you sure you want to unban %s?" % username,
		"Unban",
		false
	)
	dialog.confirmed.connect(func():
		Client.unban_member(_guild_id, user_id)
	)

func _on_bans_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_load_bans()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
