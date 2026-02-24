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
		var reason: String = status.get("reason", "")
		_voice_log(
			"join_voice_channel livekit_url=%s token=%s" % [
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
	if info.livekit_url == null or info.token == null:
		_voice_log("connect backend: missing livekit credentials")
		return
	_voice_log("connect backend: livekit url=%s" % str(info.livekit_url))
	_c._voice_session.connect_to_room(
		str(info.livekit_url), str(info.token)
	)

func leave_voice_channel() -> bool:
	var channel_id := AppState.voice_channel_id
	if channel_id.is_empty():
		return true
	# Clean up video/screen tracks
	if _c._camera_track != null:
		_c._camera_track.close()
		_c._camera_track = null
	if _c._screen_track != null:
		_c._screen_track.close()
		_c._screen_track = null
	# Clean up remote tracks
	for uid in _c._remote_tracks:
		var rt = _c._remote_tracks[uid]
		if rt != null:
			rt.close()
	_c._remote_tracks.clear()
	_c._voice_session.disconnect_voice()
	# Notify the server we're leaving (best-effort).
	# If the connection is down or missing, skip the REST call.
	var guild_id: String = _c._channel_to_guild.get(channel_id, "")
	var conn = _c._conn_for_guild(guild_id) if not guild_id.is_empty() else null
	var conn_alive: bool = conn != null \
		and conn.get("status", "") == "connected" \
		and conn.get("client") != null
	var result_ok := true
	if conn_alive:
		var client: AccordClient = conn["client"]
		var result: RestResult = await client.voice.leave(
			channel_id
		)
		if not result.ok:
			var err: String = (
				result.error.message
				if result.error else "unknown"
			)
			push_warning(
				"[Client] Failed to leave voice: ", err
			)
			result_ok = false
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
	return result_ok

func set_voice_muted(muted: bool) -> void:
	_c._voice_session.set_muted(muted)
	AppState.set_voice_muted(muted)

func set_voice_deafened(deafened: bool) -> void:
	_c._voice_session.set_deafened(deafened)
	AppState.set_voice_deafened(deafened)

# --- Video track management ---

func toggle_video() -> void:
	if AppState.voice_channel_id.is_empty():
		return
	if _c._camera_track != null:
		_c._camera_track.close()
		_c._camera_track = null
		_c._voice_session.unpublish_camera()
		AppState.set_video_enabled(false)
	else:
		var res_preset: int = Config.voice.get_video_resolution()
		var width := 640
		var height := 480
		match res_preset:
			1:
				width = 1280
				height = 720
			2:
				width = 1920
				height = 1080
		var fps: int = Config.voice.get_video_fps()
		var stream = _c._voice_session.publish_camera(
			Vector2i(width, height), fps
		)
		if stream == null:
			AppState.voice_error.emit("Failed to publish camera")
			return
		_c._camera_track = stream
		AppState.set_video_enabled(true)
	_send_voice_state_update()

func start_screen_share(
	_source_type: String, _source_id: int,
) -> void:
	if AppState.voice_channel_id.is_empty():
		return
	# Stop existing screen track if any
	if _c._screen_track != null:
		_c._screen_track.close()
		_c._screen_track = null
		_c._voice_session.unpublish_screen()
	var stream = _c._voice_session.publish_screen()
	if stream == null:
		AppState.voice_error.emit("Failed to share screen")
		return
	_c._screen_track = stream
	AppState.set_screen_sharing(true)
	_send_voice_state_update()

func stop_screen_share() -> void:
	if _c._screen_track != null:
		_c._screen_track.close()
		_c._screen_track = null
	_c._voice_session.unpublish_screen()
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
		LiveKitAdapter.State.CONNECTING:
			_voice_log("session_state: CONNECTING")
		LiveKitAdapter.State.CONNECTED:
			_voice_log("session_state: CONNECTED")
		LiveKitAdapter.State.RECONNECTING:
			_voice_log("session_state: RECONNECTING")
		LiveKitAdapter.State.FAILED:
			_voice_log("session_state: FAILED")
			push_error("[Client] Voice session failed")
			AppState.voice_error.emit(
				"Voice connection failed"
			)
		LiveKitAdapter.State.DISCONNECTED:
			_voice_log("session_state: DISCONNECTED")

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
			rt.close()
		_c._remote_tracks.erase(user_id)
		AppState.remote_track_removed.emit(user_id)
	AppState.voice_state_updated.emit(cid)

func on_track_received(
	user_id: String, stream,
) -> void:
	if stream == null:
		return
	# Stop any previous track for this peer
	if _c._remote_tracks.has(user_id):
		var old = _c._remote_tracks[user_id]
		if old != null:
			old.close()
	_c._remote_tracks[user_id] = stream
	AppState.remote_track_received.emit(user_id, stream)

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

func _validate_backend_info(
	info: AccordVoiceServerUpdate,
) -> Dictionary:
	var lk_url: String = ""
	if info.livekit_url != null:
		lk_url = str(info.livekit_url)
	var lk_token: String = ""
	if info.token != null:
		lk_token = str(info.token)
	if lk_url.is_empty() or lk_token.is_empty():
		return {
			"ok": false,
			"backend": "livekit",
			"reason": "missing livekit_url/token",
		}
	return {"ok": true, "backend": "livekit", "reason": ""}

func _voice_log(message: String) -> void:
	if DEBUG_VOICE_LOGS:
		var line := "[VoiceDebug] " + message
		print(line)
		var f := FileAccess.open(VOICE_LOG_PATH, FileAccess.READ_WRITE)
		if f:
			f.seek_end()
			f.store_line(line)
			f.close()
