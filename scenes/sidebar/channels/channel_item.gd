extends Button

signal channel_pressed(channel_id: String)

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ChannelEditScene := preload("res://scenes/admin/channel_edit_dialog.tscn")

var channel_id: String = ""
var space_id: String = ""
var _is_locked: bool = false
var _is_nsfw: bool = false
var _channel_data: Dictionary = {}
var _context_menu: PopupMenu
var _notification_submenu: PopupMenu
var _gear_btn: Button
var _drop_above: bool = false
var _drop_hovered: bool = false
var _has_unread: bool = false
var _is_active: bool = false

@onready var type_icon: TextureRect = $HBox/TypeIcon
@onready var channel_name: Label = $HBox/ChannelName
@onready var unread_dot: ColorRect = $HBox/UnreadDot
@onready var active_bg: ColorRect = $ActiveBg
@onready var active_pill: ColorRect = $ActivePill

func _ready() -> void:
	add_to_group("themed")
	pressed.connect(func(): channel_pressed.emit(channel_id))

	_notification_submenu = PopupMenu.new()
	_notification_submenu.name = "NotificationSubmenu"
	_notification_submenu.id_pressed.connect(_on_notification_submenu_id_pressed)
	_notification_submenu.add_radio_check_item("All Messages", 20)
	_notification_submenu.add_radio_check_item("Only Mentions", 21)
	_notification_submenu.add_radio_check_item("Muted", 22)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	_context_menu.add_child(_notification_submenu)
	add_child(_context_menu)

	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	active_bg.visible = false
	active_pill.visible = false
	AppState.channel_mutes_updated.connect(_on_mutes_updated)
	AppState.channel_notification_updated.connect(_on_notification_updated)

func _apply_theme() -> void:
	_apply_text_color()
	queue_redraw()

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	space_id = data.get("space_id", "")
	_channel_data = data
	channel_name.text = data.get("name", "")
	tooltip_text = data.get("name", "")

	# Locked channels are visible to admins in imposter mode but not interactive.
	_is_locked = data.get("locked", false)
	if _is_locked:
		type_icon.texture = IconEmoji.get_texture("lock")
		modulate = Color(1.0, 1.0, 1.0, 0.4)
		disabled = true
		mouse_default_cursor_shape = CURSOR_ARROW
		return

	var type: int = data.get("type", ClientModels.ChannelType.TEXT)
	match type:
		ClientModels.ChannelType.TEXT:
			type_icon.texture = IconEmoji.get_texture("text_channel")
		ClientModels.ChannelType.VOICE:
			type_icon.texture = IconEmoji.get_texture("voice_channel")
		ClientModels.ChannelType.ANNOUNCEMENT:
			type_icon.texture = IconEmoji.get_texture("announcement_channel")
		ClientModels.ChannelType.FORUM:
			type_icon.texture = IconEmoji.get_texture("forum_channel")
		_:
			type_icon.texture = IconEmoji.get_texture("text_channel")
	# NSFW indicator - dim the icon
	_is_nsfw = data.get("nsfw", false)

	# Voice channel participant count
	var voice_users: int = data.get("voice_users", 0)
	if type == ClientModels.ChannelType.VOICE and voice_users > 0:
		var count_label := Label.new()
		count_label.text = str(voice_users)
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
		count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		$HBox.add_child(count_label)
		$HBox.move_child(count_label, $HBox.get_child_count() - 1)

	_has_unread = data.get("unread", false)
	unread_dot.visible = _has_unread
	_apply_text_color()

	# Gear button (only if user has permission)
	if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		_gear_btn = Button.new()
		_gear_btn.text = "\u2699"
		_gear_btn.flat = true
		_gear_btn.visible = false
		_gear_btn.custom_minimum_size = Vector2(20, 20)
		_gear_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_gear_btn.mouse_filter = Control.MOUSE_FILTER_PASS
		_gear_btn.add_theme_font_size_override("font_size", 14)
		_gear_btn.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
		_gear_btn.tooltip_text = "Edit Channel"
		_gear_btn.pressed.connect(_on_edit_channel)
		$HBox.add_child(_gear_btn)

func set_active(active: bool) -> void:
	_is_active = active
	active_bg.visible = active
	active_pill.visible = active
	_apply_text_color()

func _apply_text_color() -> void:
	if _has_unread or _is_active:
		channel_name.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
	else:
		channel_name.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	# Dim icon when server-muted or client notification level is "muted"
	var is_dimmed: bool = (not channel_id.is_empty()) and (
		Client.is_channel_muted(channel_id) or
		Config.get_channel_notification_level(channel_id) == "muted"
	)
	if is_dimmed:
		type_icon.modulate.a = 0.4
		channel_name.modulate.a = 0.4
	elif _is_nsfw:
		type_icon.modulate.a = 0.6
		channel_name.modulate.a = 1.0
	else:
		type_icon.modulate.a = 1.0
		channel_name.modulate.a = 1.0

