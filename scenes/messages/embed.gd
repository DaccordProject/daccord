extends PanelContainer

const MAX_IMAGE_WIDTH := 400
const MAX_IMAGE_HEIGHT := 300
const MAX_THUMBNAIL_SIZE := 80
const MAX_FIELDS_PER_ROW := 3

@onready var content_row: HBoxContainer = $ContentRow
@onready var vbox: VBoxContainer = $ContentRow/VBox
@onready var author_row: HBoxContainer = $ContentRow/VBox/AuthorRow
@onready var author_icon: TextureRect = $ContentRow/VBox/AuthorRow/AuthorIcon
@onready var author_name_rtl: RichTextLabel = $ContentRow/VBox/AuthorRow/AuthorName
@onready var title_rtl: RichTextLabel = $ContentRow/VBox/Title
@onready var description_rtl: RichTextLabel = $ContentRow/VBox/Description
@onready var fields_container: VBoxContainer = $ContentRow/VBox/FieldsContainer
@onready var image_rect: TextureRect = $ContentRow/VBox/Image
@onready var footer_label: Label = $ContentRow/VBox/Footer
@onready var thumbnail_rect: TextureRect = $ContentRow/Thumbnail

func _ready() -> void:
	title_rtl.add_theme_font_size_override("font_size", 14)
	title_rtl.meta_clicked.connect(_on_meta_clicked)
	author_name_rtl.add_theme_font_size_override("font_size", 12)
	author_name_rtl.meta_clicked.connect(_on_meta_clicked)
	footer_label.add_theme_font_size_override("font_size", 11)
	footer_label.add_theme_color_override("font_color", Color(0.58, 0.608, 0.643))

func setup(data: Dictionary) -> void:
	if data.is_empty():
		visible = false
		return

	visible = true
	var embed_type: String = data.get("type", "rich")

	# --- Author ---
	var author_data: Dictionary = data.get("author", {})
	if not author_data.is_empty() and not str(author_data.get("name", "")).is_empty():
		author_row.visible = true
		var aname: String = author_data.get("name", "")
		var aurl: String = author_data.get("url", "")
		if not aurl.is_empty():
			author_name_rtl.text = (
				"[url=%s][color=#ffffff]%s[/color][/url]" % [aurl, aname]
			)
		else:
			author_name_rtl.text = "[color=#ffffff]%s[/color]" % aname
		var icon_url: String = author_data.get("icon_url", "")
		if not icon_url.is_empty():
			_load_remote_image(icon_url, author_icon, 24, 24)
		else:
			author_icon.visible = false
	else:
		author_row.visible = false

	# --- Title ---
	var title_text: String = data.get("title", "")
	var embed_url: String = data.get("url", "")
	if not title_text.is_empty():
		title_rtl.visible = true
		if not embed_url.is_empty():
			title_rtl.text = (
				"[url=%s][color=#00aaff]%s[/color][/url]" % [embed_url, title_text]
			)
		else:
			title_rtl.text = "[color=#ffffff]%s[/color]" % title_text
	else:
		title_rtl.visible = false

	# --- Description ---
	var desc: String = data.get("description", "")
	if not desc.is_empty():
		description_rtl.visible = true
		description_rtl.text = ClientModels.markdown_to_bbcode(desc)
	else:
		description_rtl.visible = false

	# --- Fields ---
	var fields_arr: Array = data.get("fields", [])
	if fields_arr.size() > 0:
		fields_container.visible = true
		_render_fields(fields_arr)
	else:
		fields_container.visible = false

	# --- Image ---
	var image_url: String = data.get("image", "")
	if not image_url.is_empty():
		if embed_type == "image":
			# Image-only embed: hide text, show just image
			title_rtl.visible = false
			description_rtl.visible = false
			footer_label.visible = false
		image_rect.visible = true
		_load_remote_image(image_url, image_rect, MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT)
	else:
		image_rect.visible = false

	# --- Thumbnail ---
	var thumb_url: String = data.get("thumbnail", "")
	if not thumb_url.is_empty():
		thumbnail_rect.visible = true
		_load_remote_image(thumb_url, thumbnail_rect, MAX_THUMBNAIL_SIZE, MAX_THUMBNAIL_SIZE)
	else:
		thumbnail_rect.visible = false

	# --- Footer ---
	footer_label.text = data.get("footer", "")
	footer_label.visible = not footer_label.text.is_empty()

	# --- Border color ---
	var embed_color: Color = data.get("color", Color(0.345, 0.396, 0.949))
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.border_color = embed_color
	add_theme_stylebox_override("panel", style)

	# --- Video type: show thumbnail with play overlay ---
	if embed_type == "video" and not thumb_url.is_empty() and image_url.is_empty():
		image_rect.visible = true
		_load_remote_image(thumb_url, image_rect, MAX_IMAGE_WIDTH, MAX_IMAGE_HEIGHT)
		# Add play button overlay after image loads
		var play_label := Label.new()
		play_label.text = "\u25b6"
		play_label.add_theme_font_size_override("font_size", 48)
		play_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		play_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		play_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		play_label.set_anchors_preset(Control.PRESET_CENTER)
		play_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		image_rect.add_child(play_label)
		if not embed_url.is_empty():
			image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
			image_rect.gui_input.connect(func(event: InputEvent) -> void:
				if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
					OS.shell_open(embed_url)
			)

