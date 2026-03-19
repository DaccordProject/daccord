extends Control

const SpaceSettingsScene := preload("res://scenes/admin/space_settings_dialog.tscn")
const ChannelMgmtScene := preload("res://scenes/admin/channel_management_dialog.tscn")
const RoleMgmtScene := preload("res://scenes/admin/role_management_dialog.tscn")
const BanListScene := preload("res://scenes/admin/ban_list_dialog.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const EmojiMgmtScene := preload("res://scenes/admin/emoji_management_dialog.tscn")
const AuditLogScene := preload("res://scenes/admin/audit_log_dialog.tscn")
const ReportListScene := preload("res://scenes/admin/report_list_dialog.tscn")
const SoundboardMgmtScene := preload("res://scenes/admin/soundboard_management_dialog.tscn")
const ImposterPickerScene := preload("res://scenes/admin/imposter_picker_dialog.tscn")

var _space_id: String = ""
var _admin_menu: PopupMenu
var _has_admin: bool = false

@onready var banner_rect: ColorRect = $BannerRect
@onready var space_name_label: Label = $GuildName
@onready var settings_button: TextureButton = $SettingsButton

func _ready() -> void:
	add_to_group("themed")
	_admin_menu = PopupMenu.new()
	_admin_menu.id_pressed.connect(_on_admin_menu_pressed)
	add_child(_admin_menu)
	settings_button.pressed.connect(_show_admin_menu)
	AppState.imposter_mode_changed.connect(_on_imposter_mode_changed)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	_apply_compact_height(AppState.current_layout_mode)

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_compact_height(mode)

func _apply_compact_height(mode: AppState.LayoutMode) -> void:
	if mode == AppState.LayoutMode.COMPACT:
		custom_minimum_size.y = 48.0
	else:
		custom_minimum_size.y = 80.0

func _apply_theme() -> void:
	space_name_label.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))

func setup(space_data: Dictionary) -> void:
	_space_id = space_data.get("id", "")
	space_name_label.text = space_data.get("name", "")
	ThemeManager.style_label(space_name_label, 16, "text_white")
	banner_rect.color = space_data.get("icon_color", ThemeManager.get_color("modal_bg")).darkened(0.3)

	_has_admin = _has_any_admin_perm()
	settings_button.visible = _has_admin

func _has_any_admin_perm() -> bool:
	if _space_id.is_empty():
		return false
	return (
		Client.has_permission(_space_id, AccordPermission.MANAGE_SPACE) or
		Client.has_permission(_space_id, AccordPermission.MANAGE_CHANNELS) or
		Client.has_permission(_space_id, AccordPermission.MANAGE_ROLES) or
		Client.has_permission(_space_id, AccordPermission.BAN_MEMBERS) or
		Client.has_permission(_space_id, AccordPermission.MANAGE_EMOJIS) or
		Client.has_permission(_space_id, AccordPermission.VIEW_AUDIT_LOG) or
		Client.has_permission(_space_id, AccordPermission.MODERATE_MEMBERS) or
		Client.has_permission(_space_id, AccordPermission.MANAGE_SOUNDBOARD) or
		Client.has_permission(_space_id, AccordPermission.USE_SOUNDBOARD)
	)

func _show_admin_menu() -> void:
	_admin_menu.clear()
	var idx: int = 0

	if Client.has_permission(_space_id, AccordPermission.MANAGE_SPACE):
		_admin_menu.add_item("Space Settings", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.MANAGE_CHANNELS):
		_admin_menu.add_item("Channels", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.MANAGE_ROLES):
		_admin_menu.add_item("Roles", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.BAN_MEMBERS):
		_admin_menu.add_item("Bans", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.MANAGE_CHANNELS):
		_admin_menu.add_item("Invites", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.MANAGE_EMOJIS):
		_admin_menu.add_item("Emojis", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.VIEW_AUDIT_LOG):
		_admin_menu.add_item("Audit Log", idx)
		idx += 1

	if Client.has_permission(_space_id, AccordPermission.MODERATE_MEMBERS):
		_admin_menu.add_item("Reports", idx)
		idx += 1

	if (Client.has_permission(_space_id, AccordPermission.MANAGE_SOUNDBOARD)
			or Client.has_permission(_space_id, AccordPermission.USE_SOUNDBOARD)):
		_admin_menu.add_item("Soundboard", idx)
		idx += 1

	var can_manage: bool = Client.has_permission(
		_space_id, AccordPermission.MANAGE_ROLES
	)
	if not AppState.is_imposter_mode and can_manage:
		_admin_menu.add_item("View As...", idx)
		idx += 1

	if idx == 0:
		return

	var pos := global_position + Vector2(0, size.y)
	_admin_menu.hide()
	_admin_menu.position = Vector2i(int(pos.x), int(pos.y))
	_admin_menu.popup()

func _on_admin_menu_pressed(id: int) -> void:
	var label: String = _admin_menu.get_item_text(_admin_menu.get_item_index(id))
	match label:
		"Space Settings":
			var dialog := SpaceSettingsScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Channels":
			var dialog := ChannelMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Roles":
			var dialog := RoleMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Bans":
			var dialog := BanListScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Invites":
			var dialog := InviteMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Emojis":
			var dialog := EmojiMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Audit Log":
			var dialog := AuditLogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Reports":
			var dialog := ReportListScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"Soundboard":
			var dialog := SoundboardMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)
		"View As...":
			var dialog := ImposterPickerScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(_space_id)

func _on_imposter_mode_changed(_active: bool) -> void:
	_has_admin = _has_any_admin_perm()
	settings_button.visible = _has_admin