func _on_mutes_updated() -> void:
	_apply_text_color()

func _on_mouse_entered() -> void:
	if _gear_btn:
		_gear_btn.visible = true

func _on_mouse_exited() -> void:
	if _gear_btn:
		_gear_btn.visible = false

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	if Client.is_channel_muted(channel_id):
		_context_menu.add_item("Unmute Channel", 10)
	else:
		_context_menu.add_item("Mute Channel", 10)
	# Notification settings submenu
	var level: String = Config.get_channel_notification_level(channel_id)
	_notification_submenu.set_item_checked(0, level == "all")
	_notification_submenu.set_item_checked(1, level == "mentions")
	_notification_submenu.set_item_checked(2, level == "muted")
	_context_menu.add_submenu_node_item("Notification Settings", _notification_submenu, 11)
	if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		_context_menu.add_separator()
		_context_menu.add_item("Edit Channel", 0)
		_context_menu.add_item("Delete Channel", 1)
	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_edit_channel()
		1: _on_delete_channel()
		10: _on_toggle_mute()

func _on_notification_submenu_id_pressed(id: int) -> void:
	match id:
		20: Config.set_channel_notification_level(channel_id, "all")
		21: Config.set_channel_notification_level(channel_id, "mentions")
		22: Config.set_channel_notification_level(channel_id, "muted")

func _on_notification_updated(updated_channel_id: String) -> void:
	if updated_channel_id == channel_id:
		_apply_text_color()

func _on_edit_channel() -> void:
	DialogHelper.open(ChannelEditScene, get_tree()).setup(_channel_data)

func _on_toggle_mute() -> void:
	if Client.is_channel_muted(channel_id):
		Client.unmute_channel(channel_id)
	else:
		Client.mute_channel(channel_id)

func _on_delete_channel() -> void:
	DialogHelper.confirm(ConfirmDialogScene, get_tree(),
		"Delete Channel",
		"Are you sure you want to delete #%s? This cannot be undone." % _channel_data.get("name", ""),
		"Delete", true, func():
			Client.admin.delete_channel(channel_id)
	)

# --- Drag-and-drop reordering ---

func _get_drag_data(_at_position: Vector2) -> Variant:
	if space_id == "" or not Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		return null
	var preview := Label.new()
	preview.text = "# " + _channel_data.get("name", "")
	preview.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
	set_drag_preview(preview)
	return {"type": "channel", "channel_data": _channel_data, "source_node": self}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "channel":
		_drop_hovered = DropIndicator.clear(self, _drop_hovered)
		return false
	var source: Control = data.get("source_node")
	if source == self or source == null:
		_drop_hovered = DropIndicator.clear(self, _drop_hovered)
		return false
	# Accept drops from any channel in the same space
	var source_data: Dictionary = data.get("channel_data", {})
	if source_data.get("space_id", "") != space_id:
		_drop_hovered = DropIndicator.clear(self, _drop_hovered)
		return false
	_drop_above = at_position.y < size.y / 2.0
	_drop_hovered = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_hovered = DropIndicator.clear(self, _drop_hovered)
	var source: Control = data.get("source_node")
	if source == null:
		return
	var source_data: Dictionary = data.get("channel_data", {})
	var same_parent: bool = source.get_parent() == get_parent()
	if not same_parent:
		# Cross-category move: update parent_id to match this channel's parent
		var target_parent_id: String = _channel_data.get("parent_id", "")
		var source_id: String = source_data.get("id", "")
		if source_id != "":
			if target_parent_id == "":
				Client.admin.update_channel(source_id, {"parent_id": null})
			else:
				Client.admin.update_channel(source_id, {"parent_id": target_parent_id})
		return
	# Same parent: reorder within the container
	var container := get_parent()
	var target_idx: int = get_index()
	if not _drop_above:
		target_idx += 1
	container.move_child(source, target_idx)
	var positions: Array = []
	var pos: int = 0
	for child in container.get_children():
		if child.has_method("setup") and "channel_id" in child:
			positions.append({"id": child.channel_id, "position": pos})
			pos += 1
	if positions.size() > 0:
		Client.admin.reorder_channels(space_id, positions)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drop_hovered = DropIndicator.clear(self, _drop_hovered)

func _draw() -> void:
	DropIndicator.draw_line_indicator(self, _drop_hovered, _drop_above)
