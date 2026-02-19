extends VBoxContainer

const EmbedScene := preload("res://scenes/messages/embed.tscn")

var _edit_input: TextEdit = null
var _edit_hint_label: Label = null
var _edit_error_label: Label = null
var _edit_error_timer: Timer = null
var _editing_message_id: String = ""
var _spoilers_revealed: bool = false
var _raw_bbcode: String = ""
var _is_system: bool = false

@onready var text_content: RichTextLabel = $TextContent
@onready var embed: PanelContainer = $Embed
@onready var reaction_bar: FlowContainer = $ReactionBar

func _ready() -> void:
	# Allow mouse events to pass through to the parent message node
	# so hover detection works over the entire message area.
	mouse_filter = Control.MOUSE_FILTER_PASS
	text_content.mouse_filter = Control.MOUSE_FILTER_PASS
	text_content.meta_clicked.connect(_on_meta_clicked)

func setup(data: Dictionary) -> void:
	var raw_text: String = data.get("content", "")
	_is_system = data.get("system", false)

	if _is_system:
		text_content.text = "[i][color=#8a8e94]" + raw_text + "[/color][/i]"
	else:
		var bbcode := ClientModels.markdown_to_bbcode(raw_text)
		if data.get("edited", false):
			bbcode += " [font_size=11][color=#8a8e94](edited)[/color][/font_size]"
		_raw_bbcode = bbcode
		text_content.text = bbcode

	# Attachments
	var attachments: Array = data.get("attachments", [])
	for att in attachments:
		var content_type: String = att.get("content_type", "")
		var url: String = att.get("url", "")
		var fname: String = att.get("filename", "file")
		var size_bytes: int = att.get("size", 0)

		# Image attachments: show image
		if content_type.begins_with("image/") and not url.is_empty():
			var max_w: int = att.get("width", 400)
			var max_h: int = att.get("height", 300)
			max_w = mini(max_w, 400)
			max_h = mini(max_h, 300)
			var container := Control.new()
			container.custom_minimum_size = Vector2(max_w, max_h)
			container.mouse_filter = Control.MOUSE_FILTER_PASS
			add_child(container)
			move_child(container, get_child_count() - 2)
			_load_image_attachment(url, container, max_w, max_h)

		# File link for all attachments
		var att_label := RichTextLabel.new()
		att_label.bbcode_enabled = true
		att_label.fit_content = true
		att_label.scroll_active = false
		att_label.mouse_filter = Control.MOUSE_FILTER_PASS
		var size_str := _format_file_size(size_bytes)
		att_label.text = (
			"[color=#00aaff][url=%s]%s[/url][/color]"
			% [url, fname]
			+ " [font_size=11][color=#8a8e94](%s)[/color][/font_size]"
			% size_str
		)
		att_label.meta_clicked.connect(_on_meta_clicked)
		add_child(att_label)
		move_child(att_label, get_child_count() - 2)

	# Embeds -- support multiple
	var embeds_arr: Array = data.get("embeds", [])
	if embeds_arr.size() > 0:
		# Use the static embed node for the first embed
		embed.setup(embeds_arr[0])
		# Create additional embed nodes for the rest
		for i in range(1, embeds_arr.size()):
			var extra_embed: PanelContainer = EmbedScene.instantiate()
			add_child(extra_embed)
			# Position before ReactionBar (last child)
			move_child(extra_embed, get_child_count() - 2)
			extra_embed.setup(embeds_arr[i])
	else:
		# Backward compat: try single embed dict
		var embed_data: Dictionary = data.get("embed", {})
		embed.setup(embed_data)

	var reactions: Array = data.get("reactions", [])
	var ch_id: String = data.get("channel_id", "")
	var msg_id: String = data.get("id", "")
	reaction_bar.setup(reactions, ch_id, msg_id)

func _on_meta_clicked(meta: Variant) -> void:
	var meta_str := str(meta)
	if meta_str == "spoiler":
		_spoilers_revealed = true
		var revealed := _raw_bbcode.replace(
			"[color=#1e1f22]", "[color=#dcddde]"
		)
		text_content.text = revealed
	elif meta_str.begins_with("http://") or meta_str.begins_with("https://"):
		OS.shell_open(meta_str)

