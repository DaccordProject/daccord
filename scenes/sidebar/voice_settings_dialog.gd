extends AcceptDialog

@onready var mic_option: OptionButton = $VBox/MicOption
@onready var speaker_option: OptionButton = $VBox/SpeakerOption
@onready var cam_option: OptionButton = $VBox/CamOption
@onready var res_option: OptionButton = $VBox/ResOption
@onready var fps_option: OptionButton = $VBox/FpsOption

func _ready() -> void:
	title = "Voice Settings"
	ok_button_text = "Apply"
	_populate_microphones()
	_populate_speakers()
	_populate_cameras()
	_populate_resolutions()
	_populate_fps()
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

func _populate_speakers() -> void:
	speaker_option.clear()
	var speakers: Array = AccordStream.get_speakers()
	var saved_id: String = Config.get_voice_output_device()
	var selected_idx := 0
	for i in speakers.size():
		var spk: Dictionary = speakers[i]
		var spk_id: String = spk.get("id", "")
		var spk_name: String = spk.get("name", spk_id)
		speaker_option.add_item(spk_name, i)
		speaker_option.set_item_metadata(i, spk_id)
		if spk_id == saved_id:
			selected_idx = i
	if speakers.is_empty():
		speaker_option.add_item("No speakers found", 0)
		speaker_option.disabled = true
	else:
		speaker_option.select(selected_idx)

func _populate_cameras() -> void:
	cam_option.clear()
	var cameras: Array = AccordStream.get_cameras()
	var saved_id: String = Config.get_voice_video_device()
	var selected_idx := 0
	for i in cameras.size():
		var cam: Dictionary = cameras[i]
		var cam_id: String = cam.get("id", "")
		var cam_name: String = cam.get("name", cam_id)
		cam_option.add_item(cam_name, i)
		cam_option.set_item_metadata(i, cam_id)
		if cam_id == saved_id:
			selected_idx = i
	if cameras.is_empty():
		cam_option.add_item("No cameras found", 0)
		cam_option.disabled = true
	else:
		cam_option.select(selected_idx)

func _populate_resolutions() -> void:
	res_option.clear()
	res_option.add_item("480p (640x480)", 0)
	res_option.set_item_metadata(0, 0)
	res_option.add_item("720p (1280x720)", 1)
	res_option.set_item_metadata(1, 1)
	res_option.add_item("360p (640x360)", 2)
	res_option.set_item_metadata(2, 2)
	var saved: int = Config.get_video_resolution()
	res_option.select(saved)

func _populate_fps() -> void:
	fps_option.clear()
	fps_option.add_item("15 fps", 0)
	fps_option.set_item_metadata(0, 15)
	fps_option.add_item("30 fps", 1)
	fps_option.set_item_metadata(1, 30)
	var saved: int = Config.get_video_fps()
	fps_option.select(1 if saved == 30 else 0)

func _on_confirmed() -> void:
	var mic_idx := mic_option.get_selected()
	if mic_idx >= 0 and not mic_option.disabled:
		var device_id: String = mic_option.get_item_metadata(
			mic_idx
		)
		Config.set_voice_input_device(device_id)

	var spk_idx := speaker_option.get_selected()
	if spk_idx >= 0 and not speaker_option.disabled:
		var device_id: String = (
			speaker_option.get_item_metadata(spk_idx)
		)
		Config.set_voice_output_device(device_id)
		AccordStream.set_output_device(device_id)

	var cam_idx := cam_option.get_selected()
	if cam_idx >= 0 and not cam_option.disabled:
		var device_id: String = cam_option.get_item_metadata(
			cam_idx
		)
		Config.set_voice_video_device(device_id)

	var res_idx := res_option.get_selected()
	if res_idx >= 0:
		var preset: int = res_option.get_item_metadata(res_idx)
		Config.set_video_resolution(preset)

	var fps_idx := fps_option.get_selected()
	if fps_idx >= 0:
		var fps: int = fps_option.get_item_metadata(fps_idx)
		Config.set_video_fps(fps)
