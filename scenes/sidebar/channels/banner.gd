extends Control

const SpaceSettingsScene := preload("res://scenes/admin/space_settings_dialog.tscn")
const ChannelMgmtScene := preload("res://scenes/admin/channel_management_dialog.tscn")
const RoleMgmtScene := preload("res://scenes/admin/role_management_dialog.tscn")
const BanListScene := preload("res://scenes/admin/ban_list_dialog.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const EmojiMgmtScene := preload("res://scenes/admin/emoji_management_dialog.tscn")
const SoundboardMgmtScene := preload("res://scenes/admin/soundboard_management_dialog.tscn")

var _guild_id: String = ""
var _admin_menu: PopupMenu
var _has_admin: bool = false

@onready var banner_rect: ColorRect = $BannerRect
@onready var guild_name_label: Label = $GuildName
@onready var dropdown_icon: Label = $DropdownIcon

func _ready() -> void:
	_admin_menu = PopupMenu.new()
	_admin_menu.id_pressed.connect(_on_admin_menu_pressed)
	add_child(_admin_menu)
	gui_input.connect(_on_banner_input)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func setup(guild_data: Dictionary) -> void:
	_guild_id = guild_data.get("id", "")
	guild_name_label.text = guild_data.get("name", "")
	guild_name_label.add_theme_font_size_override("font_size", 16)
	guild_name_label.add_theme_color_override("font_color", Color.WHITE)
	banner_rect.color = guild_data.get("icon_color", Color(0.184, 0.192, 0.212)).darkened(0.3)

	_has_admin = _has_any_admin_perm()
	dropdown_icon.visible = _has_admin

func _has_any_admin_perm() -> bool:
	if _guild_id.is_empty():
		return false
	return (
		Client.has_permission(_guild_id, AccordPermission.MANAGE_SPACE) or
		Client.has_permission(_guild_id, AccordPermission.MANAGE_CHANNELS) or
		Client.has_permission(_guild_id, AccordPermission.MANAGE_ROLES) or
		Client.has_permission(_guild_id, AccordPermission.BAN_MEMBERS) or
		Client.has_permission(_guild_id, AccordPermission.CREATE_INVITES) or
		Client.has_permission(_guild_id, AccordPermission.MANAGE_EMOJIS) or
		Client.has_permission(_guild_id, AccordPermission.MANAGE_SOUNDBOARD) or
		Client.has_permission(_guild_id, AccordPermission.USE_SOUNDBOARD)
	)

func _on_banner_input(event: InputEvent) -> void:
	if not _has_admin:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_show_admin_menu()

func _show_admin_menu() -> void:
	_admin_menu.clear()
	var idx: int = 0

	if Client.has_permission(_guild_id, AccordPermission.MANAGE_SPACE):
		_admin_menu.add_item("Space Settings", idx)
		idx += 1

	if Client.has_permission(_guild_id, AccordPermission.MANAGE_CHANNELS):
		_admin_menu.add_item("Channels", idx)
		idx += 1

	if Client.has_permission(_guild_id, AccordPermission.MANAGE_ROLES):
		_admin_menu.add_item("Roles", idx)
		idx += 1

	if Client.has_permission(_guild_id, AccordPermission.BAN_MEMBERS):
		_admin_menu.add_item("Bans", idx)
		idx += 1

	if Client.has_permission(_guild_id, AccordPermission.CREATE_INVITES):
		_admin_menu.add_item("Invites", idx)
		idx += 1

	if Client.has_permission(_guild_id, AccordPermission.MANAGE_EMOJIS):
		_admin_menu.add_item("Emojis", idx)
		idx += 1

	if (Client.has_permission(_guild_id, AccordPermission.MANAGE_SOUNDBOARD)
			or Client.has_permission(_guild_id, AccordPermission.USE_SOUNDBOARD)):
		_admin_menu.add_item("Soundboard", idx)
		idx += 1

	if idx == 0:
		return

	var pos := global_position + Vector2(0, size.y)
	_admin_menu.position = Vector2i(int(pos.x), int(pos.y))
	_admin_menu.popup()

func _on_admin_menu_pressed(id: int) -> void:
	var label: String = _admin_menu.get_item_text(_admin_menu.get_item_index(id))
	match label:
		"Space Settings":
			var dialog := SpaceSettingsScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Channels":
			var dialog := ChannelMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Roles":
			var dialog := RoleMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Bans":
			var dialog := BanListScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Invites":
			var dialog := InviteMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Emojis":
			var dialog := EmojiMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
		"Soundboard":
			var dialog := SoundboardMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_guild_id)
