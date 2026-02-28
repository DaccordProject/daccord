extends Control

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const BanDialogScene := preload("res://scenes/admin/ban_dialog.tscn")
const ModerateMemberDialogScene := preload("res://scenes/admin/moderate_member_dialog.tscn")
const NicknameDialogScene := preload("res://scenes/admin/nickname_dialog.tscn")

var _member_data: Dictionary = {}
var _context_menu: PopupMenu
var _role_start_index: int = -1

@onready var avatar: ColorRect = $HBox/Avatar
@onready var display_name: Label = $HBox/DisplayName
@onready var status_dot: ColorRect = $HBox/StatusDot

func _ready() -> void:
	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	gui_input.connect(_on_gui_input)

func setup(data: Dictionary) -> void:
	_member_data = data
	var dn_text: String = data.get("display_name", "Unknown")
	if data.get("_is_owner", false):
		dn_text += " (Owner)"
	display_name.text = dn_text
	tooltip_text = data.get("display_name", "Unknown")
	avatar.set_avatar_color(data.get("color", Color(0.345, 0.396, 0.949)))
	var dn: String = data.get("display_name", "")
	if dn.length() > 0:
		avatar.set_letter(dn[0].to_upper())
	else:
		avatar.set_letter("")
	var avatar_url = data.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		avatar.set_avatar_url(avatar_url)

	var status: int = data.get("status", ClientModels.UserStatus.OFFLINE)
	status_dot.color = ClientModels.status_color(status)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var uid: String = _member_data.get("id", "")
			if not uid.is_empty():
				var pos := get_global_mouse_position()
				AppState.profile_card_requested.emit(uid, pos)

func _show_context_menu(pos: Vector2i) -> void:
	var user_id: String = _member_data.get("id", "")
	# Don't show menu for self
	if user_id == Client.current_user.get("id", ""):
		return

	var space_id: String = AppState.current_space_id
	if space_id.is_empty():
		return

	_context_menu.clear()
	_role_start_index = -1
	var idx: int = 0

	_context_menu.add_item("Message", idx)
	idx += 1

	if Client.has_permission(space_id, AccordPermission.KICK_MEMBERS):
		_context_menu.add_item("Kick", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.BAN_MEMBERS):
		_context_menu.add_item("Ban", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MODERATE_MEMBERS):
		_context_menu.add_item("Moderate", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MANAGE_NICKNAMES):
		_context_menu.add_item("Edit Nickname", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MANAGE_ROLES):
		var roles: Array = Client.get_roles_for_space(space_id)
		var member_roles: Array = _member_data.get("roles", [])
		var my_highest: int = Client.get_my_highest_role_position(space_id)
		if roles.size() > 0:
			_context_menu.add_separator("Roles")
			idx += 1
			_role_start_index = idx
			for role in roles:
				if role.get("position", 0) == 0:
					continue  # Skip @everyone
				_context_menu.add_check_item(role.get("name", ""), idx)
				var item_idx := _context_menu.get_item_index(idx)
				_context_menu.set_item_checked(
					item_idx,
					role.get("id", "") in member_roles
				)
				if role.get("position", 0) >= my_highest:
					_context_menu.set_item_disabled(item_idx, true)
					_context_menu.set_item_tooltip(
						item_idx,
						"Role is above your highest role"
					)
				idx += 1

	if _context_menu.item_count == 0:
		return

	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	var space_id: String = AppState.current_space_id
	var user_id: String = _member_data.get("id", "")
	var dname: String = _member_data.get("display_name", "Unknown")

	# Check if this is a role toggle
	if _role_start_index != -1 and id >= _role_start_index:
		_toggle_role(space_id, user_id, id)
		return

	var label: String = _context_menu.get_item_text(_context_menu.get_item_index(id))
	match label:
		"Message":
			Client.create_dm(user_id)
		"Kick":
			var dialog := ConfirmDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(
				"Kick %s" % dname,
				"Are you sure you want to kick %s from this server?" % dname,
				"Kick",
				true
			)
			dialog.confirmed.connect(func():
				var result: RestResult = await Client.admin.kick_member(
					space_id, user_id
				)
				if result == null or not result.ok:
					var err: String = "unknown error"
					if result != null and result.error:
						err = result.error.message
					push_warning(
						"[Kick] Failed to kick member: ", err
					)
			)
		"Ban":
			var dialog := BanDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id, user_id, dname)
		"Moderate":
			var dialog := ModerateMemberDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id, user_id, dname, _member_data)
		"Edit Nickname":
			var dialog := NicknameDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(
				space_id, user_id, dname,
				_member_data.get("nickname", "")
			)

func _toggle_role(space_id: String, user_id: String, id: int) -> void:
	var roles: Array = Client.get_roles_for_space(space_id)
	var role_idx: int = id - _role_start_index
	# Filter out @everyone to match the menu ordering
	var assignable_roles: Array = []
	for role in roles:
		if role.get("position", 0) != 0:
			assignable_roles.append(role)
	if role_idx < 0 or role_idx >= assignable_roles.size():
		return
	var role: Dictionary = assignable_roles[role_idx]
	var role_id: String = role.get("id", "")
	var member_roles: Array = _member_data.get("roles", [])

	# Disable the menu item during the API call
	var item_index := _context_menu.get_item_index(id)
	_context_menu.set_item_disabled(item_index, true)

	var result: RestResult
	if role_id in member_roles:
		result = await Client.admin.remove_member_role(space_id, user_id, role_id)
	else:
		result = await Client.admin.add_member_role(space_id, user_id, role_id)

	_context_menu.set_item_disabled(item_index, false)

	# Visual feedback flash
	if result != null and result.ok:
		_flash_feedback(Color(0.231, 0.647, 0.365, 0.3))
	else:
		_flash_feedback(Color(0.929, 0.259, 0.271, 0.3))
		# Revert checkbox on failure
		_context_menu.set_item_checked(item_index, role_id in member_roles)

func _flash_feedback(color: Color) -> void:
	if Config.get_reduced_motion():
		return
	var original_modulate := modulate
	var tween := create_tween()
	tween.tween_property(self, "modulate", color + Color(0.7, 0.7, 0.7, 0.7), 0.15)
	tween.tween_property(self, "modulate", original_modulate, 0.3)
