extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _invite_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/InviteList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _create_toggle: Button = $CenterContainer/Panel/VBox/CreateToggle
@onready var _create_form: VBoxContainer = $CenterContainer/Panel/VBox/CreateForm
@onready var _max_age_option: OptionButton = $CenterContainer/Panel/VBox/CreateForm/MaxAgeOption
@onready var _max_uses_spin: SpinBox = $CenterContainer/Panel/VBox/CreateForm/MaxUsesRow/MaxUsesSpin
@onready var _temporary_check: CheckBox = $CenterContainer/Panel/VBox/CreateForm/TemporaryCheck
@onready var _create_btn: Button = $CenterContainer/Panel/VBox/CreateForm/CreateButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_create_toggle.pressed.connect(_toggle_create)
	_create_btn.pressed.connect(_on_create)
	_create_form.visible = false

	_max_age_option.add_item("30 minutes", 0)
	_max_age_option.add_item("1 hour", 1)
	_max_age_option.add_item("6 hours", 2)
	_max_age_option.add_item("12 hours", 3)
	_max_age_option.add_item("1 day", 4)
	_max_age_option.add_item("7 days", 5)
	_max_age_option.add_item("Never", 6)
	_max_age_option.select(4) # Default: 1 day

	_max_uses_spin.min_value = 0
	_max_uses_spin.max_value = 100
	_max_uses_spin.value = 0

	AppState.invites_updated.connect(_on_invites_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_load_invites()

func _load_invites() -> void:
	for child in _invite_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false

	var result: RestResult = await Client.get_invites(_guild_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load invites"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var invites: Array = result.data if result.data is Array else []
	if invites.is_empty():
		_empty_label.visible = true
		return

	for invite in invites:
		var invite_dict: Dictionary
		if invite is AccordInvite:
			invite_dict = ClientModels.invite_to_dict(invite)
		elif invite is Dictionary:
			invite_dict = invite
		else:
			continue
		var row := _create_invite_row(invite_dict)
		_invite_list.add_child(row)

func _create_invite_row(invite: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var code: String = invite.get("code", "")

	var code_label := Label.new()
	code_label.text = code
	code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(code_label)

	var uses: int = invite.get("uses", 0)
	var max_uses: int = invite.get("max_uses", 0)
	var uses_label := Label.new()
	if max_uses > 0:
		uses_label.text = "%d/%d uses" % [uses, max_uses]
	else:
		uses_label.text = "%d uses" % uses
	uses_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	row.add_child(uses_label)

	var copy_btn := Button.new()
	copy_btn.text = "Copy"
	copy_btn.flat = true
	copy_btn.add_theme_color_override("font_color", Color(0.345, 0.396, 0.949))
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(code)
	)
	row.add_child(copy_btn)

	var revoke_btn := Button.new()
	revoke_btn.text = "Revoke"
	revoke_btn.flat = true
	revoke_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	revoke_btn.pressed.connect(_on_revoke.bind(code))
	row.add_child(revoke_btn)

	return row

func _toggle_create() -> void:
	_create_form.visible = not _create_form.visible
	_create_toggle.text = "Cancel" if _create_form.visible else "Create Invite"

func _on_create() -> void:
	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var age_map := [1800, 3600, 21600, 43200, 86400, 604800, 0]
	var data := {
		"max_age": age_map[_max_age_option.selected],
		"max_uses": int(_max_uses_spin.value),
		"temporary": _temporary_check.button_pressed,
	}

	var result: RestResult = await Client.create_invite(_guild_id, data)
	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var err_msg: String = "Failed to create invite"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_create_form.visible = false
		_create_toggle.text = "Create Invite"
		_load_invites()

func _on_revoke(code: String) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Revoke Invite",
		"Are you sure you want to revoke invite '%s'?" % code,
		"Revoke",
		true
	)
	dialog.confirmed.connect(func():
		Client.delete_invite(code, _guild_id)
	)

func _on_invites_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_load_invites()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
