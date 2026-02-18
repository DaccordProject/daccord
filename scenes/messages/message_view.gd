extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")
const MessageActionBarScene := preload("res://scenes/messages/message_action_bar.tscn")

var auto_scroll: bool = true
var current_channel_id: String = ""
var _current_channel_name: String = ""
var _is_loading: bool = false

var _action_bar: PanelContainer
var _hovered_message: Control = null
var _hover_timer: Timer
var _hover_hide_pending: bool = false

var _delete_dialog: ConfirmationDialog
var _pending_delete_id: String = ""
var _is_loading_older: bool = false

var _banner_hide_timer: Timer
var _loading_timeout_timer: Timer
var _banner_style_warning: StyleBoxFlat
var _banner_style_error: StyleBoxFlat
var _banner_style_success: StyleBoxFlat

@onready var connection_banner: PanelContainer = $VBox/ConnectionBanner
@onready var banner_status_label: Label = $VBox/ConnectionBanner/HBox/StatusLabel
@onready var banner_retry_button: Button = $VBox/ConnectionBanner/HBox/RetryButton
@onready var scroll_container: ScrollContainer = $VBox/ScrollContainer
@onready var message_list: VBoxContainer = $VBox/ScrollContainer/MessageList
@onready var typing_indicator: HBoxContainer = $VBox/TypingIndicator
@onready var composer: PanelContainer = $VBox/Composer
@onready var older_btn: Button = $VBox/ScrollContainer/MessageList/OlderMessagesBtn
@onready var empty_state: VBoxContainer = $VBox/ScrollContainer/MessageList/EmptyState
@onready var loading_label: Label = $VBox/ScrollContainer/MessageList/LoadingLabel

func _ready() -> void:
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.message_sent.connect(_on_message_sent)
	AppState.message_edited.connect(_on_message_edited)
	AppState.message_deleted.connect(_on_message_deleted)
	AppState.messages_updated.connect(_on_messages_updated)
	AppState.edit_requested.connect(_on_edit_requested)
	AppState.typing_started.connect(_on_typing_started)
	AppState.typing_stopped.connect(_on_typing_stopped)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	AppState.server_disconnected.connect(_on_server_disconnected)
	AppState.server_reconnecting.connect(_on_server_reconnecting)
	AppState.server_reconnected.connect(_on_server_reconnected)
	AppState.server_connection_failed.connect(_on_server_connection_failed)
	AppState.message_fetch_failed.connect(_on_message_fetch_failed)
	scroll_container.get_v_scroll_bar().changed.connect(_on_scrollbar_changed)
	scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	older_btn.pressed.connect(_on_older_messages_pressed)
	banner_retry_button.pressed.connect(_on_retry_pressed)
	loading_label.gui_input.connect(_on_loading_label_input)

	# Banner styles
	_banner_style_warning = StyleBoxFlat.new()
	_banner_style_warning.bg_color = Color(0.75, 0.55, 0.1, 0.9)
	_banner_style_warning.set_content_margin_all(6)
	_banner_style_warning.set_corner_radius_all(4)

	_banner_style_error = StyleBoxFlat.new()
	_banner_style_error.bg_color = Color(0.75, 0.2, 0.2, 0.9)
	_banner_style_error.set_content_margin_all(6)
	_banner_style_error.set_corner_radius_all(4)

	_banner_style_success = StyleBoxFlat.new()
	_banner_style_success.bg_color = Color(0.2, 0.65, 0.3, 0.9)
	_banner_style_success.set_content_margin_all(6)
	_banner_style_success.set_corner_radius_all(4)

	# Banner auto-hide timer
	_banner_hide_timer = Timer.new()
	_banner_hide_timer.wait_time = 3.0
	_banner_hide_timer.one_shot = true
	_banner_hide_timer.timeout.connect(func(): connection_banner.visible = false)
	add_child(_banner_hide_timer)

	# Loading timeout timer
	_loading_timeout_timer = Timer.new()
	_loading_timeout_timer.wait_time = 15.0
	_loading_timeout_timer.one_shot = true
	_loading_timeout_timer.timeout.connect(_on_loading_timeout)
	add_child(_loading_timeout_timer)

	# Action bar
	_action_bar = MessageActionBarScene.instantiate()
	add_child(_action_bar)
	_action_bar.top_level = true
	_action_bar.action_reply.connect(_on_bar_reply)
	_action_bar.action_edit.connect(_on_bar_edit)
	_action_bar.action_delete.connect(_on_bar_delete)
	_action_bar.mouse_exited.connect(_on_action_bar_unhovered)

	# Hover debounce timer
	_hover_timer = Timer.new()
	_hover_timer.wait_time = 0.1
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)

