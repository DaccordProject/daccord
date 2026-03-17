extends ModalBase

## Dialog for creating a new space on the instance.
## Instantiate via the .tscn scene file.

var _pending_icon_data_uri: String = ""

@onready var _close_btn: Button = \
	$CenterContainer/Panel/VBox/Header/CloseButton
@onready var _icon_preview = \
	$CenterContainer/Panel/VBox/Content/IconRow/IconPreview
@onready var _upload_btn: Button = \
	$CenterContainer/Panel/VBox/Content/IconRow/UploadButton
@onready var _name_input: LineEdit = \
	$CenterContainer/Panel/VBox/Content/NameInput
@onready var _desc_input: TextEdit = \
	$CenterContainer/Panel/VBox/Content/DescInput
@onready var _error_label: Label = \
	$CenterContainer/Panel/VBox/Content/ErrorLabel
@onready var _create_btn: Button = \
	$CenterContainer/Panel/VBox/Content/CreateButton


func _ready() -> void:
	_bind_modal_nodes($CenterContainer/Panel, 440, 400)
	_close_btn.pressed.connect(_close)
	_upload_btn.pressed.connect(_on_icon_upload)
	_create_btn.pressed.connect(_on_create)

	# Configure avatar preview
	_icon_preview.avatar_size = 48
	_icon_preview.show_letter = true
	_icon_preview.letter_font_size = 18

	# Style buttons
	ThemeManager.style_button(
		_upload_btn, "secondary_button",
		"secondary_button_hover",
		"secondary_button_pressed", 4, [16, 6, 16, 6]
	)
	ThemeManager.style_button(
		_create_btn, "accent", "accent_hover",
		"accent_pressed", 4, [16, 6, 16, 6]
	)
	ThemeManager.apply_font_colors(self)


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
		_error_label.text = tr("Space name is required.")
		_error_label.visible = true
		return

	_error_label.visible = false
	var data: Dictionary = {"name": sname}
	var desc: String = _desc_input.text.strip_edges()
	if not desc.is_empty():
		data["description"] = desc
	if not _pending_icon_data_uri.is_empty():
		data["icon"] = _pending_icon_data_uri

	var result: RestResult = await _with_button_loading(
		_create_btn, tr("Create"),
		func() -> RestResult:
			return await Client.admin.create_space(data)
	)

	if not _show_rest_error(result, tr("Failed to create space")):
		queue_free()
