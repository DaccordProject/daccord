extends HBoxContainer

signal guild_pressed(guild_id: String)

const SpaceSettingsScene := preload("res://scenes/admin/space_settings_dialog.tscn")
const ChannelMgmtScene := preload("res://scenes/admin/channel_management_dialog.tscn")
const RoleMgmtScene := preload("res://scenes/admin/role_management_dialog.tscn")
const BanListScene := preload("res://scenes/admin/ban_list_dialog.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const EmojiMgmtScene := preload("res://scenes/admin/emoji_management_dialog.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var guild_id: String = ""
var guild_name: String = ""
var is_active: bool = false
var _has_unread: bool = false

var _context_menu: PopupMenu

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $ButtonContainer/IconButton
@onready var avatar_rect: ColorRect = $ButtonContainer/IconButton/AvatarRect
@onready var mention_badge: PanelContainer = $ButtonContainer/BadgeAnchor/MentionBadge

func _ready() -> void:
	icon_button.pressed.connect(_on_pressed)
	icon_button.mouse_entered.connect(_on_hover_enter)
	icon_button.mouse_exited.connect(_on_hover_exit)
	icon_button.button_down.connect(_on_button_down)
	icon_button.button_up.connect(_on_button_up)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	icon_button.gui_input.connect(_on_icon_gui_input)

func setup(data: Dictionary) -> void:
	guild_id = data.get("id", "")
	guild_name = data.get("name", "")
	avatar_rect.set_avatar_color(data.get("icon_color", Color.GRAY))
	icon_button.tooltip_text = guild_name

	if guild_name.length() > 0:
		avatar_rect.set_letter(guild_name[0].to_upper())
	else:
		avatar_rect.set_letter("")

	_has_unread = data.get("unread", false)
	var mentions: int = data.get("mentions", 0)

	mention_badge.count = mentions
	if is_active:
		pill.pill_state = pill.PillState.ACTIVE
	elif _has_unread:
		pill.pill_state = pill.PillState.UNREAD
	else:
		pill.pill_state = pill.PillState.HIDDEN

func set_active(active: bool) -> void:
	is_active = active
	if pill:
		if active:
			pill.set_state_animated(pill.PillState.ACTIVE)
		elif _has_unread:
			pill.set_state_animated(pill.PillState.UNREAD)
		else:
			pill.set_state_animated(pill.PillState.HIDDEN)

func _on_pressed() -> void:
	guild_pressed.emit(guild_id)

func _on_hover_enter() -> void:
	avatar_rect.tween_radius(0.5, 0.3)

func _on_hover_exit() -> void:
	if not is_active:
		avatar_rect.tween_radius(0.3, 0.5)

func _on_button_down() -> void:
	avatar_rect.tween_radius(0.5, 0.3)

func _on_button_up() -> void:
	if not is_active:
		avatar_rect.tween_radius(0.3, 0.5)

func _on_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	var idx: int = 0

	if Client.has_permission(guild_id, AccordPermission.MANAGE_SPACE):
		_context_menu.add_item("Space Settings", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.MANAGE_CHANNELS):
		_context_menu.add_item("Channels", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.MANAGE_ROLES):
		_context_menu.add_item("Roles", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.BAN_MEMBERS):
		_context_menu.add_item("Bans", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.CREATE_INVITES):
		_context_menu.add_item("Invites", idx)
		idx += 1

	if Client.has_permission(guild_id, AccordPermission.MANAGE_EMOJIS):
		_context_menu.add_item("Emojis", idx)
		idx += 1

	if idx > 0:
		_context_menu.add_separator()
		idx += 1

	_context_menu.add_item("Remove Server", idx)

	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	var label: String = _context_menu.get_item_text(_context_menu.get_item_index(id))
	match label:
		"Space Settings":
			var dialog := SpaceSettingsScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Channels":
			var dialog := ChannelMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Roles":
			var dialog := RoleMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Bans":
			var dialog := BanListScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Invites":
			var dialog := InviteMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Emojis":
			var dialog := EmojiMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(guild_id)
		"Remove Server":
			var dialog := ConfirmDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(
				"Remove Server",
				"Are you sure you want to remove '%s' from your server list?" % guild_name,
				"Remove",
				true
			)
			dialog.confirmed.connect(func():
				Client.disconnect_server(guild_id)
			)
