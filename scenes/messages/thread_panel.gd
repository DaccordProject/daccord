extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")

var _parent_message_id: String = ""
var _parent_channel_id: String = ""
var _also_send_to_channel: bool = false
var _notify_popup: PopupMenu
var _last_typing_time: int = 0

@onready var thread_title: Label = $VBox/Header/ThreadTitle
@onready var notify_button: Button = $VBox/Header/NotifyButton
@onready var close_button: Button = $VBox/Header/CloseButton
@onready var reply_count_label: Label = $VBox/ReplyCountLabel
@onready var parent_container: MarginContainer = $VBox/ParentMessageContainer
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var thread_message_list: VBoxContainer = $VBox/ScrollContainer/ThreadMessageList
@onready var thread_input: TextEdit = $VBox/ComposerBox/HBox/ThreadInput
@onready var send_button: Button = $VBox/ComposerBox/HBox/SendButton
@onready var thread_typing_indicator: HBoxContainer = $VBox/ThreadTypingIndicator
@onready var also_send_check: CheckBox = $VBox/ComposerBox/AlsoSendCheck

func _ready() -> void:
	add_to_group("themed")
	_apply_theme()
	close_button.pressed.connect(_on_close)
	notify_button.pressed.connect(_on_notify_pressed)
	send_button.pressed.connect(_on_send)
	thread_input.gui_input.connect(_on_input_key)
	thread_input.text_changed.connect(_on_thread_input_changed)
	also_send_check.toggled.connect(func(v: bool): _also_send_to_channel = v)
	AppState.guest_mode_changed.connect(_on_guest_mode_changed)

func _apply_theme() -> void:
	var style: StyleBox = get_theme_stylebox("panel")
	if style is StyleBoxFlat:
		style.bg_color = ThemeManager.get_color("panel_bg")
	_notify_popup = PopupMenu.new()
	_notify_popup.add_item(tr("Default"), 0)
	_notify_popup.add_item(tr("All Messages"), 1)
	_notify_popup.add_item(tr("Mentions Only"), 2)
	_notify_popup.add_item(tr("Nothing"), 3)
	_notify_popup.id_pressed.connect(_on_notify_option_selected)
	add_child(_notify_popup)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.thread_messages_updated.connect(_on_thread_messages_updated)
	AppState.reactions_updated.connect(_on_reactions_updated)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	AppState.thread_typing_started.connect(_on_thread_typing_started)
	AppState.thread_typing_stopped.connect(_on_thread_typing_stopped)
	_apply_layout(AppState.current_layout_mode)
	ThemeManager.apply_font_colors(self)

func _on_thread_opened(parent_message_id: String) -> void:
	_parent_message_id = parent_message_id
	visible = true

	# Find parent message data
	var parent_msg := Client.get_message_by_id(parent_message_id)
	_parent_channel_id = parent_msg.get("channel_id", AppState.current_channel_id)

	# Show parent message
	NodeUtils.free_children(parent_container)
	if not parent_msg.is_empty():
		var parent_node := CozyMessageScene.instantiate()
		parent_container.add_child(parent_node)
		parent_node.setup(parent_msg)

	# Update reply count
	var count: int = parent_msg.get("reply_count", 0)
	if count > 0:
		reply_count_label.text = tr("%d %s") % [count, tr("reply") if count == 1 else tr("replies")]
		reply_count_label.visible = true
	else:
		reply_count_label.text = ""
		reply_count_label.visible = false

	# Clear existing thread messages
	NodeUtils.free_children(thread_message_list)

	# Clear thread unread and mentions
	Client._thread_unread.erase(parent_message_id)
	Client._thread_mention_count.erase(parent_message_id)

	# Fetch thread messages
	Client.fetch.fetch_thread_messages(_parent_channel_id, parent_message_id)

	# Hide "Also send to channel" for forum threads (forums have no separate channel)
	var ch: Dictionary = Client._channel_cache.get(_parent_channel_id, {})
	var is_forum: bool = ch.get("type", 0) == ClientModels.ChannelType.FORUM
	also_send_check.visible = not is_forum
	if is_forum:
		_also_send_to_channel = false
		also_send_check.button_pressed = false

	# Guest mode: gray out composer
	if AppState.is_guest_mode:
		thread_input.editable = false
		send_button.disabled = true
		thread_input.placeholder_text = tr("Sign in to reply")
		thread_input.modulate.a = 0.5
		send_button.modulate.a = 0.5
		also_send_check.visible = false
		return

	# Check SEND_IN_THREADS permission
	var space_id: String = Client._channel_to_space.get(_parent_channel_id, "")
	var can_send: bool = Client.has_channel_permission(
		space_id, _parent_channel_id, AccordPermission.SEND_IN_THREADS
	)
	thread_input.editable = can_send
	send_button.disabled = not can_send
	thread_input.modulate.a = 1.0
	send_button.modulate.a = 1.0
	if not can_send:
		thread_input.placeholder_text = tr("You don't have permission to reply in threads")
	else:
		thread_input.placeholder_text = tr("Reply in thread...")

	# Focus input
	if can_send:
		thread_input.grab_focus()

