extends PanelContainer

const EmojiPickerScene := preload("res://scenes/messages/composer/emoji_picker.tscn")
const MAX_FILE_SIZE := 25 * 1024 * 1024 # 25 MB

var _last_typing_time: int = 0
var _emoji_picker: PanelContainer = null
var _saved_placeholder: String = ""
var _pending_files: Array = [] # Array of {filename, content, content_type, size}
var _file_dialog: FileDialog = null

@onready var upload_button: Button = $VBox/HBox/UploadButton
@onready var text_input: TextEdit = $VBox/HBox/TextInput
@onready var emoji_button: Button = $VBox/HBox/EmojiButton
@onready var send_button: Button = $VBox/HBox/SendButton
@onready var reply_bar: HBoxContainer = $VBox/ReplyBar
@onready var reply_label: Label = $VBox/ReplyBar/ReplyLabel
@onready var cancel_reply_button: Button = $VBox/ReplyBar/CancelReplyButton
@onready var error_label: Label = $VBox/ErrorLabel
@onready var attachment_bar: HBoxContainer = $VBox/AttachmentBar

func _ready() -> void:
	send_button.pressed.connect(_on_send)
	upload_button.pressed.connect(_on_upload_button)
	emoji_button.pressed.connect(_on_emoji_button)
	text_input.gui_input.connect(_on_text_input)
	text_input.text_changed.connect(_on_text_changed)
	cancel_reply_button.pressed.connect(_on_cancel_reply)
	AppState.reply_initiated.connect(_on_reply_initiated)
	AppState.reply_cancelled.connect(_on_reply_cancelled)
	AppState.message_send_failed.connect(_on_message_send_failed)
	AppState.server_disconnected.connect(func(_gid, _c, _r): update_enabled_state())
	AppState.server_reconnected.connect(func(_gid): update_enabled_state())
	AppState.server_synced.connect(func(_gid): update_enabled_state())
	AppState.server_connection_failed.connect(func(_gid, _r): update_enabled_state())
	AppState.imposter_mode_changed.connect(func(_a): update_enabled_state())
	AppState.channel_selected.connect(_on_channel_selected_restore_draft)
	# Style reply bar
	reply_label.add_theme_font_size_override("font_size", 12)
	reply_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func set_channel_name(channel_name: String) -> void:
	text_input.placeholder_text = "Message #" + channel_name

func _on_send() -> void:
	var text := text_input.text.strip_edges()
	if text.is_empty() and _pending_files.is_empty():
		return
	# Transfer pending files to AppState before emitting signal
	AppState.pending_attachments = _pending_files.duplicate()
	_pending_files.clear()
	_update_attachment_bar()
	# Check if we're queueing (disconnected but can queue)
	var guild_id: String = Client._channel_to_guild.get(
		AppState.current_channel_id, ""
	)
	var is_queuing := false
	if not guild_id.is_empty() and not Client.is_guild_connected(guild_id):
		var status: String = Client.get_guild_connection_status(guild_id)
		is_queuing = status in ["disconnected", "reconnecting"]
	AppState.send_message(text)
	text_input.text = ""
	if AppState.replying_to_message_id != "":
		AppState.cancel_reply()
	# Show queue confirmation
	if is_queuing:
		error_label.add_theme_color_override(
			"font_color", Color(0.58, 0.608, 0.643)
		)
		error_label.text = "Message queued \u2014 will send when reconnected"
		error_label.visible = true

func _on_text_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.shift_pressed:
			_on_send()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and event.shift_pressed:
			text_input.insert_text_at_caret("\n")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP and text_input.text.strip_edges().is_empty():
			_edit_last_own_message()
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
	# Warn if typing @everyone without permission
	_check_everyone_permission()

func _check_everyone_permission() -> void:
	var text := text_input.text
	if text.find("@everyone") == -1 and text.find("@here") == -1:
		if error_label.text.begins_with("You don't have"):
			error_label.visible = false
		return
	var guild_id: String = Client._channel_to_guild.get(
		AppState.current_channel_id, ""
	)
	if guild_id.is_empty():
		return
	if not Client.has_permission(guild_id, AccordPermission.MENTION_EVERYONE):
		error_label.text = "You don't have permission to mention @everyone"
		error_label.visible = true
	else:
		if error_label.text.begins_with("You don't have"):
			error_label.visible = false

func _edit_last_own_message() -> void:
	var my_id: String = Client.current_user.get("id", "")
	if my_id.is_empty():
		return
	var messages := Client.get_messages_for_channel(AppState.current_channel_id)
	for i in range(messages.size() - 1, -1, -1):
		var msg: Dictionary = messages[i]
		var author: Dictionary = msg.get("author", {})
		if author.get("id", "") == my_id:
			AppState.start_editing(msg.get("id", ""))
			AppState.edit_requested.emit(msg.get("id", ""))
			return

func _on_cancel_reply() -> void:
	AppState.cancel_reply()

# --- Upload ---

func _on_upload_button() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.title = "Select files to attach"
		_file_dialog.files_selected.connect(_on_files_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(600, 400))

func _on_files_selected(paths: PackedStringArray) -> void:
	for path in paths:
		_add_file_from_path(path)

