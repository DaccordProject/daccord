extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const EmojiCellScene := preload("res://scenes/admin/emoji_cell.tscn")

var _space_id: String = ""
var _all_emojis: Array = []

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
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
	_search_input.text_changed.connect(_on_search_changed)
	AppState.emojis_updated.connect(_on_emojis_updated)

func setup(space_id: String) -> void:
	_space_id = space_id
	_load_emojis()

func _load_emojis() -> void:
	for child in _emoji_grid.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_emojis.clear()

	var result: RestResult = await Client.admin.get_emojis(_space_id)
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
		_all_emojis.append(emoji_dict)

	_rebuild_grid(_all_emojis)

func _rebuild_grid(emojis: Array) -> void:
	for child in _emoji_grid.get_children():
		child.queue_free()

	if emojis.is_empty():
		_empty_label.visible = _all_emojis.is_empty()
		return
	_empty_label.visible = false

	for emoji_dict in emojis:
		var cell := EmojiCellScene.instantiate()
		_emoji_grid.add_child(cell)
		cell.setup(emoji_dict, _space_id)
		cell.delete_requested.connect(_on_delete_emoji)

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_rebuild_grid(_all_emojis)
		return
	var filtered: Array = []
	for emoji in _all_emojis:
		if emoji.get("name", "").to_lower().contains(query):
			filtered.append(emoji)
	_rebuild_grid(filtered)

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

	# Validate emoji name
	if emoji_name.is_empty():
		_error_label.text = "Emoji name cannot be empty."
		_error_label.visible = true
		return

	var valid_regex := RegEx.new()
	valid_regex.compile("^[a-z0-9_]+$")
	if not valid_regex.search(emoji_name):
		_error_label.text = "Emoji name must contain only letters, numbers, and underscores."
		_error_label.visible = true
		return

	# Check for duplicate names
	for existing in _all_emojis:
		if existing.get("name", "").to_lower() == emoji_name:
			_error_label.text = "An emoji named ':%s:' already exists." % emoji_name
			_error_label.visible = true
			return

	_upload_btn.disabled = true
	_upload_btn.text = "Uploading..."
	_error_label.visible = false

	var data := {
		"name": emoji_name,
		"image": data_uri,
	}

	var result: RestResult = await Client.admin.create_emoji(_space_id, data)
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
		Client.admin.delete_emoji(_space_id, emoji.get("id", ""))
	)

func _on_emojis_updated(space_id: String) -> void:
	if space_id == _space_id:
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
