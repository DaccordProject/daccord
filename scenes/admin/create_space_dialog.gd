extends ColorRect

## Dialog for creating a new space on the instance.
## Instantiate via `var d = CreateSpaceDialog.new(); root.add_child(d)`.

const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _name_input: LineEdit
var _desc_input: TextEdit
var _icon_preview: ColorRect
var _pending_icon_data_uri: String = ""
var _create_btn: Button
var _error_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0, 0, 0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 400)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.188, 0.196, 0.212)
	panel_style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Create Space"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.flat = true
	close_btn.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	close_btn.add_theme_color_override(
		"font_hover_color", Color.WHITE
	)
	close_btn.pressed.connect(queue_free)
	header.add_child(close_btn)
	vbox.add_child(header)

	# Icon upload
	var icon_section := Label.new()
	icon_section.text = "SPACE ICON"
	icon_section.add_theme_font_size_override("font_size", 11)
	icon_section.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(icon_section)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 12)
	_icon_preview = AvatarScene.instantiate()
	_icon_preview.avatar_size = 48
	_icon_preview.show_letter = true
	_icon_preview.letter_font_size = 18
	_icon_preview.custom_minimum_size = Vector2(48, 48)
	icon_row.add_child(_icon_preview)
	var upload_btn := SettingsBase.create_secondary_button(
		"Upload Icon"
	)
	upload_btn.pressed.connect(_on_icon_upload)
	icon_row.add_child(upload_btn)
	vbox.add_child(icon_row)

	# Name
	var name_label := Label.new()
	name_label.text = "SPACE NAME"
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(name_label)
	_name_input = LineEdit.new()
	_name_input.placeholder_text = "My Space"
	vbox.add_child(_name_input)

	# Description
	var desc_label := Label.new()
	desc_label.text = "DESCRIPTION (optional)"
	desc_label.add_theme_font_size_override("font_size", 11)
	desc_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(desc_label)
	_desc_input = TextEdit.new()
	_desc_input.custom_minimum_size = Vector2(0, 60)
	_desc_input.placeholder_text = "What is this space about?"
	vbox.add_child(_desc_input)

	# Error
	_error_label = Label.new()
	_error_label.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.visible = false
	vbox.add_child(_error_label)

	# Create button
	_create_btn = SettingsBase.create_action_button("Create")
	_create_btn.pressed.connect(_on_create)
	vbox.add_child(_create_btn)

func _on_icon_upload() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
	])
	fd.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return
		var bytes := file.get_buffer(file.get_length())
		file.close()
		_pending_icon_data_uri = AccordCDN.build_data_uri(
			bytes, path
		)
		var img := Image.new()
		if img.load(path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_icon_preview._apply_texture(tex)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _on_create() -> void:
	var sname: String = _name_input.text.strip_edges()
	if sname.is_empty():
		_error_label.text = "Space name is required."
		_error_label.visible = true
		return

	_create_btn.disabled = true
	_create_btn.text = "Creating..."
	_error_label.visible = false

	var data: Dictionary = {"name": sname}
	var desc: String = _desc_input.text.strip_edges()
	if not desc.is_empty():
		data["description"] = desc
	if not _pending_icon_data_uri.is_empty():
		data["icon"] = _pending_icon_data_uri

	var result: RestResult = await Client.admin.create_space(data)

	_create_btn.disabled = false
	_create_btn.text = "Create"

	if result == null or not result.ok:
		var msg := "Failed to create space"
		if result != null and result.error:
			msg = result.error.message
		_error_label.text = msg
		_error_label.visible = true
	else:
		queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		queue_free()
		get_viewport().set_input_as_handled()
