extends AcceptDialog

@onready var mic_option: OptionButton = $VBox/MicOption

func _ready() -> void:
	title = "Voice Settings"
	ok_button_text = "Apply"
	_populate_microphones()
	confirmed.connect(_on_confirmed)

func _populate_microphones() -> void:
	mic_option.clear()
	var mics: Array = AccordStream.get_microphones()
	var saved_id: String = Config.get_voice_input_device()
	var selected_idx := 0
	for i in mics.size():
		var mic: Dictionary = mics[i]
		var mic_id: String = mic.get("id", "")
		var mic_name: String = mic.get("name", mic_id)
		mic_option.add_item(mic_name, i)
		mic_option.set_item_metadata(i, mic_id)
		if mic_id == saved_id:
			selected_idx = i
	if mics.is_empty():
		mic_option.add_item("No microphones found", 0)
		mic_option.disabled = true
	else:
		mic_option.select(selected_idx)

func _on_confirmed() -> void:
	var idx := mic_option.get_selected()
	if idx >= 0 and not mic_option.disabled:
		var device_id: String = mic_option.get_item_metadata(idx)
		Config.set_voice_input_device(device_id)
