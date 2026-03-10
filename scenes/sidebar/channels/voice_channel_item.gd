extends VBoxContainer

signal channel_pressed(channel_id: String)

const VOICE_ICON := preload("res://assets/theme/icons/voice_channel.svg")
const CHAT_ICON := preload("res://assets/theme/icons/chat.svg")
const LOCK_ICON := preload("res://assets/theme/icons/lock.svg")
const AvatarScene := preload("res://scenes/common/avatar.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ChannelEditScene := preload("res://scenes/admin/channel_edit_dialog.tscn")

var channel_id: String = ""
var space_id: String = ""
var _channel_data: Dictionary = {}
var _gear_btn: Button
var _chat_btn: Button
var _context_menu: PopupMenu
var _gear_just_pressed: bool = false
var _chat_just_pressed: bool = false
var _is_active: bool = false
var _has_unread: bool = false
var _drop_above: bool = false
var _drop_hovered: bool = false
var _participant_avatars: Dictionary = {} # user_id -> Avatar node ref

@onready var channel_button: Button = $ChannelButton
@onready var type_icon: TextureRect = $ChannelButton/HBox/TypeIcon
@onready var channel_name: Label = $ChannelButton/HBox/ChannelName
@onready var user_count: Label = $ChannelButton/HBox/UserCount
@onready var participant_container: VBoxContainer = $ParticipantContainer
@onready var unread_dot: ColorRect = $ChannelButton/HBox/UnreadDot
@onready var active_bg: ColorRect = $ChannelButton/ActiveBg
@onready var active_pill: ColorRect = $ChannelButton/ActivePill

func _ready() -> void:
	channel_button.pressed.connect(func():
		if _gear_just_pressed:
			_gear_just_pressed = false
			return
		if _chat_just_pressed:
			_chat_just_pressed = false
			return
		channel_pressed.emit(channel_id)
	)
	AppState.voice_state_updated.connect(_on_voice_state_updated)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.speaking_changed.connect(_on_speaking_changed)
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.voice_text_opened.connect(_on_voice_text_opened)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	# Display-only children should not intercept mouse events (especially drag)
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	channel_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	user_count.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Forward drag-and-drop from ChannelButton to this VBoxContainer
	channel_button.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)

	active_bg.visible = false
	active_pill.visible = false

	add_to_group("themed")
	channel_button.gui_input.connect(_on_gui_input)
	channel_button.mouse_entered.connect(_on_mouse_entered)
	channel_button.mouse_exited.connect(_on_mouse_exited)
	AppState.channel_mutes_updated.connect(_on_mutes_updated)

func _apply_theme() -> void:
	_refresh_participants()
	queue_redraw()
	ThemeManager.apply_font_colors(self)

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	space_id = data.get("space_id", "")
	_channel_data = data
	channel_name.text = data.get("name", "")
	channel_button.tooltip_text = data.get("name", "")

	# Locked channels are shown to admins in imposter mode but are not interactive.
	if data.get("locked", false):
		type_icon.texture = LOCK_ICON
		channel_button.modulate = Color(1.0, 1.0, 1.0, 0.4)
		channel_button.disabled = true
		channel_button.mouse_default_cursor_shape = CURSOR_ARROW
		return

	type_icon.texture = VOICE_ICON

	_has_unread = data.get("unread", false)
	unread_dot.visible = _has_unread

	# Chat button (voice text chat)
	_chat_btn = Button.new()
	_chat_btn.icon = CHAT_ICON
	_chat_btn.flat = true
	_chat_btn.visible = false
	_chat_btn.custom_minimum_size = Vector2(20, 20)
	_chat_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chat_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	_chat_btn.add_theme_color_override("icon_normal_color", ThemeManager.get_color("text_muted"))
	_chat_btn.add_theme_color_override("icon_hover_color", ThemeManager.get_color("text_white"))
	_chat_btn.tooltip_text = "Open Text Chat"
	_chat_btn.pressed.connect(_on_chat_pressed)
	$ChannelButton/HBox.add_child(_chat_btn)

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
		$ChannelButton/HBox.add_child(_gear_btn)

	_refresh_participants()

func set_active(active: bool) -> void:
	_is_active = active
	active_bg.visible = active
	active_pill.visible = active
	_apply_text_color()

