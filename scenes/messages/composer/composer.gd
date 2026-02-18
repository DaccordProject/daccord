extends PanelContainer

const EmojiPickerScene := preload("res://scenes/messages/composer/emoji_picker.tscn")

var _last_typing_time: int = 0
var _emoji_picker: PanelContainer = null

@onready var upload_button: Button = $VBox/HBox/UploadButton
@onready var text_input: TextEdit = $VBox/HBox/TextInput
@onready var emoji_button: Button = $VBox/HBox/EmojiButton
@onready var send_button: Button = $VBox/HBox/SendButton
@onready var reply_bar: HBoxContainer = $VBox/ReplyBar
@onready var reply_label: Label = $VBox/ReplyBar/ReplyLabel
@onready var cancel_reply_button: Button = $VBox/ReplyBar/CancelReplyButton

func _ready() -> void:
	send_button.pressed.connect(_on_send)
	emoji_button.pressed.connect(_on_emoji_button)
	text_input.gui_input.connect(_on_text_input)
	text_input.text_changed.connect(_on_text_changed)
	cancel_reply_button.pressed.connect(_on_cancel_reply)
	AppState.reply_initiated.connect(_on_reply_initiated)
	AppState.reply_cancelled.connect(_on_reply_cancelled)
	# Remove default bg from text input to blend with composer
	var empty_style := StyleBoxEmpty.new()
	text_input.add_theme_stylebox_override("normal", empty_style)
	text_input.add_theme_stylebox_override("focus", empty_style)
	# Style reply bar
	reply_label.add_theme_font_size_override("font_size", 12)
	reply_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func set_channel_name(channel_name: String) -> void:
	text_input.placeholder_text = "Message #" + channel_name

func _on_send() -> void:
	var text := text_input.text.strip_edges()
	if text.is_empty():
		return
	AppState.send_message(text)
	text_input.text = ""
	if AppState.replying_to_message_id != "":
		AppState.cancel_reply()

func _on_text_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			_on_send()
			get_viewport().set_input_as_handled()

func _on_reply_initiated(message_id: String) -> void:
	var msg := Client.get_message_by_id(message_id)
	if msg.is_empty():
		return
	var author: Dictionary = msg.get("author", {})
	reply_label.text = "Replying to " + author.get("display_name", "Unknown")
	reply_bar.visible = true
	text_input.grab_focus()

func _on_reply_cancelled() -> void:
	reply_bar.visible = false
	reply_label.text = ""

func _on_text_changed() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_typing_time > 8000:
		_last_typing_time = now
		Client.send_typing(AppState.current_channel_id)

func _on_cancel_reply() -> void:
	AppState.cancel_reply()

func _on_emoji_button() -> void:
	if _emoji_picker and _emoji_picker.visible:
		_emoji_picker.visible = false
		return
	if not _emoji_picker:
		_emoji_picker = EmojiPickerScene.instantiate()
		get_tree().root.add_child(_emoji_picker)
		_emoji_picker.emoji_picked.connect(_on_emoji_picked)
	_position_picker()
	_emoji_picker.visible = true

func _position_picker() -> void:
	if not _emoji_picker:
		return
	var btn_rect := emoji_button.get_global_rect()
	var picker_size := _emoji_picker.custom_minimum_size
	var vp_size := get_viewport().get_visible_rect().size
	# Position above the emoji button, right-aligned
	var x := btn_rect.position.x + btn_rect.size.x - picker_size.x
	var y := btn_rect.position.y - picker_size.y - 8
	# Clamp to viewport
	x = clampf(x, 4, vp_size.x - picker_size.x - 4)
	y = clampf(y, 4, vp_size.y - picker_size.y - 4)
	_emoji_picker.position = Vector2(x, y)

func _on_emoji_picked(emoji_name: String) -> void:
	var entry := EmojiData.get_by_name(emoji_name)
	if entry.is_empty():
		return
	var unicode_char := EmojiData.codepoint_to_char(entry["codepoint"])
	var col := text_input.get_caret_column()
	var line := text_input.get_caret_line()
	var line_text := text_input.get_line(line)
	var new_text := line_text.substr(0, col) + unicode_char + line_text.substr(col)
	text_input.set_line(line, new_text)
	text_input.set_caret_column(col + unicode_char.length())
	text_input.grab_focus()
	_emoji_picker.visible = false

func _exit_tree() -> void:
	if _emoji_picker and is_instance_valid(_emoji_picker):
		_emoji_picker.queue_free()
