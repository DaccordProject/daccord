class_name ClientGatewayEvents
extends RefCounted

## Handles admin, entity, and voice gateway events for ClientGateway.
## Groups simple event handlers that follow the same conn_index validation pattern.

var _c: Node # Client autoload

func _init(client_node: Node) -> void:
	_c = client_node

# --- Admin / entity events ---

func on_ban_create(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.bans_updated.emit(guild_id)

func on_ban_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.bans_updated.emit(guild_id)

func on_invite_create(_invite: AccordInvite, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.invites_updated.emit(guild_id)

func on_invite_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.invites_updated.emit(guild_id)

func on_soundboard_create(_sound: AccordSound, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.soundboard_updated.emit(guild_id)

func on_soundboard_update(_sound: AccordSound, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.soundboard_updated.emit(guild_id)

func on_soundboard_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.soundboard_updated.emit(guild_id)

func on_soundboard_play(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	var sound_id: String = str(data.get("sound_id", data.get("id", "")))
	var user_id: String = str(data.get("user_id", ""))
	AppState.soundboard_played.emit(guild_id, sound_id, user_id)

func on_emoji_create(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.emojis_updated.emit(guild_id)

func on_emoji_update(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.emojis_updated.emit(guild_id)

func on_emoji_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var guild_id: String = _c._connections[conn_index]["guild_id"]
	AppState.emojis_updated.emit(guild_id)

func on_interaction_create(
	_interaction: AccordInteraction, _conn_index: int,
) -> void:
	pass # No interaction UI; wired to prevent silent drop

# --- Voice events ---

func on_voice_state_update(state: AccordVoiceState, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var state_dict := ClientModels.voice_state_to_dict(state, _c._user_cache)
	var new_channel: String = state_dict["channel_id"]
	var user_id: String = state.user_id
	var my_id: String = _c.current_user.get("id", "")

	# If we are not in voice and have no backend credentials, ignore
	# self updates that would otherwise show us as connected.
	if user_id == my_id and AppState.voice_channel_id.is_empty() \
			and _c._voice_server_info.is_empty() \
			and not new_channel.is_empty():
		if _c.has_method("_voice_log"):
			_c._voice_log(
				"ignore self voice_state_update without backend"
			)
		return

	# Remove user from any previous channel in the cache
	var old_channel := ""
	for cid in _c._voice_state_cache:
		var states: Array = _c._voice_state_cache[cid]
		for i in states.size():
			if states[i].get("user_id", "") == user_id:
				old_channel = cid
				states.remove_at(i)
				# Update voice_users count in channel cache
				if _c._channel_cache.has(cid):
					_c._channel_cache[cid]["voice_users"] = states.size()
				if cid != new_channel:
					AppState.voice_state_updated.emit(cid)
				break

	# Add user to new channel (if not null/empty)
	if not new_channel.is_empty():
		if not _c._voice_state_cache.has(new_channel):
			_c._voice_state_cache[new_channel] = []
		_c._voice_state_cache[new_channel].append(state_dict)
		if _c._channel_cache.has(new_channel):
			_c._channel_cache[new_channel]["voice_users"] = _c._voice_state_cache[new_channel].size()
		AppState.voice_state_updated.emit(new_channel)

	# Play peer join/leave sound (guard for headless mode)
	if SoundManager != null:
		SoundManager.play_for_voice_state(user_id, new_channel, old_channel)

	# Detect force-disconnect: if our user's channel_id becomes empty
	if user_id == my_id and new_channel.is_empty() and not AppState.voice_channel_id.is_empty():
		AppState.leave_voice()

func on_voice_server_update(info: AccordVoiceServerUpdate, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	_c._voice_server_info = info.to_dict()
	if _c.has_method("_voice_log"):
		_c._voice_log(
			"voice_server_update livekit=%s" % [
				str(info.livekit_url)
			]
		)
	# If we're already in a voice channel and disconnected,
	# connect the backend now (server may send update asynchronously).
	if not AppState.voice_channel_id.is_empty() and _c._voice_session != null:
		var state: int = _c._voice_session.get_session_state()
		if state == LiveKitAdapter.State.DISCONNECTED:
			if _c.has_method("_voice_log"):
				_c._voice_log("voice_server_update connecting backend now")
			_c.voice._connect_voice_backend(info)

func on_voice_signal(_data: Dictionary, _conn_index: int) -> void:
	pass # LiveKit handles signaling internally
