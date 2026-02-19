extends ColorRect

## Modal dialog for editing the current user's profile.
## Pattern B overlay (same as AddServerDialog/SpaceSettingsDialog).

var _dirty: bool = false
var _original_data: Dictionary = {}

var _panel: PanelContainer
var _avatar_preview: ColorRect
var _display_name_input: LineEdit
var _bio_input: TextEdit
var _accent_color_picker: ColorPickerButton
var _accent_reset_btn: Button
var _error_label: Label
var _save_btn: Button
var _close_btn: Button
var _avatar_upload_btn: Button
var _avatar_remove_btn: Button
var _pending_avatar_base64: String = ""
var _avatar_removed: bool = false
var _file_dialog: FileDialog

func _ready() -> void:
	# Full-screen overlay
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.0, 0.0, 0.0, 0.6)
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_backdrop_input)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.188, 0.196, 0.212)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 20.0
	style.content_margin_bottom = 20.0
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size = Vector2(420, 0)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Edit Profile"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Avatar section
	var avatar_row := HBoxContainer.new()
	avatar_row.add_theme_constant_override("separation", 12)
	vbox.add_child(avatar_row)

	var AvatarScene: PackedScene = preload(
		"res://scenes/common/avatar.tscn"
	)
	_avatar_preview = AvatarScene.instantiate()
	_avatar_preview.avatar_size = 80
	_avatar_preview.show_letter = true
	_avatar_preview.letter_font_size = 28
	_avatar_preview.custom_minimum_size = Vector2(80, 80)
	avatar_row.add_child(_avatar_preview)

	var avatar_btns := VBoxContainer.new()
	avatar_btns.add_theme_constant_override("separation", 4)
	avatar_row.add_child(avatar_btns)

	_avatar_upload_btn = Button.new()
	_avatar_upload_btn.text = "Upload Avatar"
	_avatar_upload_btn.pressed.connect(_on_avatar_upload)
	avatar_btns.add_child(_avatar_upload_btn)

	_avatar_remove_btn = Button.new()
	_avatar_remove_btn.text = "Remove Avatar"
	_avatar_remove_btn.pressed.connect(_on_avatar_remove)
	avatar_btns.add_child(_avatar_remove_btn)

	# Display Name
	var dn_label := Label.new()
	dn_label.text = "DISPLAY NAME"
	dn_label.add_theme_font_size_override("font_size", 11)
	dn_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(dn_label)

	_display_name_input = LineEdit.new()
	_display_name_input.placeholder_text = "Display name"
	_display_name_input.text_changed.connect(_on_field_changed)
	vbox.add_child(_display_name_input)

	# Bio
	var bio_label := Label.new()
	bio_label.text = "ABOUT ME"
	bio_label.add_theme_font_size_override("font_size", 11)
	bio_label.add_theme_color_override(
		"font_color", Color(0.58, 0.608, 0.643)
	)
	vbox.add_child(bio_label)

	_bio_input = TextEdit.new()
	_bio_input.custom_minimum_size = Vector2(0, 80)
	_bio_input.placeholder_text = "Tell others about yourself"
	_bio_input.text_changed.connect(_on_field_changed)
	vbox.add_child(_bio_input)

	# Accent Color
	var accent_row := HBoxContainer.new()
	accent_row.add_theme_constant_override("separation", 8)
	vbox.add_child(accent_row)

	var accent_label := Label.new()
	accent_label.text = "Accent Color"
	accent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accent_row.add_child(accent_label)

	_accent_color_picker = ColorPickerButton.new()
	_accent_color_picker.custom_minimum_size = Vector2(40, 30)
	_accent_color_picker.color_changed.connect(
		func(_c: Color) -> void: _mark_dirty()
	)
	accent_row.add_child(_accent_color_picker)

	_accent_reset_btn = Button.new()
	_accent_reset_btn.text = "Reset"
	_accent_reset_btn.pressed.connect(func() -> void:
		_accent_color_picker.color = Color.BLACK
		_mark_dirty()
	)
	accent_row.add_child(_accent_reset_btn)

	# Error label
	_error_label = Label.new()
	_error_label.add_theme_color_override(
		"font_color", Color(0.929, 0.259, 0.271)
	)
	_error_label.add_theme_font_size_override("font_size", 13)
	_error_label.visible = false
	vbox.add_child(_error_label)

	# Button row
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	vbox.add_child(btn_row)

	_close_btn = Button.new()
	_close_btn.text = "Cancel"
	_close_btn.pressed.connect(_on_close)
	btn_row.add_child(_close_btn)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.pressed.connect(_on_save)
	btn_row.add_child(_save_btn)

	# Populate with current data
	_load_current_user()

