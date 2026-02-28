extends HBoxContainer

signal space_pressed(space_id: String)

const SpaceSettingsScene := preload("res://scenes/admin/space_settings_dialog.tscn")
const ChannelMgmtScene := preload("res://scenes/admin/channel_management_dialog.tscn")
const RoleMgmtScene := preload("res://scenes/admin/role_management_dialog.tscn")
const BanListScene := preload("res://scenes/admin/ban_list_dialog.tscn")
const InviteMgmtScene := preload("res://scenes/admin/invite_management_dialog.tscn")
const EmojiMgmtScene := preload("res://scenes/admin/emoji_management_dialog.tscn")
const AuditLogScene := preload("res://scenes/admin/audit_log_dialog.tscn")
const SoundboardMgmtScene := preload("res://scenes/admin/soundboard_management_dialog.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ImposterPickerScene := preload("res://scenes/admin/imposter_picker_dialog.tscn")

var space_id: String = ""
var space_name: String = ""
var is_active: bool = false
var _is_hovered: bool = false
var _has_unread: bool = false
var _is_disconnected: bool = false
var _server_index: int = -1

var _context_menu: PopupMenu
var _status_dot: ColorRect
var _drop_above: bool = false
var _drop_hovered: bool = false

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
	icon_button.set_drag_forwarding(_space_get_drag_data, _space_can_drop_data, _space_drop_data)

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
	AppState.config_changed.connect(_on_config_changed)

func setup(data: Dictionary) -> void:
	space_id = data.get("id", "")
	space_name = data.get("name", "")
	avatar_rect.set_avatar_color(data.get("icon_color", Color.GRAY))
	icon_button.tooltip_text = space_name

	if space_name.length() > 0:
		avatar_rect.set_letter(space_name[0].to_upper())
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

	_is_disconnected = data.get("disconnected", false)
	_server_index = data.get("server_index", -1)
	if _is_disconnected:
		icon_button.modulate = Color(0.4, 0.4, 0.4)
		icon_button.tooltip_text = space_name + " (Disconnected)"
	else:
		_update_muted_visual()

func set_active(active: bool) -> void:
	is_active = active
	if pill:
		if active:
			pill.set_state_animated(pill.PillState.ACTIVE)
			avatar_rect.tween_radius(0.5, 0.3)
		else:
			if not _is_hovered:
				avatar_rect.tween_radius(0.3, 0.5)
			if _has_unread:
				pill.set_state_animated(pill.PillState.UNREAD)
			else:
				pill.set_state_animated(pill.PillState.HIDDEN)

func _on_pressed() -> void:
	if _is_disconnected:
		if _server_index >= 0:
			Client._auto_reconnect_attempted.erase(
				_server_index
			)
			Client.reconnect_server(_server_index)
		return
	space_pressed.emit(space_id)

func _on_hover_enter() -> void:
	_is_hovered = true
	if not is_active:
		avatar_rect.tween_radius(0.5, 0.3)

func _on_hover_exit() -> void:
	_is_hovered = false
	if not is_active:
		avatar_rect.tween_radius(0.3, 0.5)

func _on_button_down() -> void:
	if not is_active:
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

	if _is_disconnected:
		_context_menu.add_item("Reconnect", 0)
		_context_menu.add_separator()
		_context_menu.add_item("Remove Server", 2)
		_context_menu.hide()
		_context_menu.position = pos
		_context_menu.popup()
		return

	if Client.has_permission(space_id, AccordPermission.MANAGE_SPACE):
		_context_menu.add_item("Space Settings", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		_context_menu.add_item("Channels", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MANAGE_ROLES):
		_context_menu.add_item("Roles", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.BAN_MEMBERS):
		_context_menu.add_item("Bans", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.CREATE_INVITES):
		_context_menu.add_item("Invites", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.MANAGE_EMOJIS):
		_context_menu.add_item("Emojis", idx)
		idx += 1

	if Client.has_permission(space_id, AccordPermission.VIEW_AUDIT_LOG):
		_context_menu.add_item("Audit Log", idx)
		idx += 1

	if (Client.has_permission(space_id, AccordPermission.MANAGE_SOUNDBOARD)
			or Client.has_permission(space_id, AccordPermission.USE_SOUNDBOARD)):
		_context_menu.add_item("Soundboard", idx)
		idx += 1

	var can_manage_roles: bool = Client.has_permission(
		space_id, AccordPermission.MANAGE_ROLES
	)
	if not AppState.is_imposter_mode and can_manage_roles:
		_context_menu.add_item("View As...", idx)
		idx += 1

	var status := Client.get_space_connection_status(space_id)
	if status == "disconnected" or status == "error":
		_context_menu.add_item("Reconnect", idx)
		idx += 1

	# Account Settings
	_context_menu.add_item("Account Settings", idx)
	idx += 1

	# Mute toggle
	if Config.is_server_muted(space_id):
		_context_menu.add_item("Unmute Server", idx)
	else:
		_context_menu.add_item("Mute Server", idx)
	idx += 1

	# Folder management
	var current_folder: String = Config.get_space_folder(space_id)
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

	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	var label: String = _context_menu.get_item_text(_context_menu.get_item_index(id))
	match label:
		"Space Settings":
			var dialog := SpaceSettingsScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Channels":
			var dialog := ChannelMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Roles":
			var dialog := RoleMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Bans":
			var dialog := BanListScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Invites":
			var dialog := InviteMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Emojis":
			var dialog := EmojiMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Audit Log":
			var dialog := AuditLogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Soundboard":
			var dialog := SoundboardMgmtScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"View As...":
			var dialog := ImposterPickerScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(space_id)
		"Account Settings":
			var ServerSettingsScene: PackedScene = load(
				"res://scenes/user/server_settings.tscn"
			)
			if ServerSettingsScene:
				var settings: ColorRect = ServerSettingsScene.instantiate()
				settings.setup(space_id)
				get_tree().root.add_child(settings)
		"Reconnect":
			var conn_idx: int = _server_index \
				if _is_disconnected \
				else Client.get_conn_index_for_space(space_id)
			if conn_idx >= 0:
				Client._auto_reconnect_attempted.erase(conn_idx)
				Client.reconnect_server(conn_idx)
		"Mute Server":
			Config.set_server_muted(space_id, true)
			_update_muted_visual()
		"Unmute Server":
			Config.set_server_muted(space_id, false)
			_update_muted_visual()
		"Move to Folder":
			_show_folder_dialog()
		"Remove from Folder":
			# Find which folder this space is in and insert standalone entry at same position
			var cur_folder: String = Config.get_space_folder(space_id)
			var order: Array = Config.get_space_order()
			var new_order: Array = []
			for entry in order:
				new_order.append(entry)
				if entry is Dictionary and entry.get("type") == "folder" and entry.get("name") == cur_folder:
					new_order.append({"type": "space", "id": space_id})
			Config.set_space_order(new_order)
			Config.set_space_folder(space_id, "")
			Client.update_space_folder(space_id, "")
		"Remove Server":
			var dialog := ConfirmDialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(
				"Remove Server",
				"Are you sure you want to remove '%s' from your server list?" % space_name,
				"Remove",
				true
			)
			dialog.confirmed.connect(func():
				if _is_disconnected and _server_index >= 0:
					Config.remove_server(_server_index)
					AppState.spaces_updated.emit()
				else:
					Client.disconnect_server(space_id)
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
			# Remove standalone entry from saved order
			var order: Array = Config.get_space_order()
			var cleaned: Array = []
			for entry in order:
				if entry is Dictionary and entry.get("type") == "space" and entry.get("id") == space_id:
					continue
				cleaned.append(entry)
			Config.set_space_order(cleaned)
			Config.set_space_folder(space_id, folder_text)
			Client.update_space_folder(space_id, folder_text)
		dialog.queue_free()
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
	)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_config_changed(section: String, key: String) -> void:
	if section == "muted_servers" and key == space_id:
		_update_muted_visual()

func _update_muted_visual() -> void:
	if Config.is_server_muted(space_id):
		icon_button.modulate = Color(0.5, 0.5, 0.5)
		icon_button.tooltip_text = space_name + " (Muted)"
	else:
		icon_button.modulate = Color(1, 1, 1)
		icon_button.tooltip_text = space_name

# --- Connection Status Dot ---

func _on_connection_changed(gid: String, _a = null, _b = null) -> void:
	if gid == space_id:
		_update_status_dot()

func _on_connection_changed_1(gid: String) -> void:
	if gid == space_id:
		_update_status_dot()

func _on_connection_changed_3(gid: String, _a: int, _b: int) -> void:
	if gid == space_id:
		_update_status_dot()

func _update_status_dot() -> void:
	var status := Client.get_space_connection_status(space_id)
	match status:
		"disconnected", "reconnecting":
			_status_dot.color = Color(0.9, 0.75, 0.1)
			_status_dot.visible = true
		"error":
			_status_dot.color = Color(0.9, 0.3, 0.3)
			_status_dot.visible = true
		_:
			_status_dot.visible = false

# --- Drag-and-drop reordering ---

func _is_top_level_in_space_bar() -> bool:
	var parent := get_parent()
	return parent != null and parent.name == "GuildList" and parent.get_parent().name == "VBox"

func _space_get_drag_data(_at_position: Vector2) -> Variant:
	if not _is_top_level_in_space_bar():
		return null
	var preview := Label.new()
	preview.text = space_name
	preview.add_theme_font_size_override("font_size", 11)
	preview.add_theme_color_override("font_color", Color(1, 1, 1))
	set_drag_preview(preview)
	return {"type": "space_bar_item", "item_type": "space", "space_id": space_id, "source_node": self}

func _space_can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "space_bar_item":
		_clear_drop_indicator()
		return false
	var source: Control = data.get("source_node")
	if source == self:
		_clear_drop_indicator()
		return false
	if not _is_top_level_in_space_bar():
		_clear_drop_indicator()
		return false
	if source == null or source.get_parent() != get_parent():
		_clear_drop_indicator()
		return false
	_drop_above = at_position.y < size.y / 2.0
	_drop_hovered = true
	queue_redraw()
	return true

func _space_drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_indicator()
	var source: Control = data.get("source_node")
	if source == null or source.get_parent() != get_parent():
		return
	var container := get_parent()
	var target_idx: int = get_index()
	if not _drop_above:
		target_idx += 1
	container.move_child(source, target_idx)
	_save_space_bar_order()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_drop_indicator()

func _clear_drop_indicator() -> void:
	if _drop_hovered:
		_drop_hovered = false
		queue_redraw()

func _draw() -> void:
	if not _drop_hovered:
		return
	var line_color := Color(0.34, 0.52, 0.89)
	if _drop_above:
		draw_line(Vector2(0, 0), Vector2(size.x, 0), line_color, 2.0)
	else:
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), line_color, 2.0)

static func _save_space_bar_order_from(container: Node) -> void:
	var order: Array = []
	for child in container.get_children():
		if child is HBoxContainer and "space_id" in child and not child.space_id.is_empty():
			if not child.space_id.begins_with("__pending_"):
				order.append({"type": "space", "id": child.space_id})
		elif child is VBoxContainer and "folder_name" in child and not child.folder_name.is_empty():
			order.append({"type": "folder", "name": child.folder_name})
	Config.set_space_order(order)

func _save_space_bar_order() -> void:
	_save_space_bar_order_from(get_parent())
