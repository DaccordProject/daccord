extends ColorRect

## Permission overwrite states
enum OverwriteState { INHERIT, ALLOW, DENY }

const PermOverwriteRowScene := preload("res://scenes/admin/perm_overwrite_row.tscn")

const SELECTED_BG := Color(0.25, 0.27, 0.3, 1.0)

var _channel: Dictionary = {}
var _guild_id: String = ""
var _selected_role_id: String = ""
# role_id -> { perm_name -> OverwriteState }
var _overwrite_data: Dictionary = {}
var _perm_rows: Dictionary = {} # perm_name -> PermOverwriteRow
var _role_buttons: Dictionary = {} # role_id -> Button
# Role IDs that had overwrites when the dialog was opened
var _original_overwrite_ids: Array = []

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _title: Label = $CenterContainer/Panel/VBox/Header/Title
@onready var _role_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/RoleScroll/RoleList
@onready var _perm_list: VBoxContainer = \
	$CenterContainer/Panel/VBox/Content/PermScroll/PermList
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/Buttons/SaveButton
@onready var _reset_btn: Button = $CenterContainer/Panel/VBox/Buttons/ResetButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_reset_btn.pressed.connect(_on_reset)

func setup(channel: Dictionary, guild_id: String) -> void:
	_channel = channel
	_guild_id = guild_id
	_title.text = "Permissions: #%s" % channel.get("name", "")
	_load_overwrites()
	_rebuild_role_list()

func _load_overwrites() -> void:
	_overwrite_data.clear()
	_original_overwrite_ids.clear()
	# Load existing overwrites from channel data
	var overwrites: Array = _channel.get("permission_overwrites", [])
	for ow in overwrites:
		var ow_dict: Dictionary = ow if ow is Dictionary else {}
		var role_id: String = ow_dict.get("id", "")
		if role_id.is_empty():
			continue
		_original_overwrite_ids.append(role_id)
		var data: Dictionary = {}
		for perm in AccordPermission.all():
			if perm in ow_dict.get("allow", []):
				data[perm] = OverwriteState.ALLOW
			elif perm in ow_dict.get("deny", []):
				data[perm] = OverwriteState.DENY
			else:
				data[perm] = OverwriteState.INHERIT
		_overwrite_data[role_id] = data

func _rebuild_role_list() -> void:
	for child in _role_list.get_children():
		child.queue_free()
	_role_buttons.clear()

	var roles: Array = Client.get_roles_for_guild(_guild_id)
	roles.sort_custom(func(a: Dictionary, b: Dictionary):
		return a.get("position", 0) > b.get("position", 0)
	)

	for role in roles:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(140, 28)

		var role_color: int = role.get("color", 0)
		var display_color := Color.WHITE
		if role_color > 0:
			display_color = Color.hex(role_color)

		var rid: String = role.get("id", "")
		btn.text = role.get("name", "")
		btn.add_theme_color_override("font_color", display_color)
		btn.pressed.connect(_on_role_selected.bind(rid))
		_role_list.add_child(btn)
		_role_buttons[rid] = btn

	_update_role_selection()

func _update_role_selection() -> void:
	for rid in _role_buttons:
		var btn: Button = _role_buttons[rid]
		if rid == _selected_role_id:
			var sb := StyleBoxFlat.new()
			sb.bg_color = SELECTED_BG
			sb.corner_radius_top_left = 4
			sb.corner_radius_top_right = 4
			sb.corner_radius_bottom_left = 4
			sb.corner_radius_bottom_right = 4
			btn.add_theme_stylebox_override("normal", sb)
		else:
			btn.remove_theme_stylebox_override("normal")

func _on_role_selected(role_id: String) -> void:
	_selected_role_id = role_id
	_error_label.visible = false
	if not _overwrite_data.has(role_id):
		# Initialize all perms to INHERIT
		var data: Dictionary = {}
		for perm in AccordPermission.all():
			data[perm] = OverwriteState.INHERIT
		_overwrite_data[role_id] = data
	_update_role_selection()
	_rebuild_perm_list()

func _rebuild_perm_list() -> void:
	for child in _perm_list.get_children():
		child.queue_free()
	_perm_rows.clear()

	if _selected_role_id.is_empty():
		return

	var data: Dictionary = _overwrite_data.get(_selected_role_id, {})

	for perm in AccordPermission.all():
		var state: int = data.get(perm, OverwriteState.INHERIT)
		var row := PermOverwriteRowScene.instantiate()
		_perm_list.add_child(row)
		row.setup(perm, state)
		row.state_changed.connect(_toggle_perm)
		_perm_rows[perm] = row

func _toggle_perm(perm: String, new_state: int) -> void:
	if _selected_role_id.is_empty():
		return
	var data: Dictionary = _overwrite_data.get(_selected_role_id, {})
	data[perm] = new_state
	_overwrite_data[_selected_role_id] = data
	if _perm_rows.has(perm):
		_perm_rows[perm].update_state(new_state)

func _on_reset() -> void:
	if _selected_role_id.is_empty():
		return
	# Reset this role to all INHERIT
	var data: Dictionary = {}
	for perm in AccordPermission.all():
		data[perm] = OverwriteState.INHERIT
	_overwrite_data[_selected_role_id] = data
	_rebuild_perm_list()

func _on_save() -> void:
	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	# Build overwrites array and deleted IDs list
	var overwrites: Array = []
	var active_ids: Array = []
	for role_id in _overwrite_data:
		var data: Dictionary = _overwrite_data[role_id]
		var allow_list: Array = []
		var deny_list: Array = []
		for perm in data:
			match data[perm]:
				OverwriteState.ALLOW:
					allow_list.append(perm)
				OverwriteState.DENY:
					deny_list.append(perm)
		# Only include if there are actual overrides
		if allow_list.size() > 0 or deny_list.size() > 0:
			active_ids.append(role_id)
			overwrites.append({
				"id": role_id,
				"type": "role",
				"allow": allow_list,
				"deny": deny_list,
			})

	# IDs that had overwrites originally but are now all-INHERIT
	var deleted_ids: Array = []
	for oid in _original_overwrite_ids:
		if oid not in active_ids:
			deleted_ids.append(oid)

	var channel_id: String = _channel.get("id", "")
	var result: RestResult = await Client.admin.update_channel_overwrites(
		channel_id, overwrites, deleted_ids
	)

	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var err_msg: String = "Failed to update permissions"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_close()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