func _process(_delta: float) -> void:
	if not _action_bar.visible or _hovered_message == null:
		return
	if not is_instance_valid(_hovered_message):
		_hide_action_bar()
		return
	_position_action_bar()

func _on_channel_selected(channel_id: String) -> void:
	current_channel_id = channel_id
	_current_channel_name = "channel"
	_is_loading = true
	_hide_action_bar()
	_update_empty_state([])
	# Reset loading label style
	loading_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
	loading_label.text = "Loading messages..."
	loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_timeout_timer.start()
	Client.fetch.fetch_messages(channel_id)

	# Update composer placeholder
	for ch in Client.channels:
		if ch["id"] == channel_id:
			_current_channel_name = ch.get("name", "channel")
			composer.set_channel_name(_current_channel_name)
			break
	for dm in Client.dm_channels:
		if dm["id"] == channel_id:
			var user: Dictionary = dm.get("user", {})
			_current_channel_name = user.get("display_name", "DM")
			composer.set_channel_name(_current_channel_name)
			break

	composer.update_enabled_state()

func _update_empty_state(messages: Array) -> void:
	if _is_loading:
		empty_state.visible = false
		loading_label.visible = true
	elif messages.is_empty():
		empty_state.visible = true
		loading_label.visible = false
		var title_label: Label = empty_state.get_node("Title")
		var desc_label: Label = empty_state.get_node("Description")
		if AppState.is_dm_mode:
			title_label.text = "No messages yet"
			desc_label.text = "Send a message to start the conversation."
		else:
			title_label.text = "Welcome to #%s" % _current_channel_name
			desc_label.text = "This is the beginning of this channel." \
				+ " Send a message to get the conversation started!"
	else:
		empty_state.visible = false
		loading_label.visible = false

func _load_messages(channel_id: String) -> void:
	_hide_action_bar()
	_loading_timeout_timer.stop()

	# Save editing state before clearing
	var editing_id := AppState.editing_message_id
	var editing_text := ""
	if not editing_id.is_empty():
		for child in message_list.get_children():
			if child == older_btn or child == empty_state or child == loading_label:
				continue
			var mc = child.get("message_content")
			if mc and mc.is_editing():
				editing_text = mc.get_edit_text()
				break

	# Clear existing messages (skip persistent nodes)
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		child.queue_free()

	var messages := Client.get_messages_for_channel(channel_id)
	_is_loading = false
	_update_empty_state(messages)

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
			collapsed.mouse_entered.connect(_on_msg_hovered.bind(collapsed))
			collapsed.mouse_exited.connect(_on_msg_unhovered.bind(collapsed))
		else:
			var cozy: HBoxContainer = CozyMessageScene.instantiate()
			message_list.add_child(cozy)
			cozy.setup(msg)
			cozy.mouse_entered.connect(_on_msg_hovered.bind(cozy))
			cozy.mouse_exited.connect(_on_msg_unhovered.bind(cozy))

		prev_author_id = author_id

	# Restore editing state if a message was being edited
	if not editing_id.is_empty():
		for child in message_list.get_children():
			if child == older_btn or child == empty_state or child == loading_label:
				continue
			if child.get("_message_data") is Dictionary and child._message_data.get("id", "") == editing_id:
				var mc = child.get("message_content")
				if mc:
					mc.enter_edit_mode(editing_id, editing_text)
				break

	# Scroll to bottom (skip when loading older messages to preserve position)
	if not _is_loading_older:
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

func _on_edit_requested(message_id: String) -> void:
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		if child.get("_message_data") is Dictionary and child._message_data.get("id", "") == message_id:
			var mc = child.get("message_content")
			if mc:
				mc.enter_edit_mode(message_id, child._message_data.get("content", ""))
			break

func _on_messages_updated(channel_id: String) -> void:
	if channel_id == current_channel_id:
		_load_messages(channel_id)

func _on_typing_started(channel_id: String, username: String) -> void:
	if channel_id == current_channel_id:
		typing_indicator.show_typing(username)

func _on_typing_stopped(channel_id: String) -> void:
	if channel_id == current_channel_id:
		typing_indicator.hide_typing()

