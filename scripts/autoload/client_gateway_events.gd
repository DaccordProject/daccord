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
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.bans_updated.emit(space_id)

func on_ban_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.bans_updated.emit(space_id)

func on_invite_create(_invite: AccordInvite, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.invites_updated.emit(space_id)

func on_invite_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.invites_updated.emit(space_id)

func on_soundboard_create(_sound: AccordSound, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.soundboard_updated.emit(space_id)

func on_soundboard_update(_sound: AccordSound, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.soundboard_updated.emit(space_id)

func on_soundboard_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.soundboard_updated.emit(space_id)

func on_soundboard_play(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	var sound_data: Dictionary = data.get("sound", {})
	var sound_id: String = str(data.get("sound_id", sound_data.get("id", "")))
	var user_id: String = str(data.get("user_id", ""))
	AppState.soundboard_played.emit(space_id, sound_id, user_id)

func on_emoji_create(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.emojis_updated.emit(space_id)

func on_emoji_update(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.emojis_updated.emit(space_id)

func on_emoji_delete(_data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var space_id: String = _c._connections[conn_index]["space_id"]
	AppState.emojis_updated.emit(space_id)

func on_channel_mute_create(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	if not channel_id.is_empty():
		_c._muted_channels[channel_id] = true
		AppState.channel_mutes_updated.emit()

func on_channel_mute_delete(data: Dictionary) -> void:
	var channel_id: String = str(data.get("channel_id", ""))
	if not channel_id.is_empty():
		_c._muted_channels.erase(channel_id)
		AppState.channel_mutes_updated.emit()

func on_interaction_create(
	_interaction: AccordInteraction, _conn_index: int,
) -> void:
	pass # No interaction UI; wired to prevent silent drop

# --- Voice events ---

func on_voice_state_update(state: AccordVoiceState, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var conn: Dictionary = _c._connections[conn_index]
	var cdn_url: String = conn.get("cdn_url", "")
	# Ensure user is cached before building the voice state dict
	if not _c._user_cache.has(state.user_id):
		var client: AccordClient = conn["client"]
		if client != null:
			var user_result: RestResult = await client.users.fetch(state.user_id)
			if user_result.ok:
				_c._user_cache[state.user_id] = ClientModels.user_to_dict(
					user_result.data,
					ClientModels.UserStatus.OFFLINE,
					cdn_url
				)
	# Ensure the user is in the member cache for this space
	var space_id: String = conn["space_id"]
	if not space_id.is_empty() and _c._user_cache.has(state.user_id):
		var member_idx: int = _c._member_index_for(space_id, state.user_id)
		if member_idx == -1:
			var user_dict: Dictionary = _c._user_cache[state.user_id].duplicate()
			user_dict["roles"] = []
			user_dict["joined_at"] = ""
			user_dict["mute"] = state.mute
			user_dict["deaf"] = state.deaf
			user_dict["nickname"] = ""
			user_dict["timed_out_until"] = ""
			if not _c._member_cache.has(space_id):
				_c._member_cache[space_id] = []
			_c._member_cache[space_id].append(user_dict)
			if not _c._member_id_index.has(space_id):
				_c._member_id_index[space_id] = {}
			_c._member_id_index[space_id][state.user_id] = _c._member_cache[space_id].size() - 1
			AppState.member_joined.emit(space_id, user_dict)
			AppState.members_updated.emit(space_id)
	var state_dict := ClientModels.voice_state_to_dict(state, _c._user_cache)
	var new_channel: String = state_dict["channel_id"]
	var user_id: String = state.user_id
	var my_id: String = _c.current_user.get("id", "")

	# If we are not in voice and have no backend credentials, ignore
	# self updates that would otherwise show us as connected.
	if user_id == my_id and AppState.voice_channel_id.is_empty() \
			and _c._voice_server_info.is_empty() \
			and not new_channel.is_empty():
		_c.voice._voice_log(
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
	_c.voice._voice_log(
		"voice_server_update livekit=%s" % [
			str(info.livekit_url)
		]
	)
	# If we're already in a voice channel, (re)connect the backend with
	# the new credentials.  _connect_voice_backend() handles tearing down
	# any existing room, so this works whether the session is still
	# CONNECTED (gateway event arrived before LiveKit disconnected) or
	# already DISCONNECTED (the old race-condition path).
	if not AppState.voice_channel_id.is_empty() and _c._voice_session != null:
		_c.voice._voice_log("voice_server_update connecting backend now")
		_c.voice._connect_voice_backend(info)

func on_voice_signal(_data: Dictionary, _conn_index: int) -> void:
	pass # LiveKit handles signaling internally

# --- Relationship events ---

func on_relationship_add(rel: AccordRelationship, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var cdn: String = _c._connections[conn_index].get("cdn_url", "")
	var d: Dictionary = ClientModels.relationship_to_dict(rel, cdn)
	var user_id: String = d["user"].get("id", "")
	var key: String = str(conn_index) + ":" + user_id
	_c._relationship_cache[key] = d
	AppState.relationships_updated.emit()
	if rel.type == 3:  # PENDING_INCOMING
		AppState.friend_request_received.emit(user_id)

func on_relationship_update(rel: AccordRelationship, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var cdn: String = _c._connections[conn_index].get("cdn_url", "")
	var d: Dictionary = ClientModels.relationship_to_dict(rel, cdn)
	var key: String = str(conn_index) + ":" + d["user"].get("id", "")
	_c._relationship_cache[key] = d
	AppState.relationships_updated.emit()

func on_relationship_remove(data: Dictionary, conn_index: int) -> void:
	if conn_index >= _c._connections.size() or _c._connections[conn_index] == null:
		return
	var user_id: String = str(data.get("user_id", ""))
	if user_id.is_empty():
		return
	var key: String = str(conn_index) + ":" + user_id
	_c._relationship_cache.erase(key)
	AppState.relationships_updated.emit()
