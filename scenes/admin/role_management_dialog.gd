extends ModalBase

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const RoleRowScene := preload("res://scenes/admin/role_row.tscn")

## Sidebar collapses to a dropdown below this viewport width.
const _COMPACT_THRESHOLD: float = 600.0

var _space_id: String = ""
var _selected_role: Dictionary = {}
var _perm_checks: Dictionary = {} # perm_string -> CheckBox
var _all_roles: Array = []
var _visible_roles: Array = [] # currently displayed (filtered) role list
var _dirty: bool = false

# Compact-mode sidebar replacement
var _compact_dropdown: OptionButton
var _is_compact_layout: bool = false

@onready var _vbox: VBoxContainer = $CenterContainer/Panel/VBox
@onready var _role_scroll: ScrollContainer = \
	$CenterContainer/Panel/VBox/Content/RoleScroll
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
	_bind_modal_nodes($CenterContainer/Panel, 640, 480)
	_close_btn.pressed.connect(_close)
	_new_role_btn.pressed.connect(_on_new_role)
	_save_btn.pressed.connect(_on_save)
	_delete_btn.pressed.connect(_on_delete)
	_search_input.text_changed.connect(_on_search_changed)
	_editor.visible = false
	_build_perm_checkboxes()
	_build_compact_dropdown()
	_update_compact_layout()
	AppState.roles_updated.connect(_on_roles_updated)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_color_picker.color_changed.connect(func(_c: Color): _dirty = true)
	_hoist_check.toggled.connect(func(_b: bool): _dirty = true)
	_mentionable_check.toggled.connect(func(_b: bool): _dirty = true)

func setup(space_id: String) -> void:
	_space_id = space_id
	_rebuild_role_list()

func _build_perm_checkboxes() -> void:
	for perm in AccordPermission.all():
		var cb := CheckBox.new()
		cb.text = _format_perm_name(perm)
		cb.tooltip_text = AccordPermission.description(perm)
		cb.toggled.connect(func(_b: bool): _dirty = true)
		_perm_list.add_child(cb)
		_perm_checks[perm] = cb

func _format_perm_name(perm: String) -> String:
	return perm.replace("_", " ").capitalize()

func _rebuild_role_list() -> void:
	_clear_children(_role_list)

	_all_roles = Client.get_roles_for_space(_space_id)
	_all_roles.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.get("position", 0) > b.get("position", 0)
	)

	_build_role_buttons(_all_roles)

func _build_role_buttons(roles: Array) -> void:
	_clear_children(_role_list)

	_visible_roles = roles
	var role_counts: Dictionary = _compute_role_member_counts()

	for i in roles.size():
		var role: Dictionary = roles[i]
		var role_id: String = role.get("id", "")
		var count: int = role_counts.get(role_id, 0)
		var row := RoleRowScene.instantiate()
		_role_list.add_child(row)
		row.setup(role, i, roles.size(), count)
		row.move_requested.connect(_on_move_role)
		row.selected.connect(_select_role)

	_rebuild_compact_dropdown()

func _compute_role_member_counts() -> Dictionary:
	var counts: Dictionary = {}
	var members: Array = Client.get_members_for_space(_space_id)
	for member in members:
		var roles: Array = member.get("roles", [])
		for role_id in roles:
			var rid: String = str(role_id)
			counts[rid] = counts.get(rid, 0) + 1
	return counts

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
	var my_highest: int = Client.get_my_highest_role_position(_space_id)
	if my_highest != 999999:
		if role.get("position", 0) >= my_highest \
				or _all_roles[swap_idx].get("position", 0) >= my_highest:
			_error_label.text = tr("Cannot reorder roles at or above your own")
			_error_label.visible = true
			return

	# Build reorder data: swap positions
	var pos_a: int = _all_roles[idx].get("position", 0)
	var pos_b: int = _all_roles[swap_idx].get("position", 0)
	var data: Array = [
		{"id": _all_roles[idx].get("id", ""), "position": pos_b},
		{"id": _all_roles[swap_idx].get("id", ""), "position": pos_a},
	]

	var result: RestResult = await Client.admin.reorder_roles(_space_id, data)
	_show_rest_error(result, tr("Failed to reorder roles"))

