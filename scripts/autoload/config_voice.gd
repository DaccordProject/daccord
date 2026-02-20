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
	_parent.save()


func get_output_device() -> String:
	return _parent._config.get_value(
		"voice", "output_device", ""
	)


func set_output_device(device_id: String) -> void:
	_parent._config.set_value(
		"voice", "output_device", device_id
	)
	_parent.save()


func get_video_device() -> String:
	return _parent._config.get_value(
		"voice", "video_device", ""
	)


func set_video_device(device_id: String) -> void:
	_parent._config.set_value(
		"voice", "video_device", device_id
	)
	_parent.save()


func get_video_resolution() -> int:
	return _parent._config.get_value(
		"voice", "video_resolution", 0
	)


func set_video_resolution(preset: int) -> void:
	_parent._config.set_value(
		"voice", "video_resolution", preset
	)
	_parent.save()


func get_video_fps() -> int:
	return _parent._config.get_value("voice", "video_fps", 30)


func set_video_fps(fps: int) -> void:
	_parent._config.set_value("voice", "video_fps", fps)
	_parent.save()
