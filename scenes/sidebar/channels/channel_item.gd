extends Button

signal channel_pressed(channel_id: String)

const TEXT_ICON := preload("res://assets/theme/icons/text_channel.svg")
const VOICE_ICON := preload("res://assets/theme/icons/voice_channel.svg")
const ANNOUNCEMENT_ICON := preload("res://assets/theme/icons/announcement_channel.svg")
const FORUM_ICON := preload("res://assets/theme/icons/forum_channel.svg")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ChannelEditScene := preload("res://scenes/admin/channel_edit_dialog.tscn")
const ICON_COLOR_DEFAULT := Color(0.44, 0.47, 0.51)
const ICON_COLOR_HOVER := Color(0.72, 0.75, 0.78)
const ICON_COLOR_ACTIVE := Color(0.88, 0.9, 0.92)

var channel_id: String = ""
var space_id: String = ""
var _channel_data: Dictionary = {}
var _context_menu: PopupMenu
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
	pressed.connect(func(): channel_pressed.emit(channel_id))

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	gui_input.connect(_on_gui_input)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	active_bg.visible = false
	active_pill.visible = false

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	space_id = data.get("space_id", "")
	_channel_data = data
	channel_name.text = data.get("name", "")
	tooltip_text = data.get("name", "")

	var type: int = data.get("type", ClientModels.ChannelType.TEXT)
	match type:
		ClientModels.ChannelType.TEXT:
			type_icon.texture = TEXT_ICON
		ClientModels.ChannelType.VOICE:
			type_icon.texture = VOICE_ICON
		ClientModels.ChannelType.ANNOUNCEMENT:
			type_icon.texture = ANNOUNCEMENT_ICON
		ClientModels.ChannelType.FORUM:
			type_icon.texture = FORUM_ICON
		_:
			type_icon.texture = TEXT_ICON
	# NSFW indicator - tint icon red
	if data.get("nsfw", false):
		type_icon.modulate = Color(0.9, 0.2, 0.2)
	else:
		_apply_icon_color()

	# Voice channel participant count
	var voice_users: int = data.get("voice_users", 0)
	if type == ClientModels.ChannelType.VOICE and voice_users > 0:
		var count_label := Label.new()
		count_label.text = str(voice_users)
		count_label.add_theme_font_size_override("font_size", 11)
		count_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
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
		_gear_btn.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		_gear_btn.tooltip_text = "Edit Channel"
		_gear_btn.pressed.connect(_on_edit_channel)
		$HBox.add_child(_gear_btn)

func set_active(active: bool) -> void:
	_is_active = active
	active_bg.visible = active
	active_pill.visible = active
	_apply_text_color()
	_apply_icon_color()

func _apply_text_color() -> void:
	if _has_unread or _is_active:
		channel_name.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		channel_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func _apply_icon_color() -> void:
	if _channel_data.get("nsfw", false):
		return
	if _is_active:
		type_icon.modulate = ICON_COLOR_ACTIVE
	else:
		type_icon.modulate = ICON_COLOR_DEFAULT

func _on_mouse_entered() -> void:
	if _gear_btn:
		_gear_btn.visible = true
	if not _is_active and not _channel_data.get("nsfw", false):
		type_icon.modulate = ICON_COLOR_HOVER

func _on_mouse_exited() -> void:
	if _gear_btn:
		_gear_btn.visible = false
	_apply_icon_color()

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	_context_menu.add_item("Edit Channel", 0)
	_context_menu.add_item("Delete Channel", 1)
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_edit_channel()
		1: _on_delete_channel()

func _on_edit_channel() -> void:
	var dialog := ChannelEditScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(_channel_data)

func _on_delete_channel() -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Channel",
		"Are you sure you want to delete #%s? This cannot be undone." % _channel_data.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.admin.delete_channel(channel_id)
	)

# --- Drag-and-drop reordering ---

func _get_drag_data(_at_position: Vector2) -> Variant:
	if space_id == "" or not Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
		return null
	var preview := Label.new()
	preview.text = "# " + _channel_data.get("name", "")
	preview.add_theme_color_override("font_color", Color(1, 1, 1))
	set_drag_preview(preview)
	return {"type": "channel", "channel_data": _channel_data, "source_node": self}

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary or data.get("type", "") != "channel":
		_clear_drop_indicator()
		return false
	var source: Control = data.get("source_node")
	if source == self or source == null:
		_clear_drop_indicator()
		return false
	# Accept drops from any channel in the same space
	var source_data: Dictionary = data.get("channel_data", {})
	if source_data.get("space_id", "") != space_id:
		_clear_drop_indicator()
		return false
	_drop_above = at_position.y < size.y / 2.0
	_drop_hovered = true
	queue_redraw()
	return true

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_clear_drop_indicator()
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
