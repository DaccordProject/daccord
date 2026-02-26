extends VBoxContainer

const EmbedScene := preload("res://scenes/messages/embed.tscn")

# Static LRU image cache for attachments
const IMAGE_CACHE_CAP := 100
static var _att_image_cache: Dictionary = {}
static var _att_cache_order: Array[String] = []

var _edit_input: TextEdit = null
var _edit_hint_label: Label = null
var _edit_error_label: Label = null
var _edit_error_timer: Timer = null
var _editing_message_id: String = ""
var _original_edit_content: String = ""
var _spoilers_revealed: bool = false
var _raw_bbcode: String = ""
var _is_system: bool = false

@onready var text_content: RichTextLabel = $TextContent
@onready var embed: PanelContainer = $Embed
@onready var reaction_bar: HBoxContainer = $ReactionBar

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
		# Escape BBCode in system messages -- they render as plain italic text
		var safe_text := raw_text.replace("[", "[lb]")
		text_content.text = "[i][color=#8a8e94]" + safe_text + "[/color][/i]"
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
			_add_loading_placeholder(container)
			_load_image_attachment(url, container, max_w, max_h, content_type)

		# Video attachment: placeholder with play button
		elif content_type.begins_with("video/") and not url.is_empty():
			var vid_container := _create_video_placeholder(url, fname)
			add_child(vid_container)
			move_child(vid_container, get_child_count() - 2)

		# Audio attachment: inline player
		elif content_type.begins_with("audio/") and not url.is_empty():
			var audio_container := _create_audio_player(url, fname, content_type)
			add_child(audio_container)
			move_child(audio_container, get_child_count() - 2)

		# File link for all attachments
		var att_label := RichTextLabel.new()
		att_label.bbcode_enabled = true
		att_label.fit_content = true
		att_label.scroll_active = false
		att_label.mouse_filter = Control.MOUSE_FILTER_PASS
		var size_str := _format_file_size(size_bytes)
		var safe_fname := fname.replace("[", "[lb]")
		att_label.text = (
			"[color=#00aaff][url=%s]%s[/url][/color]"
			% [url, safe_fname]
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

func update_content(data: Dictionary) -> void:
	if is_editing():
		return
	var raw_text: String = data.get("content", "")
	_is_system = data.get("system", false)
	if _is_system:
		var safe_text := raw_text.replace("[", "[lb]")
		text_content.text = "[i][color=#8a8e94]" + safe_text + "[/color][/i]"
	else:
		var bbcode := ClientModels.markdown_to_bbcode(raw_text)
		if data.get("edited", false):
			bbcode += " [font_size=11][color=#8a8e94](edited)[/color][/font_size]"
		_raw_bbcode = bbcode
		text_content.text = bbcode

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

func _load_image_attachment(
	url: String, container: Control, max_w: int, max_h: int,
	content_type: String = "",
) -> void:
	# Check static cache first
	if _att_image_cache.has(url):
		_touch_att_cache(url)
		_apply_image_texture(_att_image_cache[url], container, max_w, max_h)
		return
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		_show_image_error(container)
		return
	var response: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(container):
		return
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_image_error(container)
		return
	var image := Image.new()
	# Try common formats
	var load_err := image.load_png_from_buffer(body)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		load_err = image.load_webp_from_buffer(body)
	if load_err != OK:
		load_err = image.load_bmp_from_buffer(body)
	if load_err != OK:
		# GIF: Godot can't decode animated GIFs — show a fallback
		if content_type == "image/gif":
			_show_gif_fallback(container, url)
			return
		_show_image_error(container)
		return
	# Scale to fit within max dimensions
	if image.get_width() > max_w or image.get_height() > max_h:
		var scale_x: float = float(max_w) / image.get_width()
		var scale_y: float = float(max_h) / image.get_height()
		var scale_factor: float = minf(scale_x, scale_y)
		image.resize(
			int(image.get_width() * scale_factor),
			int(image.get_height() * scale_factor)
		)
	var texture := ImageTexture.create_from_image(image)
	# Store in cache
	_att_image_cache[url] = texture
	_touch_att_cache(url)
	_evict_att_cache()
	_apply_image_texture(texture, container, max_w, max_h)

func _apply_image_texture(
	texture: ImageTexture, container: Control, _max_w: int, _max_h: int
) -> void:
	_remove_loading_placeholder(container)
	var tex_rect := TextureRect.new()
	tex_rect.texture = texture
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tex_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	tex_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.add_child(tex_rect)
	var img_w: int = texture.get_width()
	var img_h: int = texture.get_height()
	container.custom_minimum_size = Vector2(img_w, img_h)
	# Click to open lightbox
	tex_rect.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			AppState.image_lightbox_requested.emit(
				"", texture,
			)
	)

static func _touch_att_cache(url: String) -> void:
	var idx := _att_cache_order.find(url)
	if idx != -1:
		_att_cache_order.remove_at(idx)
	_att_cache_order.append(url)

static func _evict_att_cache() -> void:
	while _att_image_cache.size() > IMAGE_CACHE_CAP and _att_cache_order.size() > 0:
		var oldest: String = _att_cache_order[0]
		_att_cache_order.remove_at(0)
		_att_image_cache.erase(oldest)

