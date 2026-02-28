extends RefCounted
## Voice and video device configuration helper for Config.

var _parent: Node # Config singleton


func _init(parent: Node) -> void:
	_parent = parent


func get_input_device() -> String:
	return _parent._config.get_value(
		"voice", "input_device", ""
	)


func set_input_device(device_id: String) -> void:
	_parent._config.set_value(
		"voice", "input_device", device_id
	)
	_parent._save()
	_apply_input_device(device_id)


func get_output_device() -> String:
	return _parent._config.get_value(
		"voice", "output_device", ""
	)


func set_output_device(device_id: String) -> void:
	_parent._config.set_value(
		"voice", "output_device", device_id
	)
	_parent._save()
	_apply_output_device(device_id)


func get_video_device() -> String:
	return _parent._config.get_value(
		"voice", "video_device", ""
	)


func set_video_device(device_id: String) -> void:
	_parent._config.set_value(
		"voice", "video_device", device_id
	)
	_parent._save()


func get_video_resolution() -> int:
	return _parent._config.get_value(
		"voice", "video_resolution", 0
	)


func set_video_resolution(preset: int) -> void:
	_parent._config.set_value(
		"voice", "video_resolution", preset
	)
	_parent._save()
	AppState.config_changed.emit("voice", "video_resolution")


func get_video_fps() -> int:
	return _parent._config.get_value("voice", "video_fps", 30)


func set_video_fps(fps: int) -> void:
	_parent._config.set_value("voice", "video_fps", fps)
	_parent._save()
	AppState.config_changed.emit("voice", "video_fps")


func get_input_sensitivity() -> int:
	return _parent._config.get_value(
		"voice", "input_sensitivity", 50
	)


func set_input_sensitivity(value: int) -> void:
	_parent._config.set_value(
		"voice", "input_sensitivity", clampi(value, 0, 100)
	)
	_parent._save()


func get_input_volume() -> int:
	return _parent._config.get_value(
		"voice", "input_volume", 100
	)


func set_input_volume(value: int) -> void:
	_parent._config.set_value(
		"voice", "input_volume", clampi(value, 0, 200)
	)
	_parent._save()


func get_output_volume() -> int:
	return _parent._config.get_value(
		"voice", "output_volume", 100
	)


func set_output_volume(value: int) -> void:
	_parent._config.set_value(
		"voice", "output_volume", clampi(value, 0, 200)
	)
	_parent._save()


func get_debug_logging() -> bool:
	return _parent._config.get_value(
		"voice", "debug_logging", false
	)


func set_debug_logging(enabled: bool) -> void:
	_parent._config.set_value(
		"voice", "debug_logging", enabled
	)
	_parent._save()
	AppState.config_changed.emit("voice", "debug_logging")


func get_speaking_threshold() -> float:
	var sensitivity: int = get_input_sensitivity()
	# Logarithmic mapping: 0% → 0.1, 50% → ~0.003, 100% → 0.0001
	return pow(10.0, -1.0 - 3.0 * sensitivity / 100.0)


func apply_devices() -> void:
	_apply_input_device(get_input_device())
	_apply_output_device(get_output_device())


func _apply_input_device(device: String) -> void:
	if device.is_empty():
		device = "Default"
	AudioServer.input_device = device


func _apply_output_device(device: String) -> void:
	if device.is_empty():
		device = "Default"
	AudioServer.output_device = device
