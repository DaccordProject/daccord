extends PanelContainer

const CozyMessageScene := preload("res://scenes/messages/cozy_message.tscn")
const CollapsedMessageScene := preload("res://scenes/messages/collapsed_message.tscn")
const MessageActionBarScene := preload("res://scenes/messages/message_action_bar.tscn")
const ReactionPickerScene := preload("res://scenes/messages/reaction_picker.tscn")

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

var _context_menu: PopupMenu
var _context_menu_data: Dictionary = {}
var _reaction_picker: Control = null

var _scroll_tween: Tween
var _channel_transition_tween: Tween
var _old_message_count: int = 0
var _pending_edit_content: Dictionary = {}
var _message_node_index: Dictionary = {} # message_id -> scene node

var _banner_hide_timer: Timer
var _loading_timeout_timer: Timer
var _banner: MessageViewBanner

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
	AppState.message_edit_failed.connect(_on_message_edit_failed)
	AppState.message_deleted.connect(_on_message_deleted)
	AppState.messages_updated.connect(_on_messages_updated)
	AppState.reactions_updated.connect(_on_reactions_updated)
	AppState.edit_requested.connect(_on_edit_requested)
	AppState.typing_started.connect(_on_typing_started)
	AppState.typing_stopped.connect(_on_typing_stopped)
	AppState.layout_mode_changed.connect(_on_layout_mode_changed)
	AppState.message_fetch_failed.connect(_on_message_fetch_failed)
	scroll_container.get_v_scroll_bar().changed.connect(_on_scrollbar_changed)
	scroll_container.get_v_scroll_bar().value_changed.connect(_on_scroll_value_changed)
	older_btn.pressed.connect(_on_older_messages_pressed)
	banner_retry_button.pressed.connect(func(): _banner.on_retry_pressed())
	loading_label.gui_input.connect(_on_loading_label_input)

	# Banner auto-hide timer
	_banner_hide_timer = Timer.new()
	_banner_hide_timer.wait_time = 3.0
	_banner_hide_timer.one_shot = true
	_banner_hide_timer.timeout.connect(func(): connection_banner.visible = false)
	add_child(_banner_hide_timer)

	# Connection banner helper
	_banner = MessageViewBanner.new(
		connection_banner,
		banner_status_label,
		banner_retry_button,
		_banner_hide_timer,
		_guild_for_current_channel,
	)
	AppState.server_disconnected.connect(_banner.on_server_disconnected)
	AppState.server_reconnecting.connect(_banner.on_server_reconnecting)
	AppState.server_reconnected.connect(_banner.on_server_reconnected)
	AppState.server_connection_failed.connect(
		_banner.on_server_connection_failed
	)

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

	# Shared context menu
	_context_menu = PopupMenu.new()
	_context_menu.add_item("Reply", 0)
	_context_menu.add_item("Edit", 1)
	_context_menu.add_item("Delete", 2)
	_context_menu.add_item("Add Reaction", 3)
	_context_menu.add_item("Remove All Reactions", 4)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)

	# Hover debounce timer
	_hover_timer = Timer.new()
	_hover_timer.wait_time = 0.1
	_hover_timer.one_shot = true
	_hover_timer.timeout.connect(_on_hover_timer_timeout)
	add_child(_hover_timer)

