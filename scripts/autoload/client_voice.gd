class_name ClientVoice
extends RefCounted

## Handles voice channel operations for Client.
## Receives a reference to the Client autoload node so it can
## access caches, routing helpers, and emit AppState signals.

const DEBUG_VOICE_LOGS := true
const VOICE_LOG_PATH := "user://voice_debug.log"

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

# --- Voice data access ---

func get_voice_users(channel_id: String) -> Array:
	return _c._voice_state_cache.get(channel_id, [])

func get_voice_user_count(channel_id: String) -> int:
	return _c._voice_state_cache.get(channel_id, []).size()

# --- Voice mutation API ---

func join_voice_channel(channel_id: String) -> bool:
	_voice_log("join_voice_channel cid=%s" % channel_id)
	# Already in this channel
	if AppState.voice_channel_id == channel_id:
		_voice_log("join_voice_channel already in channel")
		return true
	# Leave current voice if in one
	if not AppState.voice_channel_id.is_empty():
		await leave_voice_channel()
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		push_error(
			"[Client] No connection for voice channel: ",
			channel_id
		)
		AppState.voice_error.emit("No connection found")
		return false
	var guild_id: String = _c._channel_to_guild.get(
		channel_id, ""
	)
	var result: RestResult = await client.voice.join(
		channel_id, AppState.is_voice_muted,
		AppState.is_voice_deafened
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		_voice_log("join_voice_channel failed err=%s" % err)
		push_error("[Client] Failed to join voice: ", err)
		AppState.voice_error.emit(err)
		return false
	_c._voice_server_info = {}
	if result.data is AccordVoiceServerUpdate:
		var info: AccordVoiceServerUpdate = result.data
		_c._voice_server_info = info.to_dict()
		var status: Dictionary = _validate_backend_info(info)
		var ok: bool = status.get("ok", false)
		var backend: String = status.get("backend", "")
		var reason: String = status.get("reason", "")
		_voice_log(
			"join_voice_channel got server_update backend=%s" % backend
		)
		_voice_log(
			"server_update details sfu=%s livekit=%s token=%s" % [
				str(info.sfu_endpoint),
				str(info.livekit_url),
				str(info.token != null)
			]
		)
		if not ok:
			_voice_log(
				"join_voice_channel backend invalid reason=%s" % reason
			)
			_c._voice_server_info = {}
			var leave_client: AccordClient = _c._client_for_channel(
				channel_id
			)
			if leave_client != null:
				var leave_result: RestResult = await leave_client.voice.leave(
					channel_id
				)
				if not leave_result.ok:
					var leave_err: String = (
						leave_result.error.message
						if leave_result.error else "unknown"
					)
					_voice_log(
						"leave after invalid backend failed err=%s" % leave_err
					)
			_cleanup_failed_join_state(channel_id)
			AppState.voice_error.emit(
				"Voice backend unavailable — server returned no credentials"
			)
			return false
		_connect_voice_backend(info)
	else:
		_voice_log(
			"join_voice_channel no server_update data_type=%s" % [
				str(typeof(result.data))
			]
		)
		AppState.voice_error.emit(
			"Voice join failed — server returned unexpected data"
		)
		return false
	AppState.join_voice(channel_id, guild_id)
	_c.fetch.fetch_voice_states(channel_id)
	return true

func _connect_voice_backend(
	info: AccordVoiceServerUpdate,
) -> void:
	if _c._voice_session == null:
		_voice_log("connect backend: no voice session")
		push_warning("Voice session unavailable")
		return
	var backend: String = _resolve_backend(info)
	if (backend == "livekit"
			and info.livekit_url != null
			and info.token != null):
		_voice_log("connect backend: livekit")
		_c._voice_session.connect_livekit(
			str(info.livekit_url), str(info.token)
		)
		_enable_audio_level_polling()
	elif info.sfu_endpoint != null:
		_voice_log("connect backend: custom_sfu")
		var mic_id: String = Config.voice.get_input_device()
		if mic_id.is_empty() and _c._accord_stream != null:
			var mics: Array = _c._accord_stream.get_microphones()
			if mics.size() > 0:
				mic_id = mics[0]["id"]
		if DEBUG_VOICE_LOGS:
			_voice_log("mic_id=" + (mic_id if not mic_id.is_empty() else "<default>"))
		var output_id: String = Config.voice.get_output_device()
		if not output_id.is_empty() and _c._accord_stream != null:
			var speakers: Array = _c._accord_stream.get_speakers()
			if _has_speaker(speakers, output_id):
				_c._accord_stream.set_output_device(output_id)
			else:
				if DEBUG_VOICE_LOGS:
					_voice_log(
						"output device not found, using default: " +
						output_id
					)
				Config.voice.set_output_device("")
		var ice_config := {}
		_c._voice_session.connect_custom_sfu(
			str(info.sfu_endpoint), ice_config, mic_id
		)
		_enable_audio_level_polling()
	else:
		_voice_log("connect backend: missing sfu_endpoint/livekit creds")

func leave_voice_channel() -> bool:
	var channel_id := AppState.voice_channel_id
	if channel_id.is_empty():
		return true
	# Clean up video/screen tracks
	if _c._camera_track != null:
		_c._camera_track.stop()
		_c._camera_track = null
	if _c._screen_track != null:
		_c._screen_track.stop()
		_c._screen_track = null
	# Clean up remote tracks
	for uid in _c._remote_tracks:
		var rt = _c._remote_tracks[uid]
		if rt != null:
			rt.stop()
	_c._remote_tracks.clear()
	if _c._voice_session != null:
		_c._voice_session.disconnect_voice()
	var client: AccordClient = _c._client_for_channel(channel_id)
	if client == null:
		AppState.leave_voice()
		return true
	var result: RestResult = await client.voice.leave(
		channel_id
	)
	if not result.ok:
		var err: String = (
			result.error.message
			if result.error else "unknown"
		)
		push_error(
			"[Client] Failed to leave voice: ", err
		)
	# Remove self from voice state cache
	var my_id: String = _c.current_user.get("id", "")
	if _c._voice_state_cache.has(channel_id):
		var states: Array = _c._voice_state_cache[
			channel_id
		]
		for i in states.size():
			if states[i].get("user_id", "") == my_id:
				states.remove_at(i)
				break
	_c._voice_server_info = {}
	# Clear all speaking states
	for uid in _c._speaking_users.keys():
		AppState.speaking_changed.emit(uid, false)
	_c._speaking_users.clear()
	AppState.leave_voice()
	AppState.voice_state_updated.emit(channel_id)
	return result.ok

func set_voice_muted(muted: bool) -> void:
	if _c._voice_session != null:
		_c._voice_session.set_muted(muted)
	AppState.set_voice_muted(muted)

func set_voice_deafened(deafened: bool) -> void:
	if _c._voice_session != null:
		_c._voice_session.set_deafened(deafened)
	AppState.set_voice_deafened(deafened)

# --- Video track management ---

func toggle_video() -> void:
	if AppState.voice_channel_id.is_empty():
		return
	if _c._camera_track != null:
		_c._camera_track.stop()
		_c._camera_track = null
		AppState.set_video_enabled(false)
	else:
		if _c._accord_stream == null:
			AppState.voice_error.emit("AccordStream unavailable")
			return
		var cameras: Array = _c._accord_stream.get_cameras()
		if cameras.is_empty():
			AppState.voice_error.emit("No camera found")
			return
		var cam_id: String = Config.voice.get_video_device()
		# Fall back to first camera if saved device is gone
		if cam_id.is_empty() or not _has_camera(cameras, cam_id):
			cam_id = cameras[0]["id"]
		var res_preset: int = Config.voice.get_video_resolution()
		var width := 640
		var height := 480
		match res_preset:
			1:
				width = 1280
				height = 720
			2:
				width = 640
				height = 360
		var fps: int = Config.voice.get_video_fps()
		_c._camera_track = _c._accord_stream.create_camera_track(
			cam_id, width, height, fps
		)
		AppState.set_video_enabled(true)
	_send_voice_state_update()

func start_screen_share(
	source_type: String, source_id: int,
) -> void:
	if AppState.voice_channel_id.is_empty():
		return
	# Stop existing screen track if any
	if _c._screen_track != null:
		_c._screen_track.stop()
		_c._screen_track = null
	if _c._accord_stream == null:
		AppState.voice_error.emit("AccordStream unavailable")
		return
	if source_type == "screen":
		_c._screen_track = (
			_c._accord_stream.create_screen_track(source_id, 15)
		)
	elif source_type == "window":
		_c._screen_track = (
			_c._accord_stream.create_window_track(source_id, 15)
		)
	AppState.set_screen_sharing(true)
	_send_voice_state_update()

func stop_screen_share() -> void:
	if _c._screen_track != null:
		_c._screen_track.stop()
		_c._screen_track = null
	AppState.set_screen_sharing(false)
	_send_voice_state_update()

func _send_voice_state_update() -> void:
	var guild_id := AppState.voice_guild_id
	var channel_id := AppState.voice_channel_id
	if guild_id.is_empty() or channel_id.is_empty():
		return
	var client: AccordClient = _c._client_for_guild(guild_id)
	if client == null:
		return
	client.update_voice_state(
		guild_id, channel_id,
		AppState.is_voice_muted,
		AppState.is_voice_deafened,
		AppState.is_video_enabled,
		AppState.is_screen_sharing,
	)

# --- Voice session callbacks ---

func on_session_state_changed(state: int) -> void:
	match state:
		4: # AccordVoiceSession.FAILED
			push_error("[Client] Voice session failed")
			AppState.voice_error.emit(
				"Voice connection failed"
			)
		0: # AccordVoiceSession.DISCONNECTED
			pass # Handled by leave_voice_channel

func on_peer_joined(_user_id: String) -> void:
	var cid := AppState.voice_channel_id
	if cid.is_empty():
		return
	# Refresh voice states from server
	_c.fetch.fetch_voice_states(cid)

func on_peer_left(user_id: String) -> void:
	var cid := AppState.voice_channel_id
	if cid.is_empty():
		return
	# Remove from local cache
	if _c._voice_state_cache.has(cid):
		var states: Array = _c._voice_state_cache[cid]
		for i in states.size():
			if states[i].get("user_id", "") == user_id:
				states.remove_at(i)
				break
		if _c._channel_cache.has(cid):
			_c._channel_cache[cid]["voice_users"] = (
				states.size()
			)
	# Clean up speaking state for this peer
	if _c._speaking_users.has(user_id):
		_c._speaking_users.erase(user_id)
		AppState.speaking_changed.emit(user_id, false)
	# Clean up remote track for this peer
	if _c._remote_tracks.has(user_id):
		var rt = _c._remote_tracks[user_id]
		if rt != null:
			rt.stop()
		_c._remote_tracks.erase(user_id)
		AppState.remote_track_removed.emit(user_id)
	AppState.voice_state_updated.emit(cid)

func on_track_received(
	user_id: String, track,
) -> void:
	if track == null:
		return
	# Only handle video tracks for rendering
	if track.get_kind() != "video":
		return
	# Stop any previous track for this peer
	if _c._remote_tracks.has(user_id):
		var old = _c._remote_tracks[user_id]
		if old != null:
			old.stop()
	_c._remote_tracks[user_id] = track
	AppState.remote_track_received.emit(user_id, track)

func on_audio_level_changed(
	user_id: String, level: float,
) -> void:
	# Skip if deafened
	if AppState.is_voice_deafened:
		return
	# Map @local to current user's ID
	var uid := user_id
	if uid == "@local" or uid == "local" or uid == "self" or uid.is_empty():
		uid = _c.current_user.get("id", "")
		if uid.is_empty():
			return
	var now: float = Time.get_ticks_msec() / 1000.0
	if level > 0.001:
		var was_speaking: bool = _c._speaking_users.has(uid)
		_c._speaking_users[uid] = now
		if not was_speaking:
			if DEBUG_VOICE_LOGS:
				_voice_log(
					"speaking_start uid=%s raw=%s level=%.3f" % [
						uid, user_id, level
					]
				)
			AppState.speaking_changed.emit(uid, true)
	else:
		# Just update timestamp if already speaking;
		# the debounce timer handles silence detection
		pass

func on_signal_outgoing(
	signal_type: String, payload_json: String,
) -> void:
	var gid := AppState.voice_guild_id
	var cid := AppState.voice_channel_id
	var client: AccordClient = _c._client_for_guild(gid)
	if client == null:
		return
	var payload = JSON.parse_string(payload_json)
	if payload == null:
		payload = {}
	client.send_voice_signal(
		gid, cid, signal_type, payload
	)

func _has_camera(cameras: Array, device_id: String) -> bool:
	for cam in cameras:
		if cam.get("id", "") == device_id:
			return true
	return false

func _has_speaker(speakers: Array, device_id: String) -> bool:
	for i in speakers.size():
		var speaker: Dictionary = speakers[i]
		var speaker_id: String = speaker.get("id", "")
		if speaker_id == device_id:
			return true
	return false

func _cleanup_failed_join_state(channel_id: String) -> void:
	var my_id: String = _c.current_user.get("id", "")
	if my_id.is_empty():
		return
	if _c._voice_state_cache.has(channel_id):
		var states: Array = _c._voice_state_cache[channel_id]
		for i in range(states.size() - 1, -1, -1):
			if states[i].get("user_id", "") == my_id:
				states.remove_at(i)
		if _c._channel_cache.has(channel_id):
			_c._channel_cache[channel_id]["voice_users"] = (
				states.size()
			)
		AppState.voice_state_updated.emit(channel_id)

func _enable_audio_level_polling() -> void:
	if _c._voice_session == null:
		return
	# Ensure audio level polling runs even if the session
	# never transitions to CONNECTED (e.g., missed state signal).
	if DEBUG_VOICE_LOGS:
		var has_audio: bool = _c._voice_session.has_signal(
			"audio_level_changed"
		)
		var was_processing: bool = _c._voice_session.is_processing()
		_voice_log(
			"enable_audio_polling has_audio_signal=%s was_processing=%s" % [
				str(has_audio), str(was_processing)
			]
		)
	_c._voice_session.set_process(true)
	if DEBUG_VOICE_LOGS:
		_voice_log(
			"enable_audio_polling now_processing=%s" % [
				str(_c._voice_session.is_processing())
			]
		)

func _voice_log(message: String) -> void:
	if DEBUG_VOICE_LOGS:
		var line := "[VoiceDebug] " + message
		print(line)
		var f := FileAccess.open(VOICE_LOG_PATH, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
			f.store_line(line)
			f.close()

func _resolve_backend(info: AccordVoiceServerUpdate) -> String:
	var backend: String = info.backend
	if backend.is_empty():
		var sfu: String = ""
		if info.sfu_endpoint != null:
			sfu = str(info.sfu_endpoint)
		var lk_url: String = ""
		if info.livekit_url != null:
			lk_url = str(info.livekit_url)
		var lk_token: String = ""
		if info.token != null:
			lk_token = str(info.token)
		if not sfu.is_empty():
			backend = "custom"
		elif not lk_url.is_empty() and not lk_token.is_empty():
			backend = "livekit"
	return backend

func _validate_backend_info(
	info: AccordVoiceServerUpdate,
) -> Dictionary:
	var backend: String = _resolve_backend(info)
	if backend == "custom":
		var sfu: String = ""
		if info.sfu_endpoint != null:
			sfu = str(info.sfu_endpoint)
		if sfu.is_empty():
			return {
				"ok": false,
				"backend": backend,
				"reason": "missing sfu_endpoint",
			}
		return {"ok": true, "backend": backend, "reason": ""}
	if backend == "livekit":
		var lk_url: String = ""
		if info.livekit_url != null:
			lk_url = str(info.livekit_url)
		var lk_token: String = ""
		if info.token != null:
			lk_token = str(info.token)
		if lk_url.is_empty() or lk_token.is_empty():
			return {
				"ok": false,
				"backend": backend,
				"reason": "missing livekit_url/token",
			}
		return {"ok": true, "backend": backend, "reason": ""}
	return {
		"ok": false,
		"backend": (backend if not backend.is_empty() else "unknown"),
		"reason": "missing backend or credentials",
	}