func _load_current_user() -> void:
	var user: Dictionary = Client.current_user
	_original_data = user.duplicate()
	_display_name_input.text = user.get("display_name", "")
	_bio_input.text = user.get("bio", "")
	var accent: int = user.get("accent_color", 0)
	if accent > 0:
		_accent_color_picker.color = Color.hex(accent)
	else:
		_accent_color_picker.color = Color.BLACK
	# Setup avatar preview
	_avatar_preview.set_avatar_color(
		user.get("color", Color(0.345, 0.396, 0.949))
	)
	var dn: String = user.get("display_name", "")
	if dn.length() > 0:
		_avatar_preview.set_letter(dn[0].to_upper())
	var avatar_url = user.get("avatar", null)
	if avatar_url is String and not avatar_url.is_empty():
		_avatar_preview.set_avatar_url(avatar_url)
	_dirty = false

func _on_field_changed(_text = null) -> void:
	_mark_dirty()

func _mark_dirty() -> void:
	_dirty = true

func _on_avatar_upload() -> void:
	if _file_dialog != null and is_instance_valid(_file_dialog):
		_file_dialog.queue_free()
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray([
		"*.png ; PNG Images",
		"*.jpg, *.jpeg ; JPEG Images",
		"*.webp ; WebP Images",
	])
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.canceled.connect(_file_dialog.queue_free)
	add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(600, 400))

func _on_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_show_error("Could not read file")
		return
	var bytes := file.get_buffer(file.get_length())
	file.close()
	_pending_avatar_base64 = Marshalls.raw_to_base64(bytes)
	_avatar_removed = false
	# Show preview of selected image
	var img := Image.new()
	var err := img.load(path)
	if err == OK:
		var tex := ImageTexture.create_from_image(img)
		_avatar_preview._apply_texture(tex)
	_mark_dirty()
	if _file_dialog and is_instance_valid(_file_dialog):
		_file_dialog.queue_free()

func _on_avatar_remove() -> void:
	_avatar_removed = true
	_pending_avatar_base64 = ""
	_avatar_preview.letter_label.visible = true
	if _avatar_preview._texture_rect != null:
		_avatar_preview._texture_rect.queue_free()
		_avatar_preview._texture_rect = null
	_mark_dirty()

func _on_save() -> void:
	_error_label.visible = false
	var data := {}
	var new_dn: String = _display_name_input.text.strip_edges()
	if new_dn != _original_data.get("display_name", ""):
		data["display_name"] = new_dn
	var new_bio: String = _bio_input.text.strip_edges()
	if new_bio != _original_data.get("bio", ""):
		data["bio"] = new_bio
	var accent_int: int = _accent_color_picker.color.to_rgba32()
	var orig_accent: int = _original_data.get("accent_color", 0)
	if _accent_color_picker.color == Color.BLACK:
		if orig_accent != 0:
			data["accent_color"] = null
	elif accent_int != orig_accent:
		data["accent_color"] = accent_int
	if not _pending_avatar_base64.is_empty():
		data["avatar"] = _pending_avatar_base64
	elif _avatar_removed:
		data["avatar"] = null
	if data.is_empty():
		_close()
		return
	_save_btn.disabled = true
	var ok: bool = await Client.update_profile(data)
	_save_btn.disabled = false
	if ok:
		_close()
	else:
		_show_error("Failed to save profile changes")

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_on_close()

func _on_close() -> void:
	if _dirty:
		var confirm := ConfirmationDialog.new()
		confirm.dialog_text = "You have unsaved changes. Discard?"
		confirm.ok_button_text = "Discard"
		confirm.confirmed.connect(func() -> void:
			confirm.queue_free()
			_close()
		)
		confirm.canceled.connect(confirm.queue_free)
		add_child(confirm)
		confirm.popup_centered()
	else:
		_close()

func _close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_close()
