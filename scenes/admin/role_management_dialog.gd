extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const RoleRowScene := preload("res://scenes/admin/role_row.tscn")

var _guild_id: String = ""
var _selected_role: Dictionary = {}
var _perm_checks: Dictionary = {} # perm_string -> CheckBox
var _all_roles: Array = []
var _dirty: bool = false

@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _new_role_btn: Button = \
	$CenterContainer/Panel/VBox/Header/NewRoleButton
@onready var _search_input: LineEdit = \
	$CenterContainer/Panel/VBox/SearchInput
@onready var _role_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/RoleScroll/RoleList
@onready var _editor: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor
@onready var _name_input: LineEdit = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/NameInput
@onready var _color_picker: ColorPickerButton = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/ColorRow/ColorPicker
@onready var _hoist_check: CheckBox = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/HoistRow/HoistCheck
@onready var _mentionable_check: CheckBox = \
	$CenterContainer/Panel/VBox/Content/EditorScroll/Editor/MentionableRow/MentionableCheck
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
	_search_input.text_changed.connect(_on_search_changed)
	_editor.visible = false
	_build_perm_checkboxes()
	AppState.roles_updated.connect(_on_roles_updated)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_color_picker.color_changed.connect(func(_c: Color): _dirty = true)
	_hoist_check.toggled.connect(func(_b: bool): _dirty = true)
	_mentionable_check.toggled.connect(func(_b: bool): _dirty = true)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_rebuild_role_list()

func _build_perm_checkboxes() -> void:
	for perm in AccordPermission.all():
		var cb := CheckBox.new()
		cb.text = _format_perm_name(perm)
		cb.toggled.connect(func(_b: bool): _dirty = true)
		_perm_list.add_child(cb)
		_perm_checks[perm] = cb

func _format_perm_name(perm: String) -> String:
	return perm.replace("_", " ").capitalize()

func _rebuild_role_list() -> void:
	for child in _role_list.get_children():
		child.queue_free()

	_all_roles = Client.get_roles_for_guild(_guild_id)
	_all_roles.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.get("position", 0) > b.get("position", 0)
	)

	_build_role_buttons(_all_roles)

func _build_role_buttons(roles: Array) -> void:
	for child in _role_list.get_children():
		child.queue_free()

	for i in roles.size():
		var role: Dictionary = roles[i]
		var row := RoleRowScene.instantiate()
		_role_list.add_child(row)
		row.setup(role, i, roles.size())
		row.move_requested.connect(_on_move_role)
		row.selected.connect(_select_role)

func _get_role_index(role: Dictionary) -> int:
	for i in _all_roles.size():
		if _all_roles[i].get("id", "") == role.get("id", ""):
			return i
	return -1

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_build_role_buttons(_all_roles)
		return
	var filtered: Array = []
	for role in _all_roles:
		if role.get("name", "").to_lower().contains(query):
			filtered.append(role)
	_build_role_buttons(filtered)

func _on_move_role(role: Dictionary, direction: int) -> void:
	var idx := _get_role_index(role)
	if idx == -1:
		return
	var swap_idx := idx + direction
	if swap_idx < 0 or swap_idx >= _all_roles.size():
		return
	# Don't swap with @everyone
	if _all_roles[swap_idx].get("position", 0) == 0:
		return

	# Role hierarchy enforcement
	var my_highest: int = Client.get_my_highest_role_position(_guild_id)
	if my_highest != 999999:
		if role.get("position", 0) >= my_highest \
				or _all_roles[swap_idx].get("position", 0) >= my_highest:
			_error_label.text = "Cannot reorder roles at or above your own"
			_error_label.visible = true
			return

	# Build reorder data: swap positions
	var pos_a: int = _all_roles[idx].get("position", 0)
	var pos_b: int = _all_roles[swap_idx].get("position", 0)
	var data: Array = [
		{"id": _all_roles[idx].get("id", ""), "position": pos_b},
		{"id": _all_roles[swap_idx].get("id", ""), "position": pos_a},
	]

	var result: RestResult = await Client.admin.reorder_roles(_guild_id, data)
	if result == null or not result.ok:
		var err_msg: String = "Failed to reorder roles"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _select_role(role: Dictionary) -> void:
	_selected_role = role
	_editor.visible = true
	_error_label.visible = false
	_dirty = false

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

	# Role hierarchy enforcement
	var my_highest: int = Client.get_my_highest_role_position(_guild_id)
	var above_me: bool = role.get("position", 0) >= my_highest \
		and my_highest != 999999
	_name_input.editable = not above_me
	_color_picker.disabled = above_me
	_hoist_check.disabled = above_me
	_mentionable_check.disabled = above_me
	_save_btn.disabled = above_me
	if above_me:
		_delete_btn.visible = false
	for perm in _perm_checks:
		_perm_checks[perm].disabled = above_me
	if above_me:
		_error_label.text = "You cannot edit roles at or above your own"
		_error_label.visible = true

	_dirty = false

func _on_new_role() -> void:
	_new_role_btn.disabled = true
	_error_label.visible = false
	var result: RestResult = await Client.admin.create_role(_guild_id, {"name": "New Role"})
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

	var result: RestResult = await Client.admin.update_role(
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
	else:
		_dirty = false

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
		var result: RestResult = await Client.admin.delete_role(
			_guild_id, _selected_role.get("id", "")
		)
		if result != null and result.ok:
			_selected_role = {}
			_editor.visible = false
			_dirty = false
	)

func _on_roles_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_rebuild_role_list()

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
