extends PanelContainer

var _space_id: String = ""
var _all_sounds: Array = []

@onready var _close_btn: Button = $VBox/TitleRow/CloseBtn
@onready var _search_input: LineEdit = $VBox/SearchInput
@onready var _sound_list: VBoxContainer = $VBox/Scroll/SoundList
@onready var _empty_label: Label = $VBox/EmptyLabel

func _ready() -> void:
	_close_btn.pressed.connect(close)
	_search_input.text_changed.connect(_on_search_changed)
	AppState.soundboard_updated.connect(_on_soundboard_updated)
	AppState.voice_left.connect(func(_ch: String) -> void: close())

func setup(space_id: String) -> void:
	_space_id = space_id
	_load_sounds()

func _load_sounds() -> void:
	for child in _sound_list.get_children():
		child.queue_free()
	_empty_label.visible = false
	_all_sounds.clear()

	var result: RestResult = await Client.admin.get_sounds(
		_space_id
	)
	if result == null or not result.ok:
		_empty_label.text = "Failed to load sounds."
		_empty_label.visible = true
		return

	var sounds: Array = (
		result.data if result.data is Array else []
	)
	if sounds.is_empty():
		_empty_label.text = "No sounds available."
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
		_empty_label.text = "No sounds match your search."
		_empty_label.visible = _all_sounds.size() > 0
		if _all_sounds.is_empty():
			_empty_label.text = "No sounds available."
			_empty_label.visible = true
		return
	_empty_label.visible = false

	for sound_dict in sounds:
		var btn := Button.new()
		btn.text = "  ▶  %s" % sound_dict.get("name", "")
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 32)
		btn.flat = true
		var sid: String = sound_dict.get("id", "")
		btn.pressed.connect(
			func() -> void: _on_play_pressed(sid)
		)
		_sound_list.add_child(btn)

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

func _on_play_pressed(sound_id: String) -> void:
	# Play locally immediately for instant feedback
	_play_local(sound_id)
	# Notify server so other users in the voice channel hear it too
	Client.admin.play_sound(_space_id, sound_id)

func _play_local(sound_id: String) -> void:
	for sound_dict in _all_sounds:
		if sound_dict.get("id", "") == sound_id:
			var audio_url: String = sound_dict.get("audio_url", "")
			if audio_url.is_empty():
				return
			var full_url: String = Client.admin.get_sound_url(
				_space_id, audio_url
			)
			var volume: float = sound_dict.get("volume", 1.0)
			SoundManager.play_preview(full_url, volume)
			return

func _on_soundboard_updated(space_id: String) -> void:
	if space_id == _space_id:
		_load_sounds()

func close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		var local_pos := get_global_rect()
		if not local_pos.has_point(event.global_position):
			close()
			get_viewport().set_input_as_handled()