func _on_thread_closed() -> void:
	_parent_message_id = ""
	_parent_channel_id = ""
	visible = false
	thread_typing_indicator.hide_typing()
	NodeUtils.free_children(thread_message_list)
	NodeUtils.free_children(parent_container)

func _on_thread_messages_updated(parent_id: String) -> void:
	if parent_id != _parent_message_id:
		return
	_render_thread_messages()

func _on_reactions_updated(channel_id: String, _message_id: String) -> void:
	if channel_id != _parent_channel_id:
		return
	if not visible or _parent_message_id.is_empty():
		return
	# Re-render thread messages to pick up reaction changes
	_render_thread_messages()

func _render_thread_messages() -> void:
	NodeUtils.free_children(thread_message_list)

	var messages := Client.get_messages_for_thread(_parent_message_id)
	var count := messages.size()
	if count > 0:
		reply_count_label.text = tr("%d %s") % [count, tr("reply") if count == 1 else tr("replies")]
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

func _on_notify_pressed() -> void:
	if _parent_message_id.is_empty():
		return
	var current: String = Config.get_thread_notifications(_parent_message_id)
	var mode_map: Dictionary = {"default": 0, "all": 1, "mentions": 2, "nothing": 3}
	var current_idx: int = mode_map.get(current, 0)
	for i in _notify_popup.item_count:
		_notify_popup.set_item_checked(i, i == current_idx)
	var btn_rect := notify_button.get_global_rect()
	_notify_popup.position = Vector2i(
		int(btn_rect.position.x),
		int(btn_rect.position.y + btn_rect.size.y)
	)
	_notify_popup.popup()

func _on_notify_option_selected(id: int) -> void:
	var modes: Array = ["default", "all", "mentions", "nothing"]
	if id >= 0 and id < modes.size():
		Config.set_thread_notifications(_parent_message_id, modes[id])

func _on_close() -> void:
	AppState.close_thread()

func _on_send() -> void:
	if GuestPrompt.show_if_guest():
		return
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

func _on_thread_input_changed() -> void:
	if _parent_channel_id.is_empty():
		return
	if thread_input.text.strip_edges().is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _last_typing_time > 8000:
		_last_typing_time = now
		Client.send_typing(_parent_channel_id, _parent_message_id)

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	_apply_layout(mode)

func _apply_layout(mode: AppState.LayoutMode) -> void:
	match mode:
		AppState.LayoutMode.COMPACT:
			close_button.text = tr("\u2190 Back")
			custom_minimum_size.x = 0
		_:
			close_button.text = "X"
			custom_minimum_size.x = 340

func _on_thread_typing_started(thread_id: String, username: String) -> void:
	if thread_id == _parent_message_id:
		thread_typing_indicator.show_typing(username)

func _on_thread_typing_stopped(thread_id: String) -> void:
	if thread_id == _parent_message_id:
		thread_typing_indicator.hide_typing()

func _on_guest_mode_changed(is_guest: bool) -> void:
	if not visible or _parent_message_id.is_empty():
		return
	if is_guest:
		thread_input.editable = false
		send_button.disabled = true
		thread_input.placeholder_text = tr("Sign in to reply")
		thread_input.modulate.a = 0.5
		send_button.modulate.a = 0.5
	else:
		thread_input.editable = true
		send_button.disabled = false
		thread_input.placeholder_text = tr("Reply in thread...")
		thread_input.modulate.a = 1.0
		send_button.modulate.a = 1.0
