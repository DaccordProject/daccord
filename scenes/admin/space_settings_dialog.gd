extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const AvatarScene := preload("res://scenes/common/avatar.tscn")

var _space_id: String = ""
var _dirty: bool = false
var _pending_icon_data_uri: String = ""
var _icon_removed: bool = false
var _icon_preview: ColorRect

@onready var _vbox: VBoxContainer = $CenterContainer/Panel/VBox
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _name_input: LineEdit = $CenterContainer/Panel/VBox/NameInput
@onready var _desc_input: TextEdit = $CenterContainer/Panel/VBox/DescInput
@onready var _verification_btn: OptionButton = \
	$CenterContainer/Panel/VBox/VerificationRow/VerificationOption
@onready var _notifications_btn: OptionButton = \
	$CenterContainer/Panel/VBox/NotificationsRow/NotificationsOption
@onready var _public_check: CheckBox = $CenterContainer/Panel/VBox/PublicRow/PublicCheck
@onready var _save_btn: Button = $CenterContainer/Panel/VBox/SaveRow/SaveButton
@onready var _delete_btn: Button = $CenterContainer/Panel/VBox/DangerZone/DeleteButton
@onready var _danger_zone: VBoxContainer = $CenterContainer/Panel/VBox/DangerZone
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_save_btn.pressed.connect(_on_save)
	_delete_btn.pressed.connect(_on_delete)
	_verification_btn.add_item("None", 0)
	_verification_btn.add_item("Low", 1)
	_verification_btn.add_item("Medium", 2)
	_verification_btn.add_item("High", 3)
	_notifications_btn.add_item("All Messages", 0)
	_notifications_btn.add_item("Mentions Only", 1)

	# Build icon upload section (inserted after Header)
	var icon_label := Label.new()
	icon_label.text = "SPACE ICON"
	icon_label.add_theme_font_size_override("font_size", 11)
	icon_label.add_theme_color_override(
		"font_color", Color(0.7, 0.7, 0.7)
	)
	_vbox.add_child(icon_label)
	_vbox.move_child(icon_label, 1)

	var icon_row := HBoxContainer.new()
	icon_row.add_theme_constant_override("separation", 12)
	_vbox.add_child(icon_row)
	_vbox.move_child(icon_row, 2)

	_icon_preview = AvatarScene.instantiate()
	_icon_preview.avatar_size = 64
	_icon_preview.show_letter = true
	_icon_preview.letter_font_size = 22
	_icon_preview.custom_minimum_size = Vector2(64, 64)
	icon_row.add_child(_icon_preview)

	var icon_btns := VBoxContainer.new()
	icon_btns.add_theme_constant_override("separation", 4)
	icon_row.add_child(icon_btns)

	var upload_btn := Button.new()
	upload_btn.text = "Upload Icon"
	upload_btn.pressed.connect(_on_icon_upload)
	icon_btns.add_child(upload_btn)

	var remove_btn := Button.new()
	remove_btn.text = "Remove"
	remove_btn.pressed.connect(_on_icon_remove)
	icon_btns.add_child(remove_btn)

	# Track dirty state
	_name_input.text_changed.connect(func(_t: String): _dirty = true)
	_desc_input.text_changed.connect(func(): _dirty = true)
	_verification_btn.item_selected.connect(func(_i: int): _dirty = true)
	_notifications_btn.item_selected.connect(func(_i: int): _dirty = true)
	_public_check.toggled.connect(func(_b: bool): _dirty = true)

func setup(space_id: String) -> void:
	_space_id = space_id
	var space: Dictionary = Client.get_space_by_id(space_id)

	if _name_input:
		_name_input.text = space.get("name", "")
	if _desc_input:
		_desc_input.text = space.get("description", "")

	# Icon preview
	var sname: String = space.get("name", "")
	_icon_preview.set_avatar_color(
		space.get("icon_color", Color(0.345, 0.396, 0.949))
	)
	if sname.length() > 0:
		_icon_preview.set_letter(sname[0].to_upper())
	var icon_url = space.get("icon", null)
	if icon_url is String and not icon_url.is_empty():
		_icon_preview.set_avatar_url(icon_url)

	var ver: String = space.get("verification_level", "none")
	match ver:
		"low": _verification_btn.select(1)
		"medium": _verification_btn.select(2)
		"high": _verification_btn.select(3)
		_: _verification_btn.select(0)

	var notif: String = space.get("default_notifications", "all")
	if notif == "mentions":
		_notifications_btn.select(1)
	else:
		_notifications_btn.select(0)

	_public_check.button_pressed = space.get("public", false)

	# Only the owner can see the danger zone
	_danger_zone.visible = Client.is_space_owner(space_id)
	_dirty = false

func _on_save() -> void:
	_save_btn.disabled = true
	_save_btn.text = "Saving..."
	_error_label.visible = false

	var ver_levels := ["none", "low", "medium", "high"]
	var notif_levels := ["all", "mentions"]

	var data := {
		"name": _name_input.text.strip_edges(),
		"description": _desc_input.text.strip_edges(),
		"verification_level": ver_levels[_verification_btn.selected],
		"default_notifications": notif_levels[_notifications_btn.selected],
	}

	# Public is a feature flag - send it only if the server supports it
	# For now we include it as a top-level field
	if _public_check.button_pressed:
		data["features"] = ["public"]
	else:
		data["features"] = []

	# Icon upload / removal
	if not _pending_icon_data_uri.is_empty():
		data["icon"] = _pending_icon_data_uri
	elif _icon_removed:
		data["icon"] = ""

	var result: RestResult = await Client.admin.update_space(_space_id, data)
	_save_btn.disabled = false
	_save_btn.text = "Save"

	if result == null or not result.ok:
		var err_msg: String = "Failed to update space"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_dirty = false
		queue_free()

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
		_pending_icon_data_uri = AccordCDN.build_data_uri(bytes, path)
		_icon_removed = false
		var img := Image.new()
		if img.load(path) == OK:
			var tex := ImageTexture.create_from_image(img)
			_icon_preview._apply_texture(tex)
		_dirty = true
		fd.queue_free()
	)
	fd.canceled.connect(fd.queue_free)
	add_child(fd)
	fd.popup_centered(Vector2i(600, 400))

func _on_icon_remove() -> void:
	_icon_removed = true
	_pending_icon_data_uri = ""
	_icon_preview.letter_label.visible = true
	if _icon_preview._texture_rect != null:
		_icon_preview._texture_rect.queue_free()
		_icon_preview._texture_rect = null
	_dirty = true

func _on_delete() -> void:
	var space: Dictionary = Client.get_space_by_id(_space_id)
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Space",
		"Are you sure you want to delete '%s'? This cannot be undone." % space.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		var result: RestResult = await Client.admin.delete_space(_space_id)
		if result != null and result.ok:
			_dirty = false
			queue_free()
	)

func _try_close() -> void:
	if _dirty:
		var dialog := ConfirmDialogScene.instantiate()
		get_tree().root.add_child(dialog)
		dialog.setup(
			"Unsaved Changes",
			"You have unsaved changes. Discard?",
			"Discard",
			true
		)
		dialog.confirmed.connect(func():
			_dirty = false
			queue_free()
		)
	else:
		queue_free()

func _close() -> void:
	_try_close()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_try_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_try_close()
		get_viewport().set_input_as_handled()
