extends VBoxContainer

const ForumPostRowScene := preload("res://scenes/messages/forum_post_row.tscn")

var _channel_id: String = ""
var _channel_name: String = ""
var _current_sort: int = 0 # 0=Latest Activity, 1=Newest, 2=Oldest

var _forum_title: Label
var _sort_dropdown: OptionButton
var _new_post_button: Button
var _scroll_container: ScrollContainer
var _post_list: VBoxContainer
var _empty_state: VBoxContainer
var _new_post_form: PanelContainer
var _title_input: LineEdit
var _body_input: TextEdit
var _cancel_button: Button
var _post_button: Button
var _context_menu: PopupMenu
var _context_post_data: Dictionary

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)

	_build_ui()

	AppState.forum_posts_updated.connect(_on_forum_posts_updated)
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	_apply_layout(AppState.current_layout_mode)

func _build_ui() -> void:
	# Header
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 40
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	_forum_title = Label.new()
	_forum_title.add_theme_font_size_override("font_size", 16)
	_forum_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	header.add_child(_forum_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_sort_dropdown = OptionButton.new()
	_sort_dropdown.add_item("Latest Activity", 0)
	_sort_dropdown.add_item("Newest", 1)
	_sort_dropdown.add_item("Oldest", 2)
	_sort_dropdown.selected = 0
	_sort_dropdown.item_selected.connect(_on_sort_changed)
	header.add_child(_sort_dropdown)

	_new_post_button = Button.new()
	_new_post_button.text = "New Post"
	_new_post_button.pressed.connect(_show_new_post_form)
	header.add_child(_new_post_button)

	# Separator
	var sep := HSeparator.new()
	add_child(sep)

	# Scroll container with post list
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll_container)

	_post_list = VBoxContainer.new()
	_post_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_post_list.add_theme_constant_override("separation", 2)
	_scroll_container.add_child(_post_list)

	# Empty state (inside post list)
	_empty_state = VBoxContainer.new()
	_empty_state.visible = false
	_empty_state.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_state.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_state.add_theme_constant_override("separation", 12)
	_post_list.add_child(_empty_state)

	var empty_title := Label.new()
	empty_title.text = "No posts yet"
	empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_title.add_theme_font_size_override("font_size", 20)
	empty_title.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_empty_state.add_child(empty_title)

	var empty_desc := Label.new()
	empty_desc.text = "Start the conversation by creating a new post!"
	empty_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_desc.add_theme_font_size_override("font_size", 14)
	empty_desc.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	_empty_state.add_child(empty_desc)

	var empty_btn := Button.new()
	empty_btn.text = "New Post"
	empty_btn.pressed.connect(_show_new_post_form)
	empty_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_state.add_child(empty_btn)

	# New post form (hidden by default)
	_new_post_form = PanelContainer.new()
	_new_post_form.visible = false
	var form_style := StyleBoxFlat.new()
	form_style.bg_color = Color(0.18, 0.19, 0.21, 1)
	form_style.content_margin_left = 12.0
	form_style.content_margin_right = 12.0
	form_style.content_margin_top = 12.0
	form_style.content_margin_bottom = 12.0
	form_style.corner_radius_top_left = 6
	form_style.corner_radius_top_right = 6
	form_style.corner_radius_bottom_left = 6
	form_style.corner_radius_bottom_right = 6
	_new_post_form.add_theme_stylebox_override("panel", form_style)
	add_child(_new_post_form)
	# Move form before scroll container
	move_child(_new_post_form, get_child_count() - 2)

	var form_vbox := VBoxContainer.new()
	form_vbox.add_theme_constant_override("separation", 8)
	_new_post_form.add_child(form_vbox)

	_title_input = LineEdit.new()
	_title_input.placeholder_text = "Post title"
	_title_input.add_theme_font_size_override("font_size", 14)
	form_vbox.add_child(_title_input)

	_body_input = TextEdit.new()
	_body_input.placeholder_text = "Write your post..."
	_body_input.custom_minimum_size.y = 120
	_body_input.add_theme_font_size_override("font_size", 14)
	form_vbox.add_child(_body_input)

	var form_buttons := HBoxContainer.new()
	form_buttons.alignment = BoxContainer.ALIGNMENT_END
	form_buttons.add_theme_constant_override("separation", 8)
	form_vbox.add_child(form_buttons)

	_cancel_button = Button.new()
	_cancel_button.text = "Cancel"
	_cancel_button.pressed.connect(_hide_new_post_form)
	form_buttons.add_child(_cancel_button)

	_post_button = Button.new()
	_post_button.text = "Post"
	_post_button.pressed.connect(_on_create_post)
	form_buttons.add_child(_post_button)

	# Context menu
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Open Thread", 0)
	_context_menu.add_separator()
	_context_menu.add_item("Delete Post", 1)
	_context_menu.id_pressed.connect(_on_context_menu_pressed)
	add_child(_context_menu)