# --- Action Bar Hover State Machine ---

func _on_msg_hovered(msg_node: Control) -> void:
	if AppState.current_layout_mode == AppState.LayoutMode.COMPACT:
		return
	# Suppress bar when message is being edited
	var mc = msg_node.get("message_content")
	if mc and mc.is_editing():
		return

	_hover_timer.stop()
	_hover_hide_pending = false

	# Clear previous hover highlight
	if _hovered_message and is_instance_valid(_hovered_message) and _hovered_message != msg_node:
		if _hovered_message.has_method("set_hovered"):
			_hovered_message.set_hovered(false)

	_hovered_message = msg_node
	if msg_node.has_method("set_hovered"):
		msg_node.set_hovered(true)

	var msg_data: Dictionary = msg_node.get("_message_data")
	if msg_data == null:
		msg_data = {}
	_action_bar.show_for_message(msg_node, msg_data)
	_position_action_bar()

func _on_msg_unhovered(_msg_node: Control) -> void:
	_hover_hide_pending = true
	_hover_timer.start()

func _on_action_bar_unhovered() -> void:
	_hover_hide_pending = true
	_hover_timer.start()

func _on_hover_timer_timeout() -> void:
	if not _hover_hide_pending:
		return
	if _action_bar.is_bar_hovered():
		_hover_hide_pending = false
		return
	# Check if mouse moved to a different message (handled by _on_msg_hovered)
	_hide_action_bar()

func _hide_action_bar() -> void:
	_hover_timer.stop()
	_hover_hide_pending = false
	_action_bar.hide_bar()
	if _hovered_message and is_instance_valid(_hovered_message):
		if _hovered_message.has_method("set_hovered"):
			_hovered_message.set_hovered(false)
	_hovered_message = null

func _position_action_bar() -> void:
	if _hovered_message == null or not is_instance_valid(_hovered_message):
		return

	var msg_rect := _hovered_message.get_global_rect()
	var scroll_rect := scroll_container.get_global_rect()

	# Hide if message scrolled out of view
	var msg_bottom := msg_rect.position.y + msg_rect.size.y
	var scroll_bottom := scroll_rect.position.y + scroll_rect.size.y
	if msg_bottom < scroll_rect.position.y or msg_rect.position.y > scroll_bottom:
		_action_bar.visible = false
		return
	_action_bar.visible = true

	var bar_size := _action_bar.size
	# Position at top-right of message, offset up by half bar height
	var x := msg_rect.position.x + msg_rect.size.x - bar_size.x - 8
	var y := msg_rect.position.y - bar_size.y * 0.5
	# Clamp within scroll container bounds
	y = clampf(y, scroll_rect.position.y, scroll_rect.position.y + scroll_rect.size.y - bar_size.y)
	_action_bar.position = Vector2(x, y)

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	if mode == AppState.LayoutMode.COMPACT:
		_hide_action_bar()

# --- Action Bar Callbacks ---

func _on_bar_reply(msg_data: Dictionary) -> void:
	AppState.initiate_reply(msg_data.get("id", ""))
	_hide_action_bar()

func _on_bar_edit(msg_data: Dictionary) -> void:
	var msg_id: String = msg_data.get("id", "")
	AppState.start_editing(msg_id)
	# Find the message node and enter edit mode
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		if child.get("_message_data") is Dictionary and child._message_data.get("id", "") == msg_id:
			var mc = child.get("message_content")
			if mc:
				mc.enter_edit_mode(msg_id, msg_data.get("content", ""))
			break
	_hide_action_bar()

func _on_bar_delete(msg_data: Dictionary) -> void:
	_pending_delete_id = msg_data.get("id", "")
	_hide_action_bar()
	if not _delete_dialog:
		_delete_dialog = ConfirmationDialog.new()
		_delete_dialog.dialog_text = "Are you sure you want to delete this message?"
		_delete_dialog.confirmed.connect(_on_delete_confirmed)
		add_child(_delete_dialog)
	_delete_dialog.popup_centered()

func _on_delete_confirmed() -> void:
	if not _pending_delete_id.is_empty():
		AppState.delete_message(_pending_delete_id)
		_pending_delete_id = ""

# --- Connection Banner ---

func _guild_for_current_channel() -> String:
	return Client._channel_to_guild.get(current_channel_id, "")

