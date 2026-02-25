extends ColorRect

## Permission overwrite states
enum OverwriteState { INHERIT, ALLOW, DENY }

const PermOverwriteRowScene := preload("res://scenes/admin/perm_overwrite_row.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

const SELECTED_BG := Color(0.25, 0.27, 0.3, 1.0)

# Permissions only relevant to voice channels
const VOICE_ONLY_PERMS := [
	"connect", "speak", "mute_members", "deafen_members",
	"move_members", "use_vad", "priority_speaker", "stream",
]

# Permissions only relevant to text channels
const TEXT_ONLY_PERMS := [
	"send_messages", "send_tts", "manage_messages",
	"embed_links", "attach_files", "read_history",
	"mention_everyone", "use_external_emojis",
	"manage_threads", "create_threads",
	"use_external_stickers", "send_in_threads",
]

var _channel: Dictionary = {}
var _space_id: String = ""
var _selected_role_id: String = ""
# entity_id -> { perm_name -> OverwriteState }
var _overwrite_data: Dictionary = {}
var _perm_rows: Dictionary = {} # perm_name -> PermOverwriteRow
var _role_buttons: Dictionary = {} # entity_id -> Button
# IDs that had overwrites when the dialog was opened
var _original_overwrite_ids: Array = []
# entity_id -> "role" | "user"
var _overwrite_types: Dictionary = {}
# Snapshot of loaded overwrites for dirty tracking
var _original_overwrite_data: Dictionary = {}
var _original_overwrite_types: Dictionary = {}

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
	_close_btn.pressed.connect(_try_close)
	_save_btn.pressed.connect(_on_save)
	_reset_btn.pressed.connect(_on_reset)

func setup(channel: Dictionary, space_id: String) -> void:
	_channel = channel
	_space_id = space_id
	_title.text = "Permissions: #%s" % channel.get("name", "")
	_load_overwrites()
	# Snapshot for dirty tracking
	_original_overwrite_data = _overwrite_data.duplicate(true)
	_original_overwrite_types = _overwrite_types.duplicate(true)
	_rebuild_role_list()

func _load_overwrites() -> void:
	_overwrite_data.clear()
	_original_overwrite_ids.clear()
	_overwrite_types.clear()
	# Load existing overwrites from channel data
	var overwrites: Array = _channel.get("permission_overwrites", [])
	for ow in overwrites:
		var ow_dict: Dictionary = ow if ow is Dictionary else {}
		var ow_id: String = ow_dict.get("id", "")
		if ow_id.is_empty():
			continue
		_original_overwrite_ids.append(ow_id)
		_overwrite_types[ow_id] = ow_dict.get("type", "role")
		var data: Dictionary = {}
		for perm in AccordPermission.all():
			if perm in ow_dict.get("allow", []):
				data[perm] = OverwriteState.ALLOW
			elif perm in ow_dict.get("deny", []):
				data[perm] = OverwriteState.DENY
			else:
				data[perm] = OverwriteState.INHERIT
		_overwrite_data[ow_id] = data

func _rebuild_role_list() -> void:
	for child in _role_list.get_children():
		child.queue_free()
	_role_buttons.clear()

	# Role overwrites
	var roles: Array = Client.get_roles_for_space(_space_id)
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
		btn.pressed.connect(_on_entity_selected.bind(rid, "role"))
		_role_list.add_child(btn)
		_role_buttons[rid] = btn
		if not _overwrite_types.has(rid):
			_overwrite_types[rid] = "role"

	# Separator before member overwrites
	var user_ids: Array = []
	for eid in _overwrite_types:
		if _overwrite_types[eid] == "user":
			user_ids.append(eid)

	if user_ids.size() > 0 or true:
		var sep := HSeparator.new()
		_role_list.add_child(sep)

		var member_label := Label.new()
		member_label.text = "MEMBERS"
		member_label.add_theme_color_override(
			"font_color", Color(0.7, 0.7, 0.7, 1)
		)
		member_label.add_theme_font_size_override("font_size", 11)
		_role_list.add_child(member_label)

	# Existing user-type overwrites
	for uid in user_ids:
		_add_member_button(uid)

	# "+ Add Member" button
	var add_btn := Button.new()
	add_btn.flat = true
	add_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_btn.custom_minimum_size = Vector2(140, 28)
	add_btn.text = "+ Add Member"
	add_btn.add_theme_color_override(
		"font_color", Color(0.345, 0.396, 0.949, 1)
	)
	add_btn.pressed.connect(_on_add_member_overwrite)
	_role_list.add_child(add_btn)

	_update_role_selection()

func _add_member_button(user_id: String) -> void:
	var btn := Button.new()
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(140, 28)

	var members: Array = Client.get_members_for_space(_space_id)
	var display_name: String = user_id
	for m in members:
		if m.get("id", "") == user_id:
			display_name = m.get("display_name", user_id)
			break

	btn.text = display_name
	btn.add_theme_color_override(
		"font_color", Color(0.8, 0.8, 0.9, 1)
	)
	btn.pressed.connect(_on_entity_selected.bind(user_id, "user"))
	_role_list.add_child(btn)
	_role_buttons[user_id] = btn

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

func _on_entity_selected(
	entity_id: String, entity_type: String
) -> void:
	_selected_role_id = entity_id
	_error_label.visible = false
	if not _overwrite_types.has(entity_id):
		_overwrite_types[entity_id] = entity_type
	if not _overwrite_data.has(entity_id):
		var data: Dictionary = {}
		for perm in AccordPermission.all():
			data[perm] = OverwriteState.INHERIT
		_overwrite_data[entity_id] = data
	_update_role_selection()
	_rebuild_perm_list()

func _on_add_member_overwrite() -> void:
	# Create a popup with a search input for member selection
	var popup := PopupPanel.new()
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(200, 200)

	var search := LineEdit.new()
	search.placeholder_text = "Search members..."
	search.custom_minimum_size = Vector2(0, 32)
	vbox.add_child(search)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var member_list := VBoxContainer.new()
	member_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(member_list)

	popup.add_child(vbox)
	add_child(popup)

	var members: Array = Client.get_members_for_space(_space_id)

	var build_list := func(query: String) -> void:
		for child in member_list.get_children():
			child.queue_free()
		var q := query.strip_edges().to_lower()
		for m in members:
			var uid: String = m.get("id", "")
			var dname: String = m.get("display_name", "")
			if _overwrite_data.has(uid) \
					and _overwrite_types.get(uid, "") == "user":
				continue  # Already has overwrite
			if not q.is_empty() and not dname.to_lower().contains(q):
				continue
			var btn := Button.new()
			btn.flat = true
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.text = dname
			btn.pressed.connect(func():
				_overwrite_types[uid] = "user"
				var data: Dictionary = {}
				for perm in AccordPermission.all():
					data[perm] = OverwriteState.INHERIT
				_overwrite_data[uid] = data
				popup.queue_free()
				_rebuild_role_list()
				_on_entity_selected(uid, "user")
			)
			member_list.add_child(btn)

	build_list.call("")
	search.text_changed.connect(func(text: String):
		build_list.call(text)
	)

	popup.popup_centered(Vector2i(220, 280))

func _perms_for_channel_type() -> Array:
	var ch_type: int = _channel.get("type", 0)
	var all_perms: Array = AccordPermission.all()
	match ch_type:
		ClientModels.ChannelType.VOICE:
			return all_perms.filter(func(p: String):
				return p not in TEXT_ONLY_PERMS
			)
		ClientModels.ChannelType.TEXT, \
		ClientModels.ChannelType.ANNOUNCEMENT, \
		ClientModels.ChannelType.FORUM:
			return all_perms.filter(func(p: String):
				return p not in VOICE_ONLY_PERMS
			)
		_:
			return all_perms

func _rebuild_perm_list() -> void:
	for child in _perm_list.get_children():
		child.queue_free()
	_perm_rows.clear()

	if _selected_role_id.is_empty():
		return

	var data: Dictionary = _overwrite_data.get(_selected_role_id, {})

	for perm in _perms_for_channel_type():
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
	# Reset this entity to all INHERIT
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
	for entity_id in _overwrite_data:
		var data: Dictionary = _overwrite_data[entity_id]
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
			active_ids.append(entity_id)
			overwrites.append({
				"id": entity_id,
				"type": _overwrite_types.get(entity_id, "role"),
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
		queue_free()

func _is_dirty() -> bool:
	# Check if overwrite data differs from the original snapshot
	if _overwrite_data.size() != _original_overwrite_data.size():
		return true
	if _overwrite_types.size() != _original_overwrite_types.size():
		return true
	for eid in _overwrite_data:
		if not _original_overwrite_data.has(eid):
			return true
		var cur: Dictionary = _overwrite_data[eid]
		var orig: Dictionary = _original_overwrite_data[eid]
		if cur != orig:
			return true
	for eid in _overwrite_types:
		if _overwrite_types[eid] != _original_overwrite_types.get(
			eid, ""
		):
			return true
	return false

func _try_close() -> void:
	if _is_dirty():
		var dialog := ConfirmDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(
			"Unsaved Changes",
			"You have unsaved permission changes. "
			+ "Discard them?",
			"Discard",
			true,
		)
		dialog.confirmed.connect(func(): queue_free())
	else:
		queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()