func _unhandled_input(event: InputEvent) -> void:
	if AppState.is_imposter_mode and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		AppState.exit_imposter_mode()
		get_viewport().set_input_as_handled()

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
	_old_message_count = 0
	_message_node_index.clear()
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

	# Track message count before clearing for animation decisions
	var old_count := _old_message_count

	# Clear existing messages (skip persistent nodes)
	_message_node_index.clear()
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		child.queue_free()

	var messages := Client.get_messages_for_channel(channel_id)
	_is_loading = false
	_update_empty_state(messages)

	var new_count := messages.size()
	_old_message_count = new_count

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

		var node: HBoxContainer
		if use_collapsed:
			node = CollapsedMessageScene.instantiate()
			message_list.add_child(node)
			node.setup(msg)
		else:
			node = CozyMessageScene.instantiate()
			message_list.add_child(node)
			node.setup(msg)
		node.mouse_entered.connect(_on_msg_hovered.bind(node))
		node.mouse_exited.connect(_on_msg_unhovered.bind(node))
		if node.has_signal("context_menu_requested"):
			node.context_menu_requested.connect(_on_context_menu_requested)
		_message_node_index[msg.get("id", "")] = node

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

	# Determine which animation to play
	var is_single_new_message: bool = old_count > 0 and new_count == old_count + 1

	if not Config.get_reduced_motion():
		if is_single_new_message and not _is_loading_older:
			# Fade in the last message child
			var last_msg := _get_last_message_child()
			if last_msg:
				last_msg.modulate.a = 0.0
				var msg_tween := create_tween()
				msg_tween.tween_property(last_msg, "modulate:a", 1.0, 0.15) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		elif not _is_loading_older and old_count != new_count:
			# Channel transition fade-in (not for single new messages or older-message loads)
			if _channel_transition_tween and _channel_transition_tween.is_valid():
				_channel_transition_tween.kill()
			scroll_container.modulate.a = 0.0
			_channel_transition_tween = create_tween()
			_channel_transition_tween.tween_property(scroll_container, "modulate:a", 1.0, 0.15) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Scroll to bottom (skip when loading older messages to preserve position)
	if not _is_loading_older:
		auto_scroll = true
		await get_tree().process_frame
		_scroll_to_bottom_animated()

func _on_message_sent(text: String) -> void:
	var reply_to: String = AppState.replying_to_message_id
	var attachments: Array = AppState.pending_attachments.duplicate()
	AppState.pending_attachments.clear()
	Client.send_message_to_channel(current_channel_id, text, reply_to, attachments)

func _on_message_edited(message_id: String, new_content: String) -> void:
	_pending_edit_content[message_id] = new_content
	Client.update_message_content(message_id, new_content)

func _on_message_edit_failed(message_id: String, error: String) -> void:
	var failed_content: String = _pending_edit_content.get(message_id, "")
	_pending_edit_content.erase(message_id)
	# Re-enter edit mode on the failed message with the content that failed to save
	AppState.start_editing(message_id)
	var node: Control = _find_message_node(message_id)
	if node:
		var mc = node.get("message_content")
		if mc:
			mc.enter_edit_mode(message_id, failed_content)
			mc.show_edit_error("Edit failed: %s" % error)

func _on_message_deleted(message_id: String) -> void:
	Client.remove_message(message_id)

func _on_edit_requested(message_id: String) -> void:
	var node: Control = _find_message_node(message_id)
	if node:
		var mc = node.get("message_content")
		if mc:
			mc.enter_edit_mode(message_id, node._message_data.get("content", ""))

func _on_messages_updated(channel_id: String) -> void:
	if channel_id != current_channel_id:
		return
	# First load or older-messages load: fall back to full re-render
	if _message_node_index.is_empty() or _is_loading_older:
		_load_messages(channel_id)
		return
	_diff_messages(channel_id)

