extends HBoxContainer

signal context_menu_requested(pos: Vector2i, msg_data: Dictionary)

var is_collapsed: bool = false
var _message_data: Dictionary = {}
var _long_press: LongPressDetector
var _is_hovered: bool = false

@onready var avatar: ColorRect = $AvatarColumn/Avatar
@onready var author_label: Label = $ContentColumn/Header/Author
@onready var timestamp_label: Label = $ContentColumn/Header/Timestamp
@onready var reply_ref: HBoxContainer = $ContentColumn/ReplyRef
@onready var reply_author: Label = $ContentColumn/ReplyRef/ReplyAuthor
@onready var reply_preview: Label = $ContentColumn/ReplyRef/ReplyPreview
@onready var message_content = $ContentColumn/MessageContent

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
	gui_input.connect(_on_gui_input)
	# Long-press for touch
	_long_press = LongPressDetector.new(self, _emit_context_menu)

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
			_apply_reply_reference(original)
		else:
			reply_author.text = ""
			reply_preview.text = "Loading reply..."
			reply_preview.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
			var channel_id: String = data.get("channel_id", "")
			_fetch_reply_reference(reply_to, channel_id)
	else:
		reply_ref.visible = false

	message_content.setup(data)

	# Mention highlight
	var my_id: String = Client.current_user.get("id", "")
	var my_roles: Array = _get_current_user_roles()
	if ClientModels.is_user_mentioned(data, my_id, my_roles):
		modulate = Color(1.0, 0.95, 0.85)

func _apply_reply_reference(original: Dictionary) -> void:
	var original_author: Dictionary = original.get("author", {})
	reply_author.text = original_author.get("display_name", "")
	reply_author.add_theme_color_override("font_color", original_author.get("color", Color.WHITE))
	var preview: String = original.get("content", "")
	if preview.length() > 50:
		preview = preview.substr(0, 50) + "..."
	reply_preview.text = preview

func _fetch_reply_reference(reply_to: String, channel_id: String) -> void:
	var client: AccordClient = Client._client_for_channel(channel_id)
	if client == null:
		reply_preview.text = "[original message unavailable]"
		return
	var cdn_url: String = Client._cdn_for_channel(channel_id)
	var result: RestResult = await client.messages.fetch(channel_id, reply_to)
	if not is_instance_valid(self):
		return
	if result.ok:
		var accord_msg: AccordMessage = result.data
		# Cache the author if needed
		if not Client._user_cache.has(accord_msg.author_id):
			var user_result: RestResult = await client.users.fetch(accord_msg.author_id)
			if not is_instance_valid(self):
				return
			if user_result.ok:
				Client._user_cache[accord_msg.author_id] = ClientModels.user_to_dict(
					user_result.data, ClientModels.UserStatus.OFFLINE, cdn_url
				)
		var msg_dict := ClientModels.message_to_dict(accord_msg, Client._user_cache, cdn_url)
		_apply_reply_reference(msg_dict)
	else:
		reply_preview.text = "[original message unavailable]"

func update_data(data: Dictionary) -> void:
	_message_data = data
	message_content.update_content(data)

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
			_emit_context_menu(Vector2i(int(pos.x), int(pos.y)))
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# Check if click is on avatar or author label
			var avatar_rect := avatar.get_global_rect()
			var author_rect := author_label.get_global_rect()
			var global_click := get_global_mouse_position()
			if avatar_rect.has_point(global_click) or author_rect.has_point(global_click):
				var user: Dictionary = _message_data.get("author", {})
				var uid: String = user.get("id", "")
				if not uid.is_empty():
					AppState.profile_card_requested.emit(uid, global_click)

func _emit_context_menu(pos: Vector2i) -> void:
	context_menu_requested.emit(pos, _message_data)

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

func _draw() -> void:
	if _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.25, 0.27, 0.3))