func _on_server_disconnected(guild_id: String, _code: int, _reason: String) -> void:
	if guild_id != _guild_for_current_channel():
		return
	_banner_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _banner_style_warning)
	banner_status_label.text = "Connection lost. Reconnecting..."
	banner_retry_button.visible = false
	connection_banner.visible = true

func _on_server_reconnecting(guild_id: String, attempt: int, max_attempts: int) -> void:
	if guild_id != _guild_for_current_channel():
		return
	_banner_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _banner_style_warning)
	banner_status_label.text = "Reconnecting... (attempt %d/%d)" % [attempt, max_attempts]
	banner_retry_button.visible = false
	connection_banner.visible = true

func _on_server_reconnected(guild_id: String) -> void:
	if guild_id != _guild_for_current_channel():
		return
	connection_banner.add_theme_stylebox_override("panel", _banner_style_success)
	banner_status_label.text = "Reconnected!"
	banner_retry_button.visible = false
	connection_banner.visible = true
	_banner_hide_timer.start()

func _on_server_connection_failed(guild_id: String, reason: String) -> void:
	if guild_id != _guild_for_current_channel():
		return
	_banner_hide_timer.stop()
	connection_banner.add_theme_stylebox_override("panel", _banner_style_error)
	banner_status_label.text = "Connection failed: %s" % reason
	banner_retry_button.visible = true
	connection_banner.visible = true

func _on_retry_pressed() -> void:
	var guild_id := _guild_for_current_channel()
	var idx := Client.get_conn_index_for_guild(guild_id)
	if idx >= 0:
		connection_banner.add_theme_stylebox_override("panel", _banner_style_warning)
		banner_status_label.text = "Reconnecting..."
		banner_retry_button.visible = false
		# Clear the auto-reconnect guard so the full cycle can
		# be attempted again after the user presses retry.
		Client._auto_reconnect_attempted.erase(idx)
		Client.reconnect_server(idx)

# --- Fetch Failure & Loading Timeout ---

func _on_message_fetch_failed(channel_id: String, error: String) -> void:
	if channel_id != current_channel_id:
		return
	_is_loading = false
	_loading_timeout_timer.stop()
	loading_label.text = "Failed to load messages: %s\nClick to retry" % error
	loading_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	loading_label.visible = true
	loading_label.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_loading_timeout() -> void:
	if not _is_loading:
		return
	_is_loading = false
	loading_label.text = "Loading timed out. Click to retry"
	loading_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	loading_label.mouse_filter = Control.MOUSE_FILTER_STOP

func _on_loading_label_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not _is_loading and loading_label.visible:
			_is_loading = true
			loading_label.text = "Loading messages..."
			loading_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643, 1))
			loading_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_loading_timeout_timer.start()
			Client.fetch.fetch_messages(current_channel_id)

# --- Scroll ---

func _scroll_to_bottom() -> void:
	scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _on_scrollbar_changed() -> void:
	if auto_scroll:
		_scroll_to_bottom()

func _on_scroll_value_changed(value: float) -> void:
	var scrollbar := scroll_container.get_v_scroll_bar()
	auto_scroll = value >= scrollbar.max_value - scrollbar.page - 10

# --- Older Messages ---

func _on_older_messages_pressed() -> void:
	if _is_loading_older or current_channel_id.is_empty():
		return
	_is_loading_older = true
	auto_scroll = false
	older_btn.text = "Loading..."
	older_btn.disabled = true
	var count_before := Client.get_messages_for_channel(
		current_channel_id
	).size()
	# Save scroll height before loading
	var prev_scroll_max := scroll_container.get_v_scroll_bar().max_value
	var prev_scroll_val := scroll_container.scroll_vertical
	Client.fetch.fetch_older_messages(current_channel_id)
	# Wait for re-render triggered by messages_updated
	await AppState.messages_updated
	# Restore scroll position so it doesn't jump
	await get_tree().process_frame
	var new_scroll_max := scroll_container.get_v_scroll_bar().max_value
	var diff := new_scroll_max - prev_scroll_max
	scroll_container.scroll_vertical = prev_scroll_val + int(diff)
	# Hide button if fewer than MESSAGE_CAP were loaded (no more history)
	var count_after := Client.get_messages_for_channel(
		current_channel_id
	).size()
	var loaded := count_after - count_before
	if loaded < Client.MESSAGE_CAP:
		older_btn.visible = false
	older_btn.text = "Show older messages"
	older_btn.disabled = false
	_is_loading_older = false