func _render_fields(fields_arr: Array) -> void:
	# Clear existing field nodes
	for child in fields_container.get_children():
		child.queue_free()

	var i := 0
	while i < fields_arr.size():
		var field: Dictionary = fields_arr[i]
		var is_inline: bool = field.get("inline", false)

		if is_inline:
			# Group consecutive inline fields into an HBoxContainer (max 3 per row)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 12)
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			while i < fields_arr.size() and fields_arr[i].get("inline", false):
				var f: Dictionary = fields_arr[i]
				var cell := _create_field_cell(f)
				cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(cell)
				i += 1
				if row.get_child_count() >= MAX_FIELDS_PER_ROW:
					break
			fields_container.add_child(row)
		else:
			var cell := _create_field_cell(field)
			fields_container.add_child(cell)
			i += 1

func _create_field_cell(field: Dictionary) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.text = field.get("name", "")
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_child(name_label)

	var value_rtl := RichTextLabel.new()
	value_rtl.bbcode_enabled = true
	value_rtl.fit_content = true
	value_rtl.scroll_active = false
	value_rtl.text = ClientModels.markdown_to_bbcode(field.get("value", ""))
	value_rtl.add_theme_font_size_override("normal_font_size", 12)
	value_rtl.meta_clicked.connect(_on_meta_clicked)
	cell.add_child(value_rtl)

	return cell

func _load_remote_image(
	url: String, target: TextureRect, max_w: int, max_h: int,
) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url)
	if err != OK:
		http.queue_free()
		return
	var response: Array = await http.request_completed
	http.queue_free()
	if not is_instance_valid(target):
		return
	var result: int = response[0]
	var response_code: int = response[1]
	var body: PackedByteArray = response[3]
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		return
	var image := Image.new()
	var load_err := image.load_png_from_buffer(body)
	if load_err != OK:
		load_err = image.load_jpg_from_buffer(body)
	if load_err != OK:
		load_err = image.load_webp_from_buffer(body)
	if load_err != OK:
		return
	if image.get_width() > max_w or image.get_height() > max_h:
		var scale_x: float = float(max_w) / image.get_width()
		var scale_y: float = float(max_h) / image.get_height()
		var scale_factor: float = minf(scale_x, scale_y)
		image.resize(
			int(image.get_width() * scale_factor),
			int(image.get_height() * scale_factor),
		)
	var texture := ImageTexture.create_from_image(image)
	if is_instance_valid(target):
		target.texture = texture

func _on_meta_clicked(meta: Variant) -> void:
	var meta_str := str(meta)
	if meta_str.begins_with("http://") or meta_str.begins_with("https://"):
		OS.shell_open(meta_str)
