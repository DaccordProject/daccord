extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")

var _guild_id: String = ""

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _emoji_grid: GridContainer = $CenterContainer/Panel/VBox/Scroll/EmojiGrid
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _upload_btn: Button = $CenterContainer/Panel/VBox/UploadButton
@onready var _file_dialog: FileDialog = $FileDialog
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_upload_btn.pressed.connect(_on_upload_pressed)
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.filters = PackedStringArray(["*.png ; PNG Images", "*.gif ; GIF Images"])
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	AppState.emojis_updated.connect(_on_emojis_updated)

func setup(guild_id: String) -> void:
	_guild_id = guild_id
	_load_emojis()

func _load_emojis() -> void:
	for child in _emoji_grid.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false

	var result: RestResult = await Client.get_emojis(_guild_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load emojis"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var emojis: Array = result.data if result.data is Array else []
	if emojis.is_empty():
		_empty_label.visible = true
		return

	for emoji in emojis:
		var emoji_dict: Dictionary
		if emoji is AccordEmoji:
			emoji_dict = ClientModels.emoji_to_dict(emoji)
		elif emoji is Dictionary:
			emoji_dict = emoji
		else:
			continue
		var cell := _create_emoji_cell(emoji_dict)
		_emoji_grid.add_child(cell)

func _create_emoji_cell(emoji: Dictionary) -> VBoxContainer:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(80, 80)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER

	# Colored placeholder for the emoji image
	var placeholder := ColorRect.new()
	placeholder.custom_minimum_size = Vector2(32, 32)
	placeholder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	placeholder.color = Color.from_hsv(
		fmod(emoji.get("name", "").hash() * 0.618, 1.0), 0.6, 0.8
	)
	cell.add_child(placeholder)

	var name_label := Label.new()
	name_label.text = ":%s:" % emoji.get("name", "")
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.add_child(name_label)

	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.flat = true
	del_btn.add_theme_color_override("font_color", Color(0.95, 0.3, 0.3))
	del_btn.add_theme_font_size_override("font_size", 11)
	del_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	del_btn.pressed.connect(_on_delete_emoji.bind(emoji))
	cell.add_child(del_btn)

	return cell

func _on_upload_pressed() -> void:
	_file_dialog.popup_centered(Vector2i(600, 400))

func _on_file_selected(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_error_label.text = "Failed to open file"
		_error_label.visible = true
		return

	var bytes := file.get_buffer(file.get_length())
	file.close()

	var ext := path.get_extension().to_lower()
	var mime := "image/png" if ext == "png" else "image/gif"
	var b64 := Marshalls.raw_to_base64(bytes)
	var data_uri := "data:%s;base64,%s" % [mime, b64]

	# Extract name from filename without extension
	var emoji_name: String = path.get_file().get_basename()
	emoji_name = emoji_name.replace(" ", "_").replace("-", "_").to_lower()

	_upload_btn.disabled = true
	_upload_btn.text = "Uploading..."
	_error_label.visible = false

	var data := {
		"name": emoji_name,
		"image": data_uri,
	}

	var result: RestResult = await Client.create_emoji(_guild_id, data)
	_upload_btn.disabled = false
	_upload_btn.text = "Upload Emoji"

	if result == null or not result.ok:
		var err_msg: String = "Failed to upload emoji"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
	else:
		_load_emojis()

func _on_delete_emoji(emoji: Dictionary) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Emoji",
		"Are you sure you want to delete :%s:?" % emoji.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.delete_emoji(_guild_id, emoji.get("id", ""))
	)

func _on_emojis_updated(guild_id: String) -> void:
	if guild_id == _guild_id:
		_load_emojis()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
