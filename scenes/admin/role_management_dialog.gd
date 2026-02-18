extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""
var _selected_role: Dictionary = {}
var _perm_checks: Dictionary = {} # perm_string -> CheckBox

@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _new_role_btn: Button = \
	$CenterContainer/Panel/VBox/Header/NewRoleButton
@onready var _content: HBoxContainer = \
	$CenterContainer/Panel/VBox/Content
@onready var _role_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/RoleScroll/RoleList
@onready var _editor: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor
@onready var _name_input: LineEdit = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/NameInput
@onready var _color_picker: ColorPickerButton = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/ColorRow/ColorPicker
@onready var _hoist_check: CheckBox = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/HoistCheck
@onready var _mentionable_check: CheckBox = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/MentionableCheck
@onready var _perm_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/PermList
@onready var _save_btn: Button = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/EditorButtons/SaveButton
@onready var _delete_btn: Button = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/EditorButtons/DeleteButton
@onready var _error_label: Label = \
	$CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_new_role_btn.pressed.connect(_on_new_role)
	_save_btn.pressed.connect(_on_save)
	_delete_btn.pressed.connect(_on_delete)
	_editor.visible = false
	_build_perm_checkboxes()
	AppState.roles_updated.connect(_on_roles_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_rebuild_role_list()

func _build_perm_checkboxes() -> void:
	for perm in AccordPermission.all():
		var cb := CheckBox.new()
		cb.text = _format_perm_name(perm)
		_perm_list.add_child(cb)
		_perm_checks[perm] = cb

func _format_perm_name(perm: String) -> String:
	return perm.replace("_", " ").capitalize()

func _rebuild_role_list() -> void:
	for child in _role_list.get_children():
		child.queue_free()

	var roles: Array = Client.get_roles_for_guild(_guild_id)
	roles.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.get("position", 0) > b.get("position", 0)
	)

	for role in roles:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(160, 32)

		var role_color: int = role.get("color", 0)
		var display_color := Color.WHITE
		if role_color > 0:
			display_color = Color.hex(role_color)

		btn.text = role.get("name", "")
		btn.add_theme_color_override("font_color", display_color)
		btn.pressed.connect(_select_role.bind(role))
		_role_list.add_child(btn)

func _select_role(role: Dictionary) -> void:
	_selected_role = role
	_editor.visible = true
	_error_label.visible = false

	_name_input.text = role.get("name", "")

	var role_color: int = role.get("color", 0)
	if role_color > 0:
		_color_picker.color = Color.hex(role_color)
	else:
		_color_picker.color = Color.WHITE

	_hoist_check.button_pressed = role.get("hoist", false)
	_mentionable_check.button_pressed = role.get("mentionable", false)

	var perms: Array = role.get("permissions", [])
	for perm in _perm_checks:
		_perm_checks[perm].button_pressed = perm in perms

	# Don't allow deleting @everyone
	_delete_btn.visible = role.get("position", 0) != 0

func _on_new_role() -> void:
	_new_role_btn.disabled = true
	_error_label.visible = false
	var result: RestResult = await Client.create_role(_guild_id, {"name": "New Role"})
	_new_role_btn.disabled = false
	if result == null or not result.ok:
		var err_msg: String = "Failed to create role"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _on_save() -> void:
	if _selected_role.is_empty():
		return

	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	var perms: Array = []
	for perm in _perm_checks:
		if _perm_checks[perm].button_pressed:
			perms.append(perm)

	var data := {
		"name": _name_input.text.strip_edges(),
		"color": _color_picker.color.to_html(false).hex_to_int(),
		"hoist": _hoist_check.button_pressed,
		"mentionable": _mentionable_check.button_pressed,
		"permissions": perms,
	}

	var result: RestResult = await Client.update_role(
		_guild_id, _selected_role.get("id", ""), data
	)
	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var err_msg: String = "Failed to update role"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _on_delete() -> void:
	if _selected_role.is_empty():
		return
	var role_name: String = _selected_role.get("name", "")
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Role",
		"Are you sure you want to delete '%s'?" % role_name,
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		var result: RestResult = await Client.delete_role(
			_guild_id, _selected_role.get("id", "")
		)
		if result != null and result.ok:
			_selected_role = {}
			_editor.visible = false
	)

func _on_roles_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_rebuild_role_list()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