func _diff_messages(channel_id: String) -> void:
	_loading_timeout_timer.stop()
	var messages := Client.get_messages_for_channel(channel_id)
	_is_loading = false
	_update_empty_state(messages)

	# Build set of current message IDs from cache
	var cache_ids: Dictionary = {}
	for msg in messages:
		cache_ids[msg.get("id", "")] = true

	# REMOVE: nodes for messages no longer in cache
	var removed_ids: Array = []
	for mid in _message_node_index:
		if not cache_ids.has(mid):
			removed_ids.append(mid)
	for mid in removed_ids:
		var node: Control = _message_node_index[mid]
		if is_instance_valid(node):
			node.queue_free()
		_message_node_index.erase(mid)

	# UPDATE: existing nodes with fresh data
	for msg in messages:
		var mid: String = msg.get("id", "")
		if _message_node_index.has(mid):
			var node: Control = _message_node_index[mid]
			if is_instance_valid(node) and node.has_method("update_data"):
				node.update_data(msg)

	# APPEND: new messages at the end that aren't in the index
	var appended_nodes: Array = []
	for i in range(messages.size() - 1, -1, -1):
		var msg: Dictionary = messages[i]
		var mid: String = msg.get("id", "")
		if _message_node_index.has(mid):
			break  # Hit an existing message, stop looking
		# Determine cozy vs collapsed
		var author: Dictionary = msg.get("author", {})
		var author_id: String = author.get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var prev_author_id: String = ""
		if i > 0:
			prev_author_id = messages[i - 1].get("author", {}).get("id", "")
		var use_collapsed: bool = (author_id == prev_author_id) and not has_reply and i > 0
		var node: HBoxContainer
		if use_collapsed:
			node = CollapsedMessageScene.instantiate()
		else:
			node = CozyMessageScene.instantiate()
		appended_nodes.append({"node": node, "msg": msg, "id": mid})

	# Add appended nodes in correct order (we iterated in reverse)
	appended_nodes.reverse()
	for entry in appended_nodes:
		var node: HBoxContainer = entry["node"]
		var msg: Dictionary = entry["msg"]
		message_list.add_child(node)
		node.setup(msg)
		node.mouse_entered.connect(_on_msg_hovered.bind(node))
		node.mouse_exited.connect(_on_msg_unhovered.bind(node))
		if node.has_signal("context_menu_requested"):
			node.context_menu_requested.connect(_on_context_menu_requested)
		_message_node_index[entry["id"]] = node

	# Handle layout fixup after deletion: if first message became collapsed
	# but now has no predecessor with same author, promote to cozy
	if not removed_ids.is_empty():
		_fixup_layouts_after_delete(messages)

	# If messages were inserted in the middle (not just appended), fall back
	var node_order_valid := true
	var msg_children: Array = []
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		msg_children.append(child)
	if msg_children.size() != messages.size():
		node_order_valid = false
	else:
		for i in messages.size():
			var mid: String = messages[i].get("id", "")
			var child_data: Dictionary = msg_children[i].get("_message_data")
			if child_data == null or child_data.get("id", "") != mid:
				node_order_valid = false
				break
	if not node_order_valid:
		_load_messages(channel_id)
		return

	var new_count := messages.size()
	var old_count := _old_message_count
	_old_message_count = new_count
	older_btn.visible = messages.size() >= Client.MESSAGE_CAP

	# Animate new appended messages
	if not Config.get_reduced_motion() and appended_nodes.size() > 0 and old_count > 0:
		for entry in appended_nodes:
			var node: Control = entry["node"]
			node.modulate.a = 0.0
			var msg_tween := create_tween()
			msg_tween.tween_property(node, "modulate:a", 1.0, 0.15) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# Auto-scroll for new messages
	if auto_scroll and appended_nodes.size() > 0:
		await get_tree().process_frame
		_scroll_to_bottom_animated()

func _fixup_layouts_after_delete(messages: Array) -> void:
	for i in messages.size():
		var msg: Dictionary = messages[i]
		var mid: String = msg.get("id", "")
		if not _message_node_index.has(mid):
			continue
		var node: Control = _message_node_index[mid]
		if not is_instance_valid(node):
			continue
		var author_id: String = msg.get("author", {}).get("id", "")
		var has_reply: bool = msg.get("reply_to", "") != ""
		var prev_author_id: String = ""
		if i > 0:
			prev_author_id = messages[i - 1].get("author", {}).get("id", "")
		var should_be_collapsed: bool = (author_id == prev_author_id) and not has_reply and i > 0
		var is_currently_collapsed: bool = node.get("is_collapsed") == true
		if should_be_collapsed != is_currently_collapsed:
			# Layout mismatch — replace node
			var idx := node.get_index()
			node.queue_free()
			var new_node: HBoxContainer
			if should_be_collapsed:
				new_node = CollapsedMessageScene.instantiate()
			else:
				new_node = CozyMessageScene.instantiate()
			message_list.add_child(new_node)
			message_list.move_child(new_node, idx)
			new_node.setup(msg)
			new_node.mouse_entered.connect(_on_msg_hovered.bind(new_node))
			new_node.mouse_exited.connect(_on_msg_unhovered.bind(new_node))
			if new_node.has_signal("context_menu_requested"):
				new_node.context_menu_requested.connect(_on_context_menu_requested)
			_message_node_index[mid] = new_node

func _on_reactions_updated(channel_id: String, message_id: String) -> void:
	if channel_id != current_channel_id:
		return
	# Targeted update: use index for O(1) lookup
	if _message_node_index.has(message_id):
		var node: Control = _message_node_index[message_id]
		if is_instance_valid(node):
			var mc = node.get("message_content")
			if mc:
				var msg := Client.get_message_by_id(message_id)
				var reactions: Array = msg.get("reactions", [])
				mc.reaction_bar.setup(reactions, channel_id, message_id)
		return
	# Fallback: linear scan if index misses
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		if child.get("_message_data") is Dictionary and child._message_data.get("id", "") == message_id:
			var mc = child.get("message_content")
			if mc:
				var msg := Client.get_message_by_id(message_id)
				var reactions: Array = msg.get("reactions", [])
				mc.reaction_bar.setup(reactions, channel_id, message_id)
			break

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
	var node: Control = _find_message_node(msg_id)
	if node:
		var mc = node.get("message_content")
		if mc:
			mc.enter_edit_mode(msg_id, msg_data.get("content", ""))
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

