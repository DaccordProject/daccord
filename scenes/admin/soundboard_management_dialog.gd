extends ColorRect

const ConfirmDialogScene := preload("res://scenes/admin/confirm_dialog.tscn")
const SoundRowScene := preload("res://scenes/admin/sound_row.tscn")

var _space_id: String = ""
var _all_sounds: Array = []
var _can_manage: bool = false
var _volume_debounce: Dictionary = {}

@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _search_input: LineEdit = $CenterContainer/Panel/VBox/SearchInput
@onready var _sound_list: VBoxContainer = $CenterContainer/Panel/VBox/Scroll/SoundList
@onready var _empty_label: Label = $CenterContainer/Panel/VBox/EmptyLabel
@onready var _upload_btn: Button = $CenterContainer/Panel/VBox/UploadButton
@onready var _file_dialog: FileDialog = $FileDialog
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_upload_btn.pressed.connect(_on_upload_pressed)
	_file_dialog.file_selected.connect(_on_file_selected)
	_file_dialog.filters = PackedStringArray([
		"*.ogg ; OGG Audio",
		"*.mp3 ; MP3 Audio",
		"*.wav ; WAV Audio",
	])
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_search_input.text_changed.connect(_on_search_changed)
	AppState.soundboard_updated.connect(_on_soundboard_updated)

func setup(space_id: String) -> void:
	_space_id = space_id
	_can_manage = Client.has_permission(
		space_id, AccordPermission.MANAGE_SOUNDBOARD
	)
	_upload_btn.visible = _can_manage
	_load_sounds()

func _load_sounds() -> void:
	for child in _sound_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_error_label.visible = false
	_all_sounds.clear()

	var result: RestResult = await Client.admin.get_sounds(_space_id)
	if result == null or not result.ok:
		var err_msg: String = "Failed to load sounds"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true
		return

	var sounds: Array = result.data if result.data is Array else []
	if sounds.is_empty():
		_empty_label.visible = true
		return

	for sound in sounds:
		var sound_dict: Dictionary
		if sound is AccordSound:
			sound_dict = ClientModels.sound_to_dict(sound)
		elif sound is Dictionary:
			sound_dict = sound
		else:
			continue
		_all_sounds.append(sound_dict)

	_rebuild_list(_all_sounds)

func _rebuild_list(sounds: Array) -> void:
	for child in _sound_list.get_children():
		child.queue_free()

	if sounds.is_empty():
		_empty_label.visible = _all_sounds.is_empty()
		return
	_empty_label.visible = false

	for sound_dict in sounds:
		var row := SoundRowScene.instantiate()
		_sound_list.add_child(row)
		row.setup(sound_dict, _can_manage)
		row.delete_requested.connect(_on_delete_sound)
		row.play_requested.connect(_on_play_sound)
		row.rename_requested.connect(_on_rename_sound)
		row.volume_changed.connect(_on_volume_changed)

func _on_search_changed(text: String) -> void:
	var query := text.strip_edges().to_lower()
	if query.is_empty():
		_rebuild_list(_all_sounds)
		return
	var filtered: Array = []
	for sound in _all_sounds:
		if sound.get("name", "").to_lower().contains(query):
			filtered.append(sound)
	_rebuild_list(filtered)

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
	var mime := "audio/ogg"
	match ext:
		"mp3":
			mime = "audio/mpeg"
		"wav":
			mime = "audio/wav"
	var b64 := Marshalls.raw_to_base64(bytes)
	var data_uri := "data:%s;base64,%s" % [mime, b64]

	var sound_name: String = path.get_file().get_basename()
	sound_name = sound_name.replace(" ", "_").replace("-", "_").to_lower()

	if sound_name.is_empty():
		_error_label.text = "Sound name cannot be empty."
		_error_label.visible = true
		return

	var valid_regex := RegEx.new()
	valid_regex.compile("^[a-z0-9_]+$")
	if not valid_regex.search(sound_name):
		_error_label.text = "Sound name must contain only letters, numbers, and underscores."
		_error_label.visible = true
		return

	for existing in _all_sounds:
		if existing.get("name", "").to_lower() == sound_name:
			_error_label.text = "A sound named '%s' already exists." % sound_name
			_error_label.visible = true
			return

	_upload_btn.disabled = true
	_upload_btn.text = "Uploading..."
	_error_label.visible = false

	var data := {
		"name": sound_name,
		"audio": data_uri,
	}

	var result: RestResult = await Client.admin.create_sound(_space_id, data)
	_upload_btn.disabled = false
	_upload_btn.text = "Upload Sound"

	if result == null or not result.ok:
		var err_msg: String = "Failed to upload sound"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _on_delete_sound(sound: Dictionary) -> void:
	var dialog := ConfirmDialogScene.instantiate()
	get_tree().root.add_child(dialog)
	dialog.setup(
		"Delete Sound",
		"Are you sure you want to delete '%s'?" % sound.get("name", ""),
		"Delete",
		true
	)
	dialog.confirmed.connect(func():
		Client.admin.delete_sound(_space_id, sound.get("id", ""))
	)

func _on_play_sound(sound: Dictionary) -> void:
	var audio_url: String = sound.get("audio_url", "")
	if audio_url.is_empty():
		return
	var full_url: String = Client.admin.get_sound_url(_space_id, audio_url)
	SoundManager.play_preview(full_url, sound.get("volume", 1.0))

func _on_rename_sound(sound: Dictionary, new_name: String) -> void:
	var result: RestResult = await Client.admin.update_sound(
		_space_id, sound.get("id", ""), {"name": new_name}
	)
	if result == null or not result.ok:
		var err_msg: String = "Failed to rename sound"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _on_volume_changed(sound: Dictionary, new_volume: float) -> void:
	var sound_id: String = sound.get("id", "")
	_volume_debounce[sound_id] = new_volume
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	var current_val: float = _volume_debounce.get(sound_id, new_volume)
	if current_val != new_volume:
		return
	_volume_debounce.erase(sound_id)
	var result: RestResult = await Client.admin.update_sound(
		_space_id, sound_id, {"volume": new_volume}
	)
	if result == null or not result.ok:
		var err_msg: String = "Failed to update volume"
		if result != null and result.error:
			err_msg = result.error.message
		_error_label.text = err_msg
		_error_label.visible = true

func _on_soundboard_updated(space_id: String) -> void:
	if space_id == _space_id:
		_load_sounds()

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
