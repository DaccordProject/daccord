extends HBoxContainer

var _message_data: Dictionary = {}
var _context_menu: PopupMenu
var _long_press: LongPressDetector

@onready var avatar: ColorRect = $AvatarColumn/Avatar
@onready var author_label: Label = $ContentColumn/Header/Author
@onready var timestamp_label: Label = $ContentColumn/Header/Timestamp
@onready var reply_ref: HBoxContainer = $ContentColumn/ReplyRef
@onready var reply_author: Label = $ContentColumn/ReplyRef/ReplyAuthor
@onready var reply_preview: Label = $ContentColumn/ReplyRef/ReplyPreview
@onready var message_content: VBoxContainer = $ContentColumn/MessageContent

func _ready() -> void:
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
	var content: String = data.get("content", "")
	var current_user_name: String = Client.current_user.get("display_name", "")
	if content.contains("@" + current_user_name):
		modulate = Color(1.0, 0.95, 0.85)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var pos := get_global_mouse_position()
		_show_context_menu(Vector2i(int(pos.x), int(pos.y)))

func _show_context_menu(pos: Vector2i) -> void:
	var author: Dictionary = _message_data.get("author", {})
	var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
	_context_menu.set_item_disabled(1, not is_own)
	_context_menu.set_item_disabled(2, not is_own)
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Reply
			AppState.initiate_reply(_message_data.get("id", ""))
		1: # Edit
			message_content.enter_edit_mode(_message_data.get("id", ""), _message_data.get("content", ""))
		2: # Delete
			AppState.delete_message(_message_data.get("id", ""))
