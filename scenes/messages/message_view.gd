extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")

var auto_scroll: bool = true
var current_channel_id: String = ""

@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var message_list: VBoxContainer = $VBox/ScrollContainer/MessageList
@onready var typing_indicator: HBoxContainer = $VBox/TypingIndicator
@onready var composer: PanelContainer = $VBox/Composer
@onready var older_btn: Button = $VBox/ScrollContainer/MessageList/OlderMessagesBtn

func _ready() -> void:
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.message_sent.connect(_on_message_sent)
	AppState.message_edited.connect(_on_message_edited)
	AppState.message_deleted.connect(_on_message_deleted)
	AppState.messages_updated.connect(_on_messages_updated)
	AppState.typing_started.connect(_on_typing_started)
	AppState.typing_stopped.connect(_on_typing_stopped)
	scroll_container.get_v_scroll_bar().changed.connect(_on_scrollbar_changed)
	scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	older_btn.pressed.connect(func(): older_btn.visible = false)

func _on_channel_selected(channel_id: String) -> void:
	current_channel_id = channel_id
	Client.fetch_messages(channel_id)

	# Update composer placeholder
	for ch in Client.channels:
		if ch["id"] == channel_id:
			composer.set_channel_name(ch.get("name", "channel"))
			break
	for dm in Client.dm_channels:
		if dm["id"] == channel_id:
			var user: Dictionary = dm.get("user", {})
			composer.set_channel_name(user.get("display_name", "DM"))
			break

func _load_messages(channel_id: String) -> void:
	# Clear existing messages (skip the persistent OlderMessagesBtn at index 0)
	for child in message_list.get_children():
		if child == older_btn:
			continue
		child.queue_free()

	var messages := Client.get_messages_for_channel(channel_id)

	# Only show "older messages" button if we hit the message cap (more may exist)
	older_btn.visible = messages.size() >= Client.MESSAGE_CAP
	var prev_author_id: String = ""

	for i in messages.size():
		var msg: Dictionary = messages[i]
		var author: Dictionary = msg.get("author", {})
		var author_id: String = author.get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""

		# Use collapsed style if same author and no reply
		var use_collapsed: bool = (author_id == prev_author_id) and not has_reply and i > 0

		if use_collapsed:
			var collapsed: HBoxContainer = CollapsedMessageScene.instantiate()
			message_list.add_child(collapsed)
			collapsed.setup(msg)
		else:
			var cozy: HBoxContainer = CozyMessageScene.instantiate()
			message_list.add_child(cozy)
			cozy.setup(msg)

		prev_author_id = author_id

	# Ensure we don't exceed message cap (index 0 is the older_btn)
	while message_list.get_child_count() > Client.MESSAGE_CAP + 1:
		message_list.get_child(1).queue_free()

	# Scroll to bottom
	auto_scroll = true
	await get_tree().process_frame
	_scroll_to_bottom()

func _on_message_sent(text: String) -> void:
	var reply_to: String = AppState.replying_to_message_id
	Client.send_message_to_channel(current_channel_id, text, reply_to)

func _on_message_edited(message_id: String, new_content: String) -> void:
	Client.update_message_content(message_id, new_content)

func _on_message_deleted(message_id: String) -> void:
	Client.remove_message(message_id)

func _on_messages_updated(channel_id: String) -> void:
	if channel_id == current_channel_id:
		_load_messages(channel_id)

func _on_typing_started(channel_id: String, username: String) -> void:
	if channel_id == current_channel_id:
		typing_indicator.show_typing(username)

func _on_typing_stopped(channel_id: String) -> void:
	if channel_id == current_channel_id:
		typing_indicator.hide_typing()

func _scroll_to_bottom() -> void:
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _on_scrollbar_changed() -> void:
	if auto_scroll:
		_scroll_to_bottom()

func _on_scroll_value_changed(value: float) -> void:
	var scrollbar := scroll_container.get_v_scroll_bar()
	auto_scroll = value >= scrollbar.max_value - scrollbar.page - 10
