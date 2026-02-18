extends Control

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const BanDialogScene := preload("res://scenes/admin/ban_dialog.tscn")

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
	display_name.text = data.get("display_name", "Unknown")
	avatar.set_avatar_color(data.get("color", Color(0.345, 0.396, 0.949)))

	var status: int = data.get("status", ClientModels.UserStatus.OFFLINE)
	match status:
		ClientModels.UserStatus.ONLINE:
			status_dot.color = Color(0.231, 0.647, 0.365)
		ClientModels.UserStatus.IDLE:
			status_dot.color = Color(0.98, 0.659, 0.157)
		ClientModels.UserStatus.DND:
			status_dot.color = Color(0.929, 0.259, 0.271)
		ClientModels.UserStatus.OFFLINE:
			status_dot.color = Color(0.58, 0.608, 0.643)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	var user_id: String = _member_data.get("id", "")
	# Don't show menu for self
	if user_id == Client.current_user.get("id", ""):
		return

	var guild_id: String = AppState.current_guild_id
	if guild_id.is_empty():
		return

	_context_menu.clear()
	_role_start_index = -1
	var idx: int = 0

	if Client.has_permission(guild_id, AccordPermission.KICK_MEMBERS):
		_context_menu.add_item("Kick", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.BAN_MEMBERS):
		_context_menu.add_item("Ban", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.MANAGE_ROLES):
		var roles: Array = Client.get_roles_for_guild(guild_id)
		var member_roles: Array = _member_data.get("roles", [])
		if roles.size() > 0:
			_context_menu.add_separator("Roles")
			idx += 1
			_role_start_index = idx
			for role in roles:
				if role.get("position", 0) == 0:
					continue  # Skip @everyone
				_context_menu.add_check_item(role.get("name", ""), idx)
				_context_menu.set_item_checked(
					_context_menu.get_item_index(idx),
					role.get("id", "") in member_roles
				)
				idx += 1

	if _context_menu.item_count == 0:
		return

	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	var guild_id: String = AppState.current_guild_id
	var user_id: String = _member_data.get("id", "")
	var dname: String = _member_data.get("display_name", "Unknown")

	# Check if this is a role toggle
	if _role_start_index != -1 and id >= _role_start_index:
		_toggle_role(guild_id, user_id, id)
		return

	var label: String = _context_menu.get_item_text(_context_menu.get_item_index(id))
	match label:
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
				Client.kick_member(guild_id, user_id)
			)
		"Ban":
			var dialog := BanDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id, user_id, dname)

func _toggle_role(guild_id: String, user_id: String, id: int) -> void:
	var roles: Array = Client.get_roles_for_guild(guild_id)
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
	if role_id in member_roles:
		Client.remove_member_role(guild_id, user_id, role_id)
	else:
		Client.add_member_role(guild_id, user_id, role_id)
