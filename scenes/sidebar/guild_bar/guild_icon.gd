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
var _status_dot: ColorRect

@onready var pill: ColorRect = $PillContainer/Pill
@onready var icon_button: Button = $ButtonContainer/IconButton
@onready var avatar_rect: ColorRect = $ButtonContainer/IconButton/AvatarRect
@onready var mention_badge: PanelContainer = $ButtonContainer/BadgeAnchor/MentionBadge
@onready var button_container: Control = $ButtonContainer

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

	# Status dot (bottom-right of icon)
	_status_dot = ColorRect.new()
	_status_dot.custom_minimum_size = Vector2(10, 10)
	_status_dot.size = Vector2(10, 10)
	_status_dot.position = Vector2(36, 36)
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_dot.visible = false
	button_container.add_child(_status_dot)

	AppState.server_disconnected.connect(_on_connection_changed)
	AppState.server_reconnecting.connect(_on_connection_changed_3)
	AppState.server_reconnected.connect(_on_connection_changed_1)
	AppState.server_connection_failed.connect(_on_connection_changed)

func setup(data: Dictionary) -> void:
	guild_id = data.get("id", "")
	guild_name = data.get("name", "")
	avatar_rect.set_avatar_color(data.get("icon_color", Color.GRAY))
	icon_button.tooltip_text = guild_name

	if guild_name.length() > 0:
		avatar_rect.set_letter(guild_name[0].to_upper())
	else:
		avatar_rect.set_letter("")

	var icon_url = data.get("icon", null)
	if icon_url is String and not icon_url.is_empty():
		avatar_rect.set_avatar_url(icon_url)

	_has_unread = data.get("unread", false)
	var mentions: int = data.get("mentions", 0)

	mention_badge.count = mentions
	if is_active:
		pill.pill_state = pill.PillState.ACTIVE
	elif _has_unread:
		pill.pill_state = pill.PillState.UNREAD
	else:
		pill.pill_state = pill.PillState.HIDDEN

	_update_muted_visual()

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

	var status := Client.get_guild_connection_status(guild_id)
	if status == "disconnected" or status == "error":
		_context_menu.add_item("Reconnect", idx)
		idx += 1

	# Mute toggle
	if Config.is_server_muted(guild_id):
		_context_menu.add_item("Unmute Server", idx)
	else:
		_context_menu.add_item("Mute Server", idx)
	idx += 1

	# Folder management
	var current_folder: String = Config.get_guild_folder(guild_id)
	if current_folder.is_empty():
		_context_menu.add_item("Move to Folder", idx)
		idx += 1
	else:
		_context_menu.add_item("Remove from Folder", idx)
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
		"Reconnect":
			var conn_idx := Client.get_conn_index_for_guild(guild_id)
			if conn_idx >= 0:
				Client._auto_reconnect_attempted.erase(conn_idx)
				Client.reconnect_server(conn_idx)
		"Mute Server":
			Config.set_server_muted(guild_id, true)
			_update_muted_visual()
		"Unmute Server":
			Config.set_server_muted(guild_id, false)
			_update_muted_visual()
		"Move to Folder":
			_show_folder_dialog()
		"Remove from Folder":
			Config.set_guild_folder(guild_id, "")
			Client.update_guild_folder(guild_id, "")
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

func _show_folder_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Move to Folder"
	dialog.ok_button_text = "Move"

	var vbox := VBoxContainer.new()

	var existing_folders: Array = Config.get_all_folder_names()
	var line_edit := LineEdit.new()
	line_edit.placeholder_text = "Folder name"
	line_edit.custom_minimum_size = Vector2(200, 0)

	if existing_folders.size() > 0:
		var label := Label.new()
		label.text = "Existing folders:"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		vbox.add_child(label)
		for fname in existing_folders:
			var btn := Button.new()
			btn.text = fname
			btn.flat = true
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(func(): line_edit.text = fname)
			vbox.add_child(btn)
		var sep := HSeparator.new()
		vbox.add_child(sep)

	var new_label := Label.new()
	new_label.text = "Folder name:"
	new_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(new_label)
	vbox.add_child(line_edit)

	dialog.add_child(vbox)
	dialog.confirmed.connect(func():
		var folder_text: String = line_edit.text.strip_edges()
		if not folder_text.is_empty():
			Config.set_guild_folder(guild_id, folder_text)
			Client.update_guild_folder(guild_id, folder_text)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _update_muted_visual() -> void:
	if Config.is_server_muted(guild_id):
		icon_button.modulate = Color(0.5, 0.5, 0.5)
		icon_button.tooltip_text = guild_name + " (Muted)"
	else:
		icon_button.modulate = Color(1, 1, 1)
		icon_button.tooltip_text = guild_name

# --- Connection Status Dot ---

func _on_connection_changed(gid: String, _a = null, _b = null) -> void:
	if gid == guild_id:
		_update_status_dot()

func _on_connection_changed_1(gid: String) -> void:
	if gid == guild_id:
		_update_status_dot()

func _on_connection_changed_3(gid: String, _a: int, _b: int) -> void:
	if gid == guild_id:
		_update_status_dot()

func _update_status_dot() -> void:
	var status := Client.get_guild_connection_status(guild_id)
	match status:
		"disconnected", "reconnecting":
			_status_dot.color = Color(0.9, 0.75, 0.1)
			_status_dot.visible = true
		"error":
			_status_dot.color = Color(0.9, 0.3, 0.3)
			_status_dot.visible = true
		_:
			_status_dot.visible = false
