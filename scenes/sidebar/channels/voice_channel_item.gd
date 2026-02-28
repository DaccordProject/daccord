extends VBoxContainer

signal channel_pressed(channel_id: String)

const VOICE_ICON := preload("res://assets/theme/icons/voice_channel.svg")
const AvatarScene := preload("res://scenes/common/avatar.tscn")
const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const ChannelEditScene := preload("res://scenes/admin/channel_edit_dialog.tscn")

var channel_id: String = ""
var space_id: String = ""
var _channel_data: Dictionary = {}
var _gear_btn: Button
var _context_menu: PopupMenu
var _gear_just_pressed: bool = false
var _drop_above: bool = false
var _drop_hovered: bool = false
var _participant_avatars: Dictionary = {} # user_id -> Avatar node ref

@onready var channel_button: Button = $ChannelButton
@onready var type_icon: TextureRect = $ChannelButton/HBox/TypeIcon
@onready var channel_name: Label = $ChannelButton/HBox/ChannelName
@onready var user_count: Label = $ChannelButton/HBox/UserCount
@onready var participant_container: VBoxContainer = $ParticipantContainer

func _ready() -> void:
	channel_button.pressed.connect(func():
		if _gear_just_pressed:
			_gear_just_pressed = false
			return
		channel_pressed.emit(channel_id)
	)
	AppState.voice_state_updated.connect(_on_voice_state_updated)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.speaking_changed.connect(_on_speaking_changed)

	_context_menu = PopupMenu.new()
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	# Display-only children should not intercept mouse events (especially drag)
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	channel_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	user_count.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Forward drag-and-drop from ChannelButton to this VBoxContainer
	channel_button.set_drag_forwarding(_get_drag_data, _can_drop_data, _drop_data)

	channel_button.gui_input.connect(_on_gui_input)
	channel_button.mouse_entered.connect(_on_mouse_entered)
	channel_button.mouse_exited.connect(_on_mouse_exited)

func setup(data: Dictionary) -> void:
	channel_id = data.get("id", "")
	space_id = data.get("space_id", "")
	_channel_data = data
	channel_name.text = data.get("name", "")
	channel_button.tooltip_text = data.get("name", "")
	type_icon.texture = VOICE_ICON

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
		$ChannelButton/HBox.add_child(_gear_btn)

	_refresh_participants()

func set_active(_active: bool) -> void:
	# Voice channels don't have a persistent active state like text channels,
	# but we support the interface for polymorphism with channel_item.
	pass

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
		type_icon.modulate = Color(0.231, 0.647, 0.365)
		channel_name.add_theme_color_override("font_color", Color(1, 1, 1))
	else:
		type_icon.modulate = Color(0.44, 0.47, 0.51)
		channel_name.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

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
		av.set_avatar_color(user.get("color", Color(0.345, 0.396, 0.949)))
		var dn: String = user.get("display_name", "?")
		av.set_letter(dn.left(1).to_upper() if not dn.is_empty() else "?")
		var avatar_url = user.get("avatar", null)
		if avatar_url is String and not avatar_url.is_empty():
			av.set_avatar_url(avatar_url)

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
		name_label.add_theme_color_override("font_color", Color(0.72, 0.73, 0.76))
		row.add_child(name_label)

		# Mute/deaf indicators
		var self_mute: bool = vs.get("self_mute", false)
		var self_deaf: bool = vs.get("self_deaf", false)
		if self_deaf:
			var deaf_label := Label.new()
			deaf_label.text = "D"
			deaf_label.add_theme_font_size_override("font_size", 10)
			deaf_label.add_theme_color_override("font_color", Color(0.929, 0.259, 0.271))
			deaf_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(deaf_label)
		elif self_mute:
			var mute_label := Label.new()
			mute_label.text = "M"
			mute_label.add_theme_font_size_override("font_size", 10)
			mute_label.add_theme_color_override("font_color", Color(0.929, 0.259, 0.271))
			mute_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(mute_label)

		# Video/screen share indicators
		var self_video: bool = vs.get("self_video", false)
		var self_stream: bool = vs.get("self_stream", false)
		if self_video:
			var video_label := Label.new()
			video_label.text = "V"
			video_label.add_theme_font_size_override("font_size", 10)
			video_label.add_theme_color_override("font_color", Color(0.231, 0.647, 0.365))
			video_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(video_label)
		if self_stream:
			var stream_label := Label.new()
			stream_label.text = "S"
			stream_label.add_theme_font_size_override("font_size", 10)
			stream_label.add_theme_color_override("font_color", Color(0.345, 0.396, 0.949))
			stream_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(stream_label)

		participant_container.add_child(row)

func _on_speaking_changed(user_id: String, is_speaking: bool) -> void:
	if _participant_avatars.has(user_id):
		var av = _participant_avatars[user_id]
		if is_instance_valid(av):
			av.set_speaking(is_speaking)

func _on_mouse_entered() -> void:
	if _gear_btn:
		_gear_btn.visible = true
	if AppState.voice_channel_id != channel_id:
		type_icon.modulate = Color(0.72, 0.75, 0.78)

func _on_mouse_exited() -> void:
	if _gear_btn:
		_gear_btn.visible = false
	if AppState.voice_channel_id != channel_id:
		type_icon.modulate = Color(0.44, 0.47, 0.51)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if space_id != "" and Client.has_permission(space_id, AccordPermission.MANAGE_CHANNELS):
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	_context_menu.clear()
	_context_menu.add_item("Edit Channel", 0)
	_context_menu.add_item("Delete Channel", 1)
	_context_menu.hide()
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: _on_edit_channel()
		1: _on_delete_channel()

func _on_edit_channel() -> void:
	_gear_just_pressed = true
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