func load_forum(channel_id: String, channel_name: String) -> void:
	_channel_id = channel_id
	_channel_name = channel_name
	_forum_title.text = "# %s" % channel_name

	# Clear existing post rows
	_clear_posts()
	_empty_state.visible = false

	var sort_str: String = _sort_string()
	Client.fetch.fetch_forum_posts(channel_id, sort_str)

func _on_forum_posts_updated(channel_id: String) -> void:
	if channel_id != _channel_id:
		return
	_render_posts()

func _render_posts() -> void:
	_clear_posts()
	var posts: Array = Client.get_forum_posts(_channel_id)

	if posts.is_empty():
		_empty_state.visible = true
		return
	_empty_state.visible = false

	# Client-side sort
	var sorted_posts: Array = posts.duplicate()
	_sort_posts(sorted_posts)

	for post in sorted_posts:
		var row: PanelContainer = ForumPostRowScene.instantiate()
		_post_list.add_child(row)
		row.setup(post)
		row.post_pressed.connect(_on_post_pressed)
		row.context_menu_requested.connect(_on_post_context_menu)

func _clear_posts() -> void:
	for child in _post_list.get_children():
		if child == _empty_state:
			continue
		child.queue_free()

func _sort_posts(posts: Array) -> void:
	match _current_sort:
		0: # Latest Activity
			posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var a_time: String = a.get("last_reply_at", "")
				var b_time: String = b.get("last_reply_at", "")
				if a_time.is_empty():
					a_time = a.get("timestamp", "")
				if b_time.is_empty():
					b_time = b.get("timestamp", "")
				return a_time > b_time
			)
		1: # Newest
			posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.get("id", "") > b.get("id", "")
			)
		2: # Oldest
			posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return a.get("id", "") < b.get("id", "")
			)

func _sort_string() -> String:
	match _current_sort:
		0: return "latest_activity"
		1: return "newest"
		2: return "oldest"
		_: return "latest_activity"

func _on_post_pressed(message_id: String) -> void:
	AppState.open_thread(message_id)

func _on_sort_changed(index: int) -> void:
	_current_sort = index
	# Re-fetch with new sort
	var sort_str: String = _sort_string()
	Client.fetch.fetch_forum_posts(_channel_id, sort_str)

func _show_new_post_form() -> void:
	_new_post_form.visible = true
	_title_input.text = ""
	_body_input.text = ""
	_title_input.grab_focus()

func _hide_new_post_form() -> void:
	_new_post_form.visible = false

func _on_create_post() -> void:
	var post_title: String = _title_input.text.strip_edges()
	var body: String = _body_input.text.strip_edges()
	if post_title.is_empty() and body.is_empty():
		return
	_hide_new_post_form()
	Client.send_message_to_channel(
		_channel_id, body, "", [], "", post_title
	)

func _on_post_context_menu(pos: Vector2i, post_data: Dictionary) -> void:
	_context_post_data = post_data
	# Show/hide delete based on ownership
	var author: Dictionary = post_data.get("author", {})
	var my_id: String = Client.current_user.get("id", "")
	var is_own: bool = author.get("id", "") == my_id
	var guild_id: String = Client._channel_to_guild.get(_channel_id, "")
	var can_manage: bool = Client.has_permission(guild_id, "MANAGE_THREADS")
	_context_menu.set_item_disabled(
		_context_menu.get_item_index(1),
		not is_own and not can_manage
	)
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_pressed(id: int) -> void:
	var msg_id: String = _context_post_data.get("id", "")
	match id:
		0: # Open Thread
			AppState.open_thread(msg_id)
		1: # Delete Post
			Client.remove_message(msg_id)

func _on_channels_updated(guild_id: String) -> void:
	if _channel_id.is_empty():
		return
	# Check if this forum channel's guild matches
	var ch_guild: String = Client._channel_to_guild.get(_channel_id, "")
	if ch_guild != guild_id:
		return
	# Update channel name if it changed
	var ch: Dictionary = Client._channel_cache.get(_channel_id, {})
	if not ch.is_empty():
		var new_name: String = ch.get("name", _channel_name)
		if new_name != _channel_name:
			_channel_name = new_name
			_forum_title.text = "# %s" % new_name

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_layout(mode)

func _apply_layout(mode: AppState.LayoutMode) -> void:
	match mode:
		AppState.LayoutMode.COMPACT:
			_forum_title.add_theme_font_size_override("font_size", 14)
			_new_post_button.text = "+"
			_new_post_button.tooltip_text = "New Post"
		_:
			_forum_title.add_theme_font_size_override("font_size", 16)
			_new_post_button.text = "New Post"
			_new_post_button.tooltip_text = ""