# --- Shared Context Menu ---

func _on_context_menu_requested(pos: Vector2i, msg_data: Dictionary) -> void:
	_context_menu_data = msg_data
	var author: Dictionary = msg_data.get("author", {})
	var is_own: bool = author.get("id", "") == Client.current_user.get("id", "")
	_context_menu.set_item_disabled(1, not is_own)
	_context_menu.set_item_disabled(2, not is_own)
	var guild_id: String = Client._channel_to_guild.get(
		msg_data.get("channel_id", ""), ""
	)
	var has_reactions: bool = msg_data.get("reactions", []).size() > 0
	var can_manage: bool = Client.has_permission(guild_id, "MANAGE_MESSAGES")
	_context_menu.set_item_disabled(4, not (can_manage and has_reactions))
	_context_menu.position = pos
	_context_menu.popup()

func _on_context_menu_id_pressed(id: int) -> void:
	match id:
		0: # Reply
			AppState.initiate_reply(_context_menu_data.get("id", ""))
		1: # Edit
			var msg_id: String = _context_menu_data.get("id", "")
			AppState.start_editing(msg_id)
			var node: Control = _find_message_node(msg_id)
			if node:
				var mc = node.get("message_content")
				if mc:
					mc.enter_edit_mode(msg_id, _context_menu_data.get("content", ""))
		2: # Delete
			_pending_delete_id = _context_menu_data.get("id", "")
			if not _delete_dialog:
				_delete_dialog = ConfirmationDialog.new()
				_delete_dialog.dialog_text = "Are you sure you want to delete this message?"
				_delete_dialog.confirmed.connect(_on_delete_confirmed)
				add_child(_delete_dialog)
			_delete_dialog.popup_centered()
		3: # Add Reaction
			_open_reaction_picker(_context_menu_data)
		4: # Remove All Reactions
			var cid: String = _context_menu_data.get("channel_id", "")
			var mid: String = _context_menu_data.get("id", "")
			Client.remove_all_reactions(cid, mid)

func _open_reaction_picker(msg_data: Dictionary) -> void:
	if _reaction_picker and is_instance_valid(_reaction_picker):
		_reaction_picker.queue_free()
	_reaction_picker = ReactionPickerScene.instantiate()
	get_tree().root.add_child(_reaction_picker)
	var channel_id: String = msg_data.get("channel_id", "")
	var msg_id: String = msg_data.get("id", "")
	var pos := get_global_mouse_position()
	_reaction_picker.open(channel_id, msg_id, pos)
	_reaction_picker.closed.connect(func():
		_reaction_picker = null
	)

# --- Connection Banner ---

func _guild_for_current_channel() -> String:
	return Client._channel_to_guild.get(current_channel_id, "")

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

func _scroll_to_bottom_animated() -> void:
	var target := int(scroll_container.get_v_scroll_bar().max_value)
	if Config.get_reduced_motion():
		scroll_container.scroll_vertical = target
		return
	var distance := absi(target - scroll_container.scroll_vertical)
	if distance < 50:
		scroll_container.scroll_vertical = target
		return
	if _scroll_tween and _scroll_tween.is_valid():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(scroll_container, "scroll_vertical", target, 0.2) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _get_last_message_child() -> Control:
	var children := message_list.get_children()
	for i in range(children.size() - 1, -1, -1):
		var child: Node = children[i]
		if child != older_btn and child != empty_state and child != loading_label:
			return child as Control
	return null

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

# --- Helpers ---

func _find_message_node(message_id: String) -> Control:
	if _message_node_index.has(message_id):
		var node: Control = _message_node_index[message_id]
		if is_instance_valid(node):
			return node
	# Fallback: linear scan
	for child in message_list.get_children():
		if child == older_btn or child == empty_state or child == loading_label:
			continue
		if child.get("_message_data") is Dictionary and child._message_data.get("id", "") == message_id:
			return child as Control
	return null
