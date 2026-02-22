extends PanelContainer

signal post_pressed(message_id: String)
signal context_menu_requested(pos: Vector2i, post_data: Dictionary)

const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _post_data: Dictionary

var _avatar: ColorRect
var _title_label: Label
var _author_label: Label
var _reply_count_label: Label
var _last_activity_label: Label
var _preview_label: Label

var _dot2: Label
var _hover_style: StyleBoxFlat
var _normal_style: StyleBoxFlat

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	# Normal style (transparent)
	_normal_style = StyleBoxFlat.new()
	_normal_style.bg_color = Color(0, 0, 0, 0)
	_normal_style.content_margin_left = 12.0
	_normal_style.content_margin_right = 12.0
	_normal_style.content_margin_top = 10.0
	_normal_style.content_margin_bottom = 10.0
	_normal_style.corner_radius_top_left = 6
	_normal_style.corner_radius_top_right = 6
	_normal_style.corner_radius_bottom_left = 6
	_normal_style.corner_radius_bottom_right = 6

	# Hover style
	_hover_style = _normal_style.duplicate()
	_hover_style.bg_color = Color(0.24, 0.25, 0.27, 1)

	add_theme_stylebox_override("panel", _normal_style)

	# Build scene tree
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	_avatar = AvatarScene.instantiate()
	_avatar.avatar_size = 32
	_avatar.show_letter = true
	_avatar.letter_font_size = 12
	hbox.add_child(_avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hbox.add_child(info)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 15)
	_title_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	info.add_child(_title_label)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 4)
	info.add_child(meta)

	_author_label = Label.new()
	_author_label.add_theme_font_size_override("font_size", 12)
	_author_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	meta.add_child(_author_label)

	var dot1 := Label.new()
	dot1.text = " \u00b7 "
	dot1.add_theme_font_size_override("font_size", 12)
	dot1.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	meta.add_child(dot1)

	_reply_count_label = Label.new()
	_reply_count_label.add_theme_font_size_override("font_size", 12)
	_reply_count_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	meta.add_child(_reply_count_label)

	_dot2 = Label.new()
	_dot2.text = " \u00b7 "
	_dot2.add_theme_font_size_override("font_size", 12)
	_dot2.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	meta.add_child(_dot2)

	_last_activity_label = Label.new()
	_last_activity_label.add_theme_font_size_override("font_size", 12)
	_last_activity_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	meta.add_child(_last_activity_label)

	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 13)
	_preview_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	_preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_label.max_lines_visible = 2
	info.add_child(_preview_label)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	_apply_layout(AppState.current_layout_mode)

func setup(data: Dictionary) -> void:
	_post_data = data

	# Title: use title field, fallback to first line of content
	var title: String = data.get("title", "")
	if title.is_empty():
		var content: String = data.get("content", "")
		var newline_idx: int = content.find("\n")
		if newline_idx != -1:
			title = content.substr(0, newline_idx)
		elif not content.is_empty():
			title = content.substr(0, mini(80, content.length()))
		else:
			title = "Untitled Post"
	_title_label.text = title

	# Author
	var author: Dictionary = data.get("author", {})
	var display_name: String = author.get("display_name", "Unknown")
	_author_label.text = display_name

	# Avatar
	var author_color: Color = author.get("color", Color.WHITE)
	_avatar.set_avatar_color(author_color)
	_avatar.set_letter(display_name.substr(0, 1).to_upper())
	var avatar_url = author.get("avatar", null)
	if avatar_url != null and avatar_url is String and not avatar_url.is_empty():
		_avatar.set_avatar_url(avatar_url)

	# Reply count
	var reply_count: int = data.get("reply_count", 0)
	if reply_count == 1:
		_reply_count_label.text = "1 reply"
	else:
		_reply_count_label.text = "%d replies" % reply_count

	# Last activity
	var last_reply: String = data.get("last_reply_at", "")
	if not last_reply.is_empty():
		_last_activity_label.text = last_reply
	else:
		_last_activity_label.text = data.get("timestamp", "")

	# Content preview
	var content: String = data.get("content", "")
	var title_text: String = data.get("title", "")
	# If content starts with the title, skip it for the preview
	if not title_text.is_empty() and content.begins_with(title_text):
		content = content.substr(title_text.length()).strip_edges()
	if content.length() > 120:
		content = content.substr(0, 120) + "..."
	_preview_label.text = content
	_preview_label.visible = not content.is_empty()

func update_data(data: Dictionary) -> void:
	setup(data)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			post_pressed.emit(_post_data.get("id", ""))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			context_menu_requested.emit(
				Vector2i(int(event.global_position.x), int(event.global_position.y)),
				_post_data
			)

func _on_mouse_entered() -> void:
	add_theme_stylebox_override("panel", _hover_style)

func _on_mouse_exited() -> void:
	add_theme_stylebox_override("panel", _normal_style)

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_layout(mode)

func _apply_layout(mode: AppState.LayoutMode) -> void:
	match mode:
		AppState.LayoutMode.COMPACT:
			_avatar.visible = false
			_title_label.add_theme_font_size_override("font_size", 13)
			_preview_label.max_lines_visible = 1
			_dot2.visible = false
			_last_activity_label.visible = false
		_:
			_avatar.visible = true
			_title_label.add_theme_font_size_override("font_size", 15)
			_preview_label.max_lines_visible = 2
			_dot2.visible = true
			_last_activity_label.visible = true