func _on_voice_state_updated(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _on_voice_joined(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _on_voice_left(cid: String) -> void:
	if cid == channel_id:
		_refresh_participants()

func _refresh_participants() -> void:
	# Clear old participant items and avatar tracking
	for child in participant_container.get_children():
		child.queue_free()
	_participant_avatars.clear()

	var voice_users: Array = Client.get_voice_users(channel_id)
	var count: int = voice_users.size()

	# Update count label
	if count > 0:
		user_count.text = str(count)
		user_count.visible = true
	else:
		user_count.visible = false

	# Green tint when we are connected to this channel
	if AppState.voice_channel_id == channel_id:
		type_icon.modulate = ThemeManager.get_color("success")
	else:
		type_icon.modulate = ThemeManager.get_color("icon_default")
	_apply_text_color()

	# Build participant items
	for vs in voice_users:
		var user: Dictionary = vs.get("user", {})
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 24)

		# Indent spacer
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(28, 0)
		row.add_child(spacer)

		# Avatar
		var av := AvatarScene.instantiate()
		av.avatar_size = 18
		av.show_letter = true
		av.letter_font_size = 9
		av.custom_minimum_size = Vector2(18, 18)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(av)
		av.setup_from_dict(user)

		# Track avatar and apply current speaking state (no animation during rebuild)
		var user_id: String = user.get("id", vs.get("user_id", ""))
		if not user_id.is_empty():
			_participant_avatars[user_id] = av
			if Client.is_user_speaking(user_id):
				av.set_ring_opacity(1.0)

		# Spacer between avatar and name
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(6, 0)
		row.add_child(gap)

		# Username label
		var name_label := Label.new()
		name_label.text = user.get("display_name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 12)
		var uid: String = user.get("id", vs.get("user_id", ""))
		var role_color = null
		if not space_id.is_empty() and not uid.is_empty():
			role_color = Client.get_role_color_for_user(space_id, uid)
		if role_color != null:
			name_label.add_theme_color_override("font_color", role_color)
		else:
			name_label.add_theme_color_override("font_color", ThemeManager.get_color("text_body"))
		row.add_child(name_label)

		# Mute/deaf indicators
		var self_mute: bool = vs.get("self_mute", false)
		var self_deaf: bool = vs.get("self_deaf", false)
		if self_deaf:
			var deaf_label := Label.new()
			deaf_label.text = "D"
			deaf_label.add_theme_font_size_override("font_size", 10)
			deaf_label.add_theme_color_override("font_color", ThemeManager.get_color("error"))
			deaf_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(deaf_label)
		elif self_mute:
			var mute_label := Label.new()
			mute_label.text = "M"
			mute_label.add_theme_font_size_override("font_size", 10)
			mute_label.add_theme_color_override("font_color", ThemeManager.get_color("error"))
			mute_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(mute_label)

		# Video/screen share indicators
		var self_video: bool = vs.get("self_video", false)
		var self_stream: bool = vs.get("self_stream", false)
		if self_video:
			var video_label := Label.new()
			video_label.text = "V"
			video_label.add_theme_font_size_override("font_size", 10)
			video_label.add_theme_color_override("font_color", ThemeManager.get_color("success"))
			video_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(video_label)
		if self_stream:
			var stream_label := Label.new()
			stream_label.text = "S"
			stream_label.add_theme_font_size_override("font_size", 10)
			stream_label.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
			stream_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(stream_label)

		participant_container.add_child(row)

func _apply_text_color() -> void:
	if _has_unread or _is_active or AppState.voice_channel_id == channel_id:
		channel_name.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))
	else:
		channel_name.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	if not channel_id.is_empty() and Client.is_channel_muted(channel_id):
		channel_name.modulate.a = 0.4
	else:
		channel_name.modulate.a = 1.0

func _on_mutes_updated() -> void:
	_apply_text_color()

func _on_speaking_changed(user_id: String, is_speaking: bool) -> void:
	if _participant_avatars.has(user_id):
		var av = _participant_avatars[user_id]
		if is_instance_valid(av):
			av.set_speaking(is_speaking)

func _on_channels_updated(_space_id: String) -> void:
	if channel_id.is_empty():
		return
	for ch in Client.channels:
		if ch["id"] == channel_id:
			var was_unread := _has_unread
			_has_unread = ch.get("unread", false)
			if _has_unread != was_unread:
				unread_dot.visible = _has_unread
				_apply_text_color()
			break

func _on_voice_text_opened(cid: String) -> void:
	if cid == channel_id and _has_unread:
		Client.clear_channel_unread(channel_id)

func _on_chat_pressed() -> void:
	_chat_just_pressed = true
	AppState.toggle_voice_text(channel_id)

func _on_mouse_entered() -> void:
	if _chat_btn:
		_chat_btn.visible = true
	if _gear_btn:
		_gear_btn.visible = true
	if AppState.voice_channel_id != channel_id:
		type_icon.modulate = ThemeManager.get_color("icon_hover")
	channel_name.add_theme_color_override("font_color", ThemeManager.get_color("text_white"))

func _on_mouse_exited() -> void:
	if _chat_btn:
		_chat_btn.visible = false
	if _gear_btn:
		_gear_btn.visible = false
	if AppState.voice_channel_id != channel_id:
		type_icon.modulate = ThemeManager.get_color("icon_default")
	_apply_text_color()

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

func _on_toggle_mute() -> void:
	if Client.is_channel_muted(channel_id):
		Client.unmute_channel(channel_id)
	else:
		Client.mute_channel(channel_id)

func _on_edit_channel() -> void:
	_gear_just_pressed = true
	DialogHelper.open(ChannelEditScene, get_tree()).setup(_channel_data)

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
