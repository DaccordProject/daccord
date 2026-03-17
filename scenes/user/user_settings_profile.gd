class_name UserSettingsProfile
extends RefCounted

## Builds and manages the Profile settings page within UserSettings.

const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _profile_avatar: ColorRect
var _profile_dn_input: LineEdit
var _profile_bio_input: TextEdit
var _profile_accent_picker: ColorPickerButton
var _profile_error: Label
var _profile_save_btn: Button
var _pending_avatar_data_uri: String = ""
var _profile_avatar_removed: bool = false
var _settings_panel: Control # parent panel for adding file dialog
var _accord_client: AccordClient = null
var _user_override: Dictionary = {}

func build(
	page_vbox: VBoxContainer,
	section_label_fn: Callable,
	error_label_fn: Callable,
	settings_panel: Control,
	accord_client: AccordClient = null,
	user: Dictionary = {},
) -> void:
	_settings_panel = settings_panel
	_accord_client = accord_client
	_user_override = user
	if user.is_empty():
		user = Client.current_user

	# Avatar
	_profile_avatar = AvatarScene.instantiate()
	_profile_avatar.avatar_size = 80
	_profile_avatar.show_letter = true
	_profile_avatar.letter_font_size = 28
	_profile_avatar.custom_minimum_size = Vector2(80, 80)
	_profile_avatar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_profile_avatar.setup_from_dict(user)
	page_vbox.add_child(_profile_avatar)

	var avatar_btns := HBoxContainer.new()
	avatar_btns.add_theme_constant_override("separation", 8)
	page_vbox.add_child(avatar_btns)

	var upload_btn := SettingsBase.create_secondary_button(tr("Upload Avatar"))
	upload_btn.pressed.connect(_on_avatar_upload)
	avatar_btns.add_child(upload_btn)

	var remove_btn := SettingsBase.create_secondary_button(tr("Remove"))
	remove_btn.pressed.connect(_on_avatar_remove)
	avatar_btns.add_child(remove_btn)

	# Display name
	page_vbox.add_child(section_label_fn.call(tr("DISPLAY NAME")))
	_profile_dn_input = LineEdit.new()
	_profile_dn_input.text = user.get("display_name", "")
	page_vbox.add_child(_profile_dn_input)

	# Bio
	page_vbox.add_child(section_label_fn.call(tr("ABOUT ME")))
	_profile_bio_input = TextEdit.new()
	_profile_bio_input.custom_minimum_size = Vector2(0, 80)
	_profile_bio_input.text = user.get("bio", "")
	page_vbox.add_child(_profile_bio_input)

	# Accent color
	var accent_row := HBoxContainer.new()
	accent_row.add_theme_constant_override("separation", 8)
	page_vbox.add_child(accent_row)

	var accent_lbl := Label.new()
	accent_lbl.text = tr("Accent Color")
	accent_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accent_row.add_child(accent_lbl)

	_profile_accent_picker = ColorPickerButton.new()
	_profile_accent_picker.custom_minimum_size = Vector2(40, 30)
	var accent_int: int = user.get("accent_color", 0)
	_profile_accent_picker.color = Color.hex(accent_int) if accent_int > 0 else Color.BLACK
	accent_row.add_child(_profile_accent_picker)

	var reset_btn := SettingsBase.create_secondary_button(tr("Reset"))
	reset_btn.pressed.connect(func() -> void:
		_profile_accent_picker.color = Color.BLACK
	)
	accent_row.add_child(reset_btn)

	# Error + Save
	_profile_error = error_label_fn.call()
	page_vbox.add_child(_profile_error)

	_profile_save_btn = SettingsBase.create_action_button(tr("Save Changes"))
	_profile_save_btn.pressed.connect(_on_save)
	page_vbox.add_child(_profile_save_btn)

func _on_avatar_upload() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.use_native_dialog = true
	fd.filters = PackedStringArray([
		"*.png ; " + tr("PNG Images"),
		"*.jpg, *.jpeg ; " + tr("JPEG Images"),
		"*.webp ; " + tr("WebP Images"),
	])
	fd.file_selected.connect(func(path: String) -> void:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return
		var bytes := file.get_buffer(file.get_length())
		file.close()
		_pending_avatar_data_uri = AccordCDN.build_data_uri(bytes, path)
		_profile_avatar_removed = false
		var img := Image.new()
		if img.load(path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_profile_avatar._apply_texture(tex)
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	_settings_panel.add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _on_avatar_remove() -> void:
	_profile_avatar_removed = true
	_pending_avatar_data_uri = ""
	_profile_avatar.letter_label.visible = true
	if _profile_avatar._texture_rect != null:
		_profile_avatar._texture_rect.queue_free()
		_profile_avatar._texture_rect = null

func _on_save() -> void:
	_profile_error.visible = false
	var user: Dictionary = _user_override if not _user_override.is_empty() else Client.current_user
	var data := {}
	var new_dn: String = _profile_dn_input.text.strip_edges()
	if new_dn != user.get("display_name", ""):
		data["display_name"] = new_dn
	var new_bio: String = _profile_bio_input.text.strip_edges()
	if new_bio != user.get("bio", ""):
		data["bio"] = new_bio
	var accent_int: int = _profile_accent_picker.color.to_rgba32()
	var orig_accent: int = user.get("accent_color", 0)
	if _profile_accent_picker.color == Color.BLACK:
		if orig_accent != 0:
			data["accent_color"] = null
	elif accent_int != orig_accent:
		data["accent_color"] = accent_int
	if not _pending_avatar_data_uri.is_empty():
		data["avatar"] = _pending_avatar_data_uri
	elif _profile_avatar_removed:
		data["avatar"] = ""
	if data.is_empty():
		return
	_profile_save_btn.disabled = true
	var ok: bool
	if _accord_client != null:
		var result: RestResult = await _accord_client.users.update_me(data)
		ok = result.ok
	else:
		ok = await Client.update_profile(data)
	_profile_save_btn.disabled = false
	if not ok:
		_profile_error.text = tr("Failed to save profile")
		_profile_error.visible = true