func _add_file_from_path(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("[Composer] Failed to open file: ", path)
		return
	var content := file.get_buffer(file.get_length())
	file.close()

	if content.size() > MAX_FILE_SIZE:
		error_label.text = "File too large (max 25 MB): " + path.get_file()
		error_label.visible = true
		return

	var filename := path.get_file()
	var content_type := _guess_content_type(filename)
	_pending_files.append({
		"filename": filename,
		"content": content,
		"content_type": content_type,
		"size": content.size(),
	})
	_update_attachment_bar()

func _update_attachment_bar() -> void:
	# Clear existing children
	for child in attachment_bar.get_children():
		child.queue_free()
	attachment_bar.visible = not _pending_files.is_empty()
	for i in _pending_files.size():
		var file_info: Dictionary = _pending_files[i]
		var label := Label.new()
		label.text = file_info["filename"] + " (" + _format_file_size(file_info["size"]) + ")"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
		var remove_btn := Button.new()
		remove_btn.text = "x"
		remove_btn.flat = true
		remove_btn.custom_minimum_size = Vector2(20, 20)
		remove_btn.pressed.connect(_remove_pending_file.bind(i))
		var hbox := HBoxContainer.new()
		hbox.add_child(label)
		hbox.add_child(remove_btn)
		attachment_bar.add_child(hbox)

func _remove_pending_file(index: int) -> void:
	if index >= 0 and index < _pending_files.size():
		_pending_files.remove_at(index)
		_update_attachment_bar()

static func _guess_content_type(filename: String) -> String:
	var ext := filename.get_extension().to_lower()
	match ext:
		"png": return "image/png"
		"jpg", "jpeg": return "image/jpeg"
		"gif": return "image/gif"
		"webp": return "image/webp"
		"svg": return "image/svg+xml"
		"bmp": return "image/bmp"
		"mp4": return "video/mp4"
		"webm": return "video/webm"
		"mp3": return "audio/mpeg"
		"ogg", "oga": return "audio/ogg"
		"wav": return "audio/wav"
		"pdf": return "application/pdf"
		"zip": return "application/zip"
		"txt": return "text/plain"
		"json": return "application/json"
		"md": return "text/markdown"
		_: return "application/octet-stream"

static func _format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	if bytes < 1024 * 1024:
		return str(snappedi(bytes / 1024, 1)) + " KB"
	return "%.1f MB" % (bytes / 1048576.0)

# --- Emoji ---

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
	var insert_text: String
	if emoji_name.begins_with("custom:"):
		# Custom emoji format: "custom:name:id" -> insert ":name:"
		var parts := emoji_name.split(":")
		if parts.size() >= 3:
			insert_text = ":" + parts[1] + ":"
		else:
			return
	else:
		var entry := EmojiData.get_by_name(emoji_name)
		if entry.is_empty():
			return
		insert_text = ":" + emoji_name + ":"
	var col := text_input.get_caret_column()
	var line := text_input.get_caret_line()
	var line_text := text_input.get_line(line)
	var new_text := line_text.substr(0, col) + insert_text + line_text.substr(col)
	text_input.set_line(line, new_text)
	text_input.set_caret_column(col + insert_text.length())
	text_input.grab_focus()
	_emoji_picker.visible = false

# --- Error handling ---

func _on_message_send_failed(channel_id: String, content: String, error: String) -> void:
	if channel_id != AppState.current_channel_id:
		return
	# Restore the failed message text so the user can retry
	if text_input.text.strip_edges().is_empty():
		text_input.text = content
	error_label.text = "Failed to send: %s" % error
	error_label.visible = true

# --- State ---

func update_enabled_state() -> void:
	var guild_id: String = Client._channel_to_guild.get(AppState.current_channel_id, "")
	var connected := Client.is_guild_connected(guild_id) if not guild_id.is_empty() else true

	# Imposter mode: always disable sending (view-only preview)
	if AppState.is_imposter_mode and guild_id == AppState.imposter_guild_id:
		text_input.editable = false
		send_button.disabled = true
		upload_button.disabled = true
		emoji_button.disabled = true
		if _saved_placeholder.is_empty():
			_saved_placeholder = text_input.placeholder_text
		var has_send: bool = AccordPermission.has(
			AppState.imposter_permissions,
			AccordPermission.SEND_MESSAGES
		)
		if not has_send:
			text_input.placeholder_text = (
				"Cannot send \u2014 previewing as %s"
				% AppState.imposter_role_name
			)
		else:
			text_input.placeholder_text = "Preview mode \u2014 sending disabled"
		return

	# Syncing: connected but data not yet refreshed
	var is_syncing := false
	if connected and not guild_id.is_empty():
		is_syncing = Client.is_guild_syncing(guild_id)

	# Check if we can queue messages while disconnected
	var can_queue := false
	if not connected and not guild_id.is_empty():
		var status: String = Client.get_guild_connection_status(guild_id)
		can_queue = status in ["disconnected", "reconnecting"]

	text_input.editable = (connected and not is_syncing) or can_queue
	send_button.disabled = (not connected and not can_queue) or is_syncing
	upload_button.disabled = not connected or is_syncing
	emoji_button.disabled = not connected or is_syncing
	if is_syncing:
		if _saved_placeholder.is_empty():
			_saved_placeholder = text_input.placeholder_text
		text_input.placeholder_text = "Syncing..."
	elif connected:
		if not _saved_placeholder.is_empty():
			text_input.placeholder_text = _saved_placeholder
			_saved_placeholder = ""
		error_label.visible = false
	elif can_queue:
		if _saved_placeholder.is_empty():
			_saved_placeholder = text_input.placeholder_text
		text_input.placeholder_text = "Messages will be queued and sent when reconnected"
	else:
		if _saved_placeholder.is_empty():
			_saved_placeholder = text_input.placeholder_text
		text_input.placeholder_text = "Cannot send messages \u2014 disconnected"

func _on_channel_selected_restore_draft(channel_id: String) -> void:
	var draft: String = Config.get_draft_text(channel_id)
	if not draft.is_empty():
		text_input.text = draft
		text_input.set_caret_column(draft.length())
		Config.clear_draft_text(channel_id)

func _exit_tree() -> void:
	if _emoji_picker and is_instance_valid(_emoji_picker):
		_emoji_picker.queue_free()