static func _format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	return "%.1f MB" % (bytes / (1024.0 * 1024.0))

func _add_loading_placeholder(container: Control) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.13, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.name = "LoadingPlaceholder"
	container.add_child(bg)
	var lbl := Label.new()
	lbl.text = "Loading..."
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(lbl)

func _show_image_error(container: Control) -> void:
	_remove_loading_placeholder(container)
	container.custom_minimum_size = Vector2(200, 40)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.12, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)
	var lbl := Label.new()
	lbl.text = "Failed to load image"
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(lbl)

func _remove_loading_placeholder(container: Control) -> void:
	var placeholder: Node = container.get_node_or_null("LoadingPlaceholder")
	if placeholder:
		placeholder.queue_free()

func _show_gif_fallback(container: Control, url: String) -> void:
	_remove_loading_placeholder(container)
	container.custom_minimum_size = Vector2(200, 60)
	var bg := ColorRect.new()
	bg.color = Color(0.15, 0.16, 0.18)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	container.add_child(bg)
	var lbl := Label.new()
	lbl.text = "GIF - Click to view"
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.0, 0.667, 1.0))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(lbl)
	bg.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url)
	)

func _create_video_placeholder(url: String, filename: String) -> Control:
	var container := Control.new()
	container.custom_minimum_size = Vector2(400, 225)
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.1, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bg)
	# Play triangle
	var play_label := Label.new()
	play_label.text = "\u25b6"
	play_label.add_theme_font_size_override("font_size", 48)
	play_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	play_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_label.set_anchors_preset(Control.PRESET_CENTER)
	play_label.position.y -= 10
	play_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(play_label)
	# Filename at bottom
	var name_label := Label.new()
	name_label.text = filename
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -24
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(name_label)
	# Click to open in browser
	container.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url)
	)
	return container

func _create_audio_player(
	url: String, filename: String, _content_type: String,
) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(300, 36)
	# Background
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.16, 0.18)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	panel.add_theme_stylebox_override("panel", style)
	var inner_row := HBoxContainer.new()
	inner_row.add_theme_constant_override("separation", 8)
	panel.add_child(inner_row)
	# Play/Pause button
	var play_btn := Button.new()
	play_btn.text = "\u25b6"
	play_btn.custom_minimum_size = Vector2(32, 32)
	inner_row.add_child(play_btn)
	# Progress slider
	var slider := HSlider.new()
	slider.custom_minimum_size = Vector2(150, 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	inner_row.add_child(slider)
	# Time label
	var time_label := Label.new()
	time_label.text = "0:00"
	time_label.add_theme_font_size_override("font_size", 11)
	time_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	inner_row.add_child(time_label)
	# Filename
	var name_label := Label.new()
	name_label.text = filename
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))
	inner_row.add_child(name_label)
	row.add_child(panel)
	# Audio playback logic
	var stream_player := AudioStreamPlayer.new()
	row.add_child(stream_player)
	var is_loaded := [false]
	var is_playing := [false]
	play_btn.pressed.connect(func() -> void:
		if not is_loaded[0]:
			# Download audio first
			play_btn.text = "..."
			var http := HTTPRequest.new()
			row.add_child(http)
			var err := http.request(url)
			if err != OK:
				http.queue_free()
				play_btn.text = "\u25b6"
				return
			var response: Array = await http.request_completed
			http.queue_free()
			var result: int = response[0]
			var response_code: int = response[1]
			var body: PackedByteArray = response[3]
			if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
				play_btn.text = "\u25b6"
				return
			# Try to load as OGG (most common for web)
			var stream: AudioStream = null
			var ogg_stream = AudioStreamOggVorbis.load_from_buffer(body)
			if ogg_stream != null:
				stream = ogg_stream
			if stream == null:
				var mp3 := AudioStreamMP3.new()
				mp3.data = body
				stream = mp3
			if stream == null:
				play_btn.text = "\u25b6"
				return
			stream_player.stream = stream
			is_loaded[0] = true
		if is_playing[0]:
			stream_player.stop()
			play_btn.text = "\u25b6"
			is_playing[0] = false
		else:
			stream_player.play()
			play_btn.text = "\u23f8"
			is_playing[0] = true
	)
	stream_player.finished.connect(func() -> void:
		play_btn.text = "\u25b6"
		is_playing[0] = false
		slider.value = 0.0
		time_label.text = "0:00"
	)
	return row

func enter_edit_mode(message_id: String, content: String) -> void:
	_editing_message_id = message_id
	_original_edit_content = content
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
	_original_edit_content = ""

func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_ENTER, KEY_KP_ENTER] and not event.shift_pressed:
			var new_text := _edit_input.text.strip_edges()
			if new_text == _original_edit_content:
				# No change — just exit edit mode
				_exit_edit_mode()
			elif not new_text.is_empty():
				# Optimistic update: show new content with "(saving...)" indicator
				var bbcode := ClientModels.markdown_to_bbcode(new_text)
				bbcode += " [font_size=11][color=#8a8e94](saving...)[/color][/font_size]"
				text_content.text = bbcode
				AppState.edit_message(_editing_message_id, new_text)
				_exit_edit_mode()
			else:
				show_edit_error("Empty message not saved")
				_exit_edit_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and event.shift_pressed:
			_edit_input.insert_text_at_caret("\n")
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