func _select_role(role: Dictionary) -> void:
	_selected_role = role
	_editor.visible = true
	_error_label.visible = false
	_dirty = false
	_sync_compact_dropdown_selection()

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
	var my_highest: int = Client.get_my_highest_role_position(_space_id)
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
		_error_label.text = tr("You cannot edit roles at or above your own")
		_error_label.visible = true

	_dirty = false

func _on_new_role() -> void:
	_error_label.visible = false
	var result: RestResult = await _with_button_loading(
		_new_role_btn, _new_role_btn.text,
		func() -> RestResult:
			return await Client.admin.create_role(
				_space_id, {"name": tr("New Role")}
			)
	)
	_show_rest_error(result, tr("Failed to create role"))

func _on_save() -> void:
	if _selected_role.is_empty():
		return

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

	var result: RestResult = await _with_button_loading(
		_save_btn, tr("Save"),
		func() -> RestResult:
			return await Client.admin.update_role(
				_space_id, _selected_role.get("id", ""), data
			)
	)

	if not _show_rest_error(result, tr("Failed to update role")):
		_dirty = false

func _on_delete() -> void:
	if _selected_role.is_empty():
		return
	var role_name: String = _selected_role.get("name", "")
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		tr("Delete Role"),
		tr("Are you sure you want to delete '%s'?") % role_name,
		tr("Delete"),
		true
	)
	dialog.confirmed.connect(func():
		var result: RestResult = await Client.admin.delete_role(
			_space_id, _selected_role.get("id", "")
		)
		if result != null and result.ok:
			_selected_role = {}
			_editor.visible = false
			_dirty = false
	)

func _on_roles_updated(space_id: String) -> void:
	if space_id == _space_id:
		_rebuild_role_list()

func _try_close() -> void:
	_try_close_dirty(_dirty, ConfirmDialogScene)

func _close() -> void:
	_try_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()

# --- Compact-mode sidebar collapse ---

func _build_compact_dropdown() -> void:
	_compact_dropdown = OptionButton.new()
	_compact_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_compact_dropdown.visible = false
	_compact_dropdown.item_selected.connect(_on_compact_dropdown_selected)
	# Insert directly after the SearchInput (index 2) so it sits above Content.
	_vbox.add_child(_compact_dropdown)
	_vbox.move_child(_compact_dropdown, 2)

func _rebuild_compact_dropdown() -> void:
	if not is_instance_valid(_compact_dropdown):
		return
	_compact_dropdown.clear()
	for role in _visible_roles:
		_compact_dropdown.add_item(role.get("name", ""))
	_sync_compact_dropdown_selection()

func _sync_compact_dropdown_selection() -> void:
	if not is_instance_valid(_compact_dropdown):
		return
	if _selected_role.is_empty():
		_compact_dropdown.selected = -1
		return
	var sel_id: String = _selected_role.get("id", "")
	for i in _visible_roles.size():
		if _visible_roles[i].get("id", "") == sel_id:
			_compact_dropdown.selected = i
			return
	_compact_dropdown.selected = -1

func _on_compact_dropdown_selected(idx: int) -> void:
	if idx < 0 or idx >= _visible_roles.size():
		return
	_select_role(_visible_roles[idx])

func _update_compact_layout() -> void:
	if not is_instance_valid(_compact_dropdown) \
			or not is_instance_valid(_role_scroll):
		return
	var vp_w: float = get_viewport_rect().size.x
	var should_compact: bool = vp_w < _COMPACT_THRESHOLD
	if should_compact == _is_compact_layout:
		return
	_is_compact_layout = should_compact
	_role_scroll.visible = not should_compact
	_compact_dropdown.visible = should_compact

func _on_viewport_resized() -> void:
	super._on_viewport_resized()
	_update_compact_layout()
