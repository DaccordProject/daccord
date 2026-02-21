extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")

var _parent_message_id: String = ""
var _parent_channel_id: String = ""
var _also_send_to_channel: bool = false

@onready var close_button: Button = $VBox/Header/CloseButton
@onready var reply_count_label: Label = $VBox/ReplyCountLabel
@onready var parent_container: MarginContainer = $VBox/ParentMessageContainer
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var thread_message_list: VBoxContainer = $VBox/ScrollContainer/ThreadMessageList
@onready var thread_input: TextEdit = $VBox/ComposerBox/HBox/ThreadInput
@onready var send_button: Button = $VBox/ComposerBox/HBox/SendButton
@onready var also_send_check: CheckBox = $VBox/ComposerBox/AlsoSendCheck

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	send_button.pressed.connect(_on_send)
	thread_input.gui_input.connect(_on_input_key)
	also_send_check.toggled.connect(func(v: bool): _also_send_to_channel = v)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.thread_messages_updated.connect(_on_thread_messages_updated)

func _on_thread_opened(parent_message_id: String) -> void:
	_parent_message_id = parent_message_id
	visible = true

	# Find parent message data
	var parent_msg := Client.get_message_by_id(parent_message_id)
	_parent_channel_id = parent_msg.get("channel_id", AppState.current_channel_id)

	# Show parent message
	for child in parent_container.get_children():
		child.queue_free()
	if not parent_msg.is_empty():
		var parent_node := CozyMessageScene.instantiate()
		parent_container.add_child(parent_node)
		parent_node.setup(parent_msg)

	# Update reply count
	var count: int = parent_msg.get("reply_count", 0)
	if count > 0:
		reply_count_label.text = "%d %s" % [count, "reply" if count == 1 else "replies"]
		reply_count_label.visible = true
	else:
		reply_count_label.text = ""
		reply_count_label.visible = false

	# Clear existing thread messages
	for child in thread_message_list.get_children():
		child.queue_free()

	# Clear thread unread
	Client._thread_unread.erase(parent_message_id)

	# Fetch thread messages
	Client.fetch.fetch_thread_messages(_parent_channel_id, parent_message_id)

	# Focus input
	thread_input.grab_focus()

func _on_thread_closed() -> void:
	_parent_message_id = ""
	_parent_channel_id = ""
	visible = false
	for child in thread_message_list.get_children():
		child.queue_free()
	for child in parent_container.get_children():
		child.queue_free()

func _on_thread_messages_updated(parent_id: String) -> void:
	if parent_id != _parent_message_id:
		return
	_render_thread_messages()

func _render_thread_messages() -> void:
	for child in thread_message_list.get_children():
		child.queue_free()

	var messages := Client.get_messages_for_thread(_parent_message_id)
	var count := messages.size()
	if count > 0:
		reply_count_label.text = "%d %s" % [count, "reply" if count == 1 else "replies"]
		reply_count_label.visible = true
	else:
		reply_count_label.visible = false

	var prev_author_id: String = ""
	for i in messages.size():
		var msg: Dictionary = messages[i]
		var author: Dictionary = msg.get("author", {})
		var author_id: String = author.get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var use_collapsed: bool = (author_id == prev_author_id) and not has_reply and i > 0

		var node: HBoxContainer
		if use_collapsed:
			node = CollapsedMessageScene.instantiate()
		else:
			node = CozyMessageScene.instantiate()
		thread_message_list.add_child(node)
		node.setup(msg)
		prev_author_id = author_id

	# Scroll to bottom
	await get_tree().process_frame
	scroll_container.scroll_vertical = int(
		scroll_container.get_v_scroll_bar().max_value
	)

func _on_close() -> void:
	AppState.close_thread()

func _on_send() -> void:
	var text := thread_input.text.strip_edges()
	if text.is_empty():
		return
	thread_input.text = ""

	# Send as thread reply
	Client.send_message_to_channel(
		_parent_channel_id, text, "", [], _parent_message_id
	)

	# Optionally also send to channel
	if _also_send_to_channel:
		Client.send_message_to_channel(
			_parent_channel_id, text, _parent_message_id
		)

func _on_input_key(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			get_viewport().set_input_as_handled()
			_on_send()
		elif event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			AppState.close_thread()