func _load_image_attachment(url: String, container: Control, max_w: int, max_h: int) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return
	var response: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(container):
		return
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var image := Image.new()
	# Try common formats
	var load_err := image.load_png_from_buffer(body)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		load_err = image.load_webp_from_buffer(body)
	if load_err != OK:
		return
	# Scale to fit within max dimensions
	if image.get_width() > max_w or image.get_height() > max_h:
		var scale_x: float = float(max_w) / image.get_width()
		var scale_y: float = float(max_h) / image.get_height()
		var scale: float = minf(scale_x, scale_y)
		image.resize(
			int(image.get_width() * scale),
			int(image.get_height() * scale)
		)
	var texture := ImageTexture.create_from_image(image)
	var tex_rect := TextureRect.new()
	tex_rect.texture = texture
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tex_rect.mouse_filter = Control.MOUSE_FILTER_PASS
	container.add_child(tex_rect)
	container.custom_minimum_size = Vector2(image.get_width(), image.get_height())

static func _format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / (1024.0 * 1024.0))

func enter_edit_mode(message_id: String, content: String) -> void:
	_editing_message_id = message_id
	text_content.visible = false
	_edit_input = TextEdit.new()
	_edit_input.text = content
	_edit_input.custom_minimum_size = Vector2(0, 36)
	_edit_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit_input.scroll_fit_content_height = true
	_edit_input.gui_input.connect(_on_edit_input)
	add_child(_edit_input)
	move_child(_edit_input, 0)

	# Keyboard hint label below the TextEdit
	_edit_hint_label = Label.new()
	_edit_hint_label.text = "Enter to save \u00b7 Escape to cancel \u00b7 Shift+Enter for newline"
	_edit_hint_label.add_theme_font_size_override("font_size", 11)
	_edit_hint_label.add_theme_color_override("font_color", Color(0.541, 0.557, 0.580))
	add_child(_edit_hint_label)
	move_child(_edit_hint_label, 1)

	_edit_input.grab_focus()

func is_editing() -> bool:
	return _edit_input != null

func get_edit_text() -> String:
	if _edit_input:
		return _edit_input.text
	return ""

func _exit_edit_mode() -> void:
	if _edit_input:
		_edit_input.queue_free()
		_edit_input = null
	if _edit_hint_label:
		_edit_hint_label.queue_free()
		_edit_hint_label = null
	if _edit_error_label:
		_edit_error_label.queue_free()
		_edit_error_label = null
	if _edit_error_timer:
		_edit_error_timer.queue_free()
		_edit_error_timer = null
	text_content.visible = true
	_editing_message_id = ""

func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and not event.shift_pressed:
			var new_text := _edit_input.text.strip_edges()
			if not new_text.is_empty():
				# Optimistic update: show new content with "(saving...)" indicator
				var bbcode := ClientModels.markdown_to_bbcode(new_text)
				bbcode += " [font_size=11][color=#8a8e94](saving...)[/color][/font_size]"
				text_content.text = bbcode
				AppState.edit_message(_editing_message_id, new_text)
			else:
				show_edit_error("Empty message not saved")
			_exit_edit_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_exit_edit_mode()
			get_viewport().set_input_as_handled()

func show_edit_error(error: String) -> void:
	# Remove previous error label if any
	if _edit_error_label and is_instance_valid(_edit_error_label):
		_edit_error_label.queue_free()
	if _edit_error_timer and is_instance_valid(_edit_error_timer):
		_edit_error_timer.queue_free()

	_edit_error_label = Label.new()
	_edit_error_label.text = error
	_edit_error_label.add_theme_font_size_override("font_size", 11)
	_edit_error_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	add_child(_edit_error_label)
	# Place after TextEdit and hint if editing, otherwise at the top
	if _edit_input:
		var idx: int = (
			_edit_hint_label.get_index() + 1
			if _edit_hint_label
			else _edit_input.get_index() + 1
		)
		move_child(_edit_error_label, idx)
	else:
		move_child(_edit_error_label, 0)

	# Auto-hide after 5 seconds
	_edit_error_timer = Timer.new()
	_edit_error_timer.wait_time = 5.0
	_edit_error_timer.one_shot = true
	_edit_error_timer.timeout.connect(_on_edit_error_timeout)
	add_child(_edit_error_timer)
	_edit_error_timer.start()

func _on_edit_error_timeout() -> void:
	if _edit_error_label and is_instance_valid(_edit_error_label):
		_edit_error_label.queue_free()
		_edit_error_label = null
	if _edit_error_timer and is_instance_valid(_edit_error_timer):
		_edit_error_timer.queue_free()
		_edit_error_timer = null
