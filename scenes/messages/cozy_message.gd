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
@onready var thread_indicator: HBoxContainer = $ContentColumn/ThreadIndicator
@onready var thread_count_label: Label = $ContentColumn/ThreadIndicator/ThreadCountLabel

func _ready() -> void:
	add_to_group("themed")
	# Allow mouse events to pass through child controls so hover
	# detection covers the entire message area, not just gaps.
	content_column.mouse_filter = Control.MOUSE_FILTER_PASS
	header.mouse_filter = Control.MOUSE_FILTER_PASS
	timestamp_label.add_theme_font_size_override("font_size", 11)
	reply_author.add_theme_font_size_override("font_size", 12)
	reply_preview.add_theme_font_size_override("font_size", 12)
	_apply_theme()
	gui_input.connect(_on_gui_input)
	# Long-press for touch
	_long_press = LongPressDetector.new(self, _emit_context_menu)

func _apply_theme() -> void:
	timestamp_label.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	reply_preview.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
	queue_redraw()

func setup(data: Dictionary) -> void:
	_message_data = data
	var user: Dictionary = data.get("author", {})
	author_label.text = user.get("display_name", "Unknown")
	var name_color: Color = user.get("color", Color.WHITE)
	var role_color = _resolve_role_color(user)
	if role_color != null:
		name_color = role_color
	author_label.add_theme_color_override("font_color", name_color)
	avatar.set_avatar_color(user.get("color", ThemeManager.get_color("accent")))
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
			reply_preview.add_theme_color_override("font_color", ThemeManager.get_color("text_muted"))
			var channel_id: String = data.get("channel_id", "")
			_fetch_reply_reference(reply_to, channel_id)
	else:
		reply_ref.visible = false

	message_content.setup(data)

	# Thread indicator
	var thread_reply_count: int = data.get("reply_count", 0)
	if thread_reply_count > 0:
		thread_indicator.visible = true
		var suffix: String = "reply" if thread_reply_count == 1 else "replies"
		thread_count_label.text = "%d %s" % [thread_reply_count, suffix]
		thread_count_label.add_theme_font_size_override("font_size", 12)
		thread_count_label.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
		# Detect unread thread
		if Client._thread_unread.has(data.get("id", "")):
			thread_count_label.add_theme_color_override("font_color", ThemeManager.get_color("accent_hover"))
		# Show mention badge
		var mention_count: int = Client._thread_mention_count.get(data.get("id", ""), 0)
		if mention_count > 0:
			thread_count_label.text += " \u00b7 @%d" % mention_count
			thread_count_label.add_theme_color_override("font_color", ThemeManager.get_color("accent_hover"))
		thread_indicator.gui_input.connect(_on_thread_indicator_input)
		thread_indicator.mouse_filter = Control.MOUSE_FILTER_STOP
		thread_indicator.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		thread_indicator.visible = false

	# Mention highlight
	var my_id: String = Client.current_user.get("id", "")
	var my_roles: Array = _get_current_user_roles()
	if ClientModels.is_user_mentioned(data, my_id, my_roles):
		modulate = Color(1.0, 0.95, 0.85)

func _apply_reply_reference(original: Dictionary) -> void:
	var original_author: Dictionary = original.get("author", {})
	reply_author.text = original_author.get("display_name", "")
	var reply_name_color: Color = original_author.get("color", Color.WHITE)
	var reply_role_color = _resolve_role_color(original_author)
	if reply_role_color != null:
		reply_name_color = reply_role_color
	reply_author.add_theme_color_override("font_color", reply_name_color)
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

func update_author(user: Dictionary) -> void:
	_message_data["author"] = user
	author_label.text = user.get("display_name", "Unknown")
	var name_color: Color = user.get("color", Color.WHITE)
	var role_color = _resolve_role_color(user)
	if role_color != null:
		name_color = role_color
	author_label.add_theme_color_override("font_color", name_color)
	avatar.set_avatar_color(user.get("color", ThemeManager.get_color("accent")))
	var display_name: String = user.get("display_name", "")
	if display_name.length() > 0:
		avatar.set_letter(display_name[0].to_upper())
	else:
		avatar.set_letter("")
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		avatar.set_avatar_url(avatar_url)

func update_data(data: Dictionary) -> void:
	_message_data = data
	message_content.update_content(data)

func _get_current_user_roles() -> Array:
	var space_id: String = Client._channel_to_space.get(
		AppState.current_channel_id, ""
	)
	if space_id.is_empty():
		return []
	var my_id: String = Client.current_user.get("id", "")
	for member in Client.get_members_for_space(space_id):
		if member.get("id", "") == my_id:
			return member.get("roles", [])
	return []

func _resolve_role_color(user: Dictionary) -> Variant:
	var space_id: String = Client._channel_to_space.get(
		AppState.current_channel_id, ""
	)
	if space_id.is_empty():
		return null
	var uid: String = user.get("id", "")
	if uid.is_empty():
		return null
	return Client.get_role_color_for_user(space_id, uid)

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

func _on_thread_indicator_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AppState.open_thread(_message_data.get("id", ""))

func _emit_context_menu(pos: Vector2i) -> void:
	context_menu_requested.emit(pos, _message_data)

func set_hovered(hovered: bool) -> void:
	_is_hovered = hovered
	queue_redraw()

func _draw() -> void:
	if _is_hovered:
		draw_rect(Rect2(Vector2.ZERO, size), Color(ThemeManager.get_color("button_hover"), 0.3))
