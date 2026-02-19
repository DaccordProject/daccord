extends HBoxContainer

const ReactionPickerScene := preload("res://scenes/messages/reaction_picker.tscn")

var _message_data: Dictionary = {}
var _context_menu: PopupMenu
var _long_press: LongPressDetector
var _reaction_picker: Control = null
var _is_hovered: bool = false
var _delete_dialog: ConfirmationDialog

@onready var avatar: ColorRect = $AvatarColumn/Avatar
@onready var author_label: Label = $ContentColumn/Header/Author
@onready var timestamp_label: Label = $ContentColumn/Header/Timestamp
@onready var reply_ref: HBoxContainer = $ContentColumn/ReplyRef
@onready var reply_author: Label = $ContentColumn/ReplyRef/ReplyAuthor
@onready var reply_preview: Label = $ContentColumn/ReplyRef/ReplyPreview
@onready var message_content: VBoxContainer = $ContentColumn/MessageContent

@onready var content_column: VBoxContainer = $ContentColumn
@onready var header: HBoxContainer = $ContentColumn/Header

func _ready() -> void:
	# Allow mouse events to pass through child controls so hover
	# detection covers the entire message area, not just gaps.
	content_column.mouse_filter = Control.MOUSE_FILTER_PASS
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	timestamp_label.add_theme_font_size_override("font_size", 11)
	timestamp_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	reply_author.add_theme_font_size_override("font_size", 12)
	reply_preview.add_theme_font_size_override("font_size", 12)
	reply_preview.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	# Context menu
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Reply", 0)
	_context_menu.add_item("Edit", 1)
	_context_menu.add_item("Delete", 2)
	_context_menu.add_item("Add Reaction", 3)
	_context_menu.add_item("Remove All Reactions", 4)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	gui_input.connect(_on_gui_input)
	# Long-press for touch
	_long_press = LongPressDetector.new(self, _show_context_menu)

func setup(data: Dictionary) -> void:
	_message_data = data
	var user: Dictionary = data.get("author", {})
	author_label.text = user.get("display_name", "Unknown")
	author_label.add_theme_color_override("font_color", user.get("color", Color.WHITE))
	avatar.set_avatar_color(user.get("color", Color(0.345, 0.396, 0.949)))
	var display_name: String = user.get("display_name", "")
	if display_name.length() > 0:
		avatar.set_letter(display_name[0].to_upper())
	else:
		avatar.set_letter("")
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		avatar.set_avatar_url(avatar_url)
	timestamp_label.text = data.get("timestamp", "")

	# Reply reference
	var reply_to: String = data.get("reply_to", "")
	if reply_to != "":
		reply_ref.visible = true
		var original := Client.get_message_by_id(reply_to)
		if not original.is_empty():
			var original_author: Dictionary = original.get("author", {})
			reply_author.text = original_author.get("display_name", "")
			reply_author.add_theme_color_override("font_color", original_author.get("color", Color.WHITE))
			var preview: String = original.get("content", "")
			if preview.length() > 50:
				preview = preview.substr(0, 50) + "..."
			reply_preview.text = preview
	else:
		reply_ref.visible = false

	message_content.setup(data)

	# Mention highlight
	var my_id: String = Client.current_user.get("id", "")
	var my_roles: Array = _get_current_user_roles()
	if ClientModels.is_user_mentioned(data, my_id, my_roles):
		modulate = Color(1.0, 0.95, 0.85)

func _get_current_user_roles() -> Array:
	var guild_id: String = Client._channel_to_guild.get(
		AppState.current_channel_id, ""
	)
	if guild_id.is_empty():
		return []
	var my_id: String = Client.current_user.get("id", "")
	for member in Client.get_members_for_guild(guild_id):
		if member.get("id", "") == my_id:
			return member.get("roles", [])
	return []

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var pos := get_global_mouse_position()
			_show_context_menu(Vector2i(int(pos.x), int(pos.y)))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# Check if click is on avatar or author label
			var click_pos: Vector2 = event.position
			var avatar_rect := avatar.get_global_rect()
			var author_rect := author_label.get_global_rect()
			var global_click := get_global_mouse_position()
			if avatar_rect.has_point(global_click) or author_rect.has_point(global_click):
				var user: Dictionary = _message_data.get("author", {})
				var uid: String = user.get("id", "")
				if not uid.is_empty():
					AppState.profile_card_requested.emit(uid, global_click)

func _show_context_menu(pos: Vector2i) -> void:
	var author: Dictionary = _message_data.get("author", {})
	var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
	_context_menu.set_item_disabled(1, not is_own)
	_context_menu.set_item_disabled(2, not is_own)
	# "Remove All Reactions" requires MANAGE_MESSAGES permission
	var guild_id: String = Client._channel_to_guild.get(
		_message_data.get("channel_id", ""), ""
	)
	var has_reactions: bool = _message_data.get("reactions", []).size() > 0
	var can_manage: bool = Client.has_permission(guild_id, "MANAGE_MESSAGES")
	_context_menu.set_item_disabled(4, not (can_manage and has_reactions))
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Reply
			AppState.initiate_reply(_message_data.get("id", ""))
		1: # Edit
			AppState.start_editing(_message_data.get("id", ""))
			message_content.enter_edit_mode(_message_data.get("id", ""), _message_data.get("content", ""))
		2: # Delete
			_confirm_delete()
		3: # Add Reaction
			_open_reaction_picker()
		4: # Remove All Reactions
			var cid: String = _message_data.get("channel_id", "")
			var mid: String = _message_data.get("id", "")
			Client.remove_all_reactions(cid, mid)

func _confirm_delete() -> void:
	if not _delete_dialog:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.dialog_text = "Are you sure you want to delete this message?"
		_delete_dialog.confirmed.connect(func():
			AppState.delete_message(_message_data.get("id", ""))
		)
		add_child(_delete_dialog)
	_delete_dialog.popup_centered()

func _open_reaction_picker() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
	_reaction_picker = ReactionPickerScene.instantiate()
	get_tree().root.add_child(_reaction_picker)
	var channel_id: String = _message_data.get("channel_id", "")
	var msg_id: String = _message_data.get("id", "")
	var pos := get_global_mouse_position()
	_reaction_picker.open(channel_id, msg_id, pos)
	_reaction_picker.closed.connect(func():
		_reaction_picker = null
	)

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

func _draw() -> void:
	if _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.25, 0.27, 0.3))

func _exit_tree() -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
