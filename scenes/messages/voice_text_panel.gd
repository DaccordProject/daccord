extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")

var _channel_id: String = ""
var _channel_name: String = ""
var _last_typing_time: int = 0
var _is_loading_older: bool = false
var _older_btn: Button

@onready var header_label: Label = $VBox/Header/HeaderLabel
@onready var close_button: Button = $VBox/Header/CloseButton
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var message_list: VBoxContainer = $VBox/ScrollContainer/MessageList
@onready var typing_indicator: HBoxContainer = $VBox/TypingIndicator
@onready var text_input: TextEdit = $VBox/ComposerBox/HBox/TextInput
@onready var send_button: Button = $VBox/ComposerBox/HBox/SendButton

func _ready() -> void:
	add_to_group("themed")
	_apply_theme()
	close_button.pressed.connect(_on_close)
	send_button.pressed.connect(_on_send)
	text_input.gui_input.connect(_on_input_key)
	text_input.text_changed.connect(_on_text_changed)
	AppState.voice_text_opened.connect(_on_voice_text_opened)
	AppState.voice_text_closed.connect(_on_voice_text_closed)
	AppState.messages_updated.connect(_on_messages_updated)
	AppState.typing_started.connect(_on_typing_started)
	AppState.typing_stopped.connect(_on_typing_stopped)

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("panel_bg")

	# "Load older messages" button at top of message list
	_older_btn = Button.new()
	_older_btn.text = "Show older messages"
	_older_btn.flat = true
	_older_btn.visible = false
	_older_btn.add_theme_font_size_override("font_size", 12)
	_older_btn.add_theme_color_override("font_color", ThemeManager.get_color("accent"))
	_older_btn.pressed.connect(_on_older_messages_pressed)
	message_list.add_child(_older_btn)

func _on_voice_text_opened(channel_id: String) -> void:
	_channel_id = channel_id
	visible = true

	# Look up channel name
	var ch_data: Dictionary = Client._channel_cache.get(channel_id, {})
	_channel_name = ch_data.get("name", channel_id)
	header_label.text = _channel_name
	text_input.placeholder_text = "Message #" + _channel_name

	# Clear old messages (keep persistent older button)
	for child in message_list.get_children():
		if child == _older_btn:
			continue
		child.queue_free()

	# Clear unread state for this voice channel
	Client.clear_channel_unread(channel_id)

	# Fetch messages for the voice channel
	Client.fetch.fetch_messages(channel_id)

	text_input.grab_focus()

func _on_voice_text_closed() -> void:
	_channel_id = ""
	visible = false
	typing_indicator.hide_typing()
	_older_btn.visible = false
	for child in message_list.get_children():
		if child == _older_btn:
			continue
		child.queue_free()

func _on_messages_updated(channel_id: String) -> void:
	if channel_id != _channel_id or not visible:
		return
	_render_messages()

func _render_messages() -> void:
	# Remove all children except the persistent older button
	for child in message_list.get_children():
		if child == _older_btn:
			continue
		child.queue_free()

	var messages: Array = Client.get_messages_for_channel(_channel_id)

	# Show older button if cache is full (more may exist server-side)
	_older_btn.visible = messages.size() >= Client.MESSAGE_CAP

	var prev_author_id: String = ""
	for i in messages.size():
		var msg: Dictionary = messages[i]
		var author: Dictionary = msg.get("author", {})
		var author_id: String = author.get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var use_collapsed: bool = (
			author_id == prev_author_id and not has_reply and i > 0
		)

		var node: HBoxContainer
		if use_collapsed:
			node = CollapsedMessageScene.instantiate()
		else:
			node = CozyMessageScene.instantiate()
		message_list.add_child(node)
		node.setup(msg)
		prev_author_id = author_id

	# Scroll to bottom (skip if loading older to preserve position)
	if not _is_loading_older:
		await get_tree().process_frame
		scroll_container.scroll_vertical = int(
			scroll_container.get_v_scroll_bar().max_value
		)

func _on_older_messages_pressed() -> void:
	if _is_loading_older or _channel_id.is_empty():
		return
	_is_loading_older = true
	_older_btn.text = "Loading..."
	_older_btn.disabled = true
	var sc := scroll_container
	var prev_scroll_max := sc.get_v_scroll_bar().max_value
	var prev_scroll_val := sc.scroll_vertical
	Client.fetch.fetch_older_messages(_channel_id)
	await AppState.messages_updated
	# Restore scroll position so it doesn't jump
	await get_tree().process_frame
	var new_scroll_max := sc.get_v_scroll_bar().max_value
	var diff := new_scroll_max - prev_scroll_max
	sc.scroll_vertical = prev_scroll_val + int(diff)
	# Hide button if fewer than MESSAGE_CAP were loaded (no more history)
	var messages: Array = Client.get_messages_for_channel(_channel_id)
	_older_btn.visible = messages.size() >= Client.MESSAGE_CAP
	_older_btn.text = "Show older messages"
	_older_btn.disabled = false
	_is_loading_older = false

func _on_close() -> void:
	AppState.close_voice_text()

func _on_send() -> void:
	var text := text_input.text.strip_edges()
	if text.is_empty():
		return
	text_input.text = ""
	Client.send_message_to_channel(_channel_id, text)

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_on_send()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			AppState.close_voice_text()

func _on_text_changed() -> void:
	if _channel_id.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_typing_time > 5000:
		_last_typing_time = now
		Client.send_typing(_channel_id)

func _on_typing_started(channel_id: String, username: String) -> void:
	if channel_id == _channel_id:
		typing_indicator.show_typing(username)

func _on_typing_stopped(channel_id: String) -> void:
	if channel_id == _channel_id:
		typing_indicator.hide_typing()
