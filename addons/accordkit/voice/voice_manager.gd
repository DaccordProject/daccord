class_name VoiceManager extends RefCounted

signal voice_connected(info: AccordVoiceServerUpdate)
signal voice_disconnected(channel_id: String)
signal voice_state_changed(state: AccordVoiceState)
signal voice_server_updated(info: AccordVoiceServerUpdate)
signal voice_error(error: String)

var _voice_api: VoiceApi
var _gateway: GatewaySocket
var _current_channel_id: String = ""
var _current_voice_state = null  # AccordVoiceState


func _init(voice_api: VoiceApi, gw: GatewaySocket) -> void:
	_voice_api = voice_api
	_gateway = gw
	_gateway.voice_state_update.connect(_on_voice_state_update)
	_gateway.voice_server_update.connect(_on_voice_server_update)


func join(channel_id: String, self_mute: bool = false, self_deaf: bool = false) -> RestResult:
	var result := await _voice_api.join(channel_id, self_mute, self_deaf)
	if result.ok and result.data is AccordVoiceServerUpdate:
		var info: AccordVoiceServerUpdate = result.data
		_current_channel_id = channel_id
		_current_voice_state = info.voice_state
		voice_connected.emit(info)
	else:
		var msg: String = ""
		if result.error != null:
			msg = result.error.message
		else:
			msg = "Failed to join voice channel"
		voice_error.emit(msg)
	return result


func leave() -> RestResult:
	var channel_id := _current_channel_id
	if channel_id == "":
		return RestResult.failure(0, null)
	var result := await _voice_api.leave(channel_id)
	if result.ok:
		_current_channel_id = ""
		_current_voice_state = null
		voice_disconnected.emit(channel_id)
	return result


func is_connected_to_voice() -> bool:
	return _current_channel_id != ""


func get_current_channel() -> String:
	return _current_channel_id


func get_current_voice_state():
	return _current_voice_state


func _on_voice_state_update(state: AccordVoiceState) -> void:
	voice_state_changed.emit(state)
	# Detect forced disconnection: our user's channel_id became null
	if _current_voice_state != null and state.user_id == _current_voice_state.user_id:
		_current_voice_state = state
		if state.channel_id == null and _current_channel_id != "":
			var old_channel := _current_channel_id
			_current_channel_id = ""
			_current_voice_state = null
			voice_disconnected.emit(old_channel)


func _on_voice_server_update(info: AccordVoiceServerUpdate) -> void:
	voice_server_updated.emit(info)
