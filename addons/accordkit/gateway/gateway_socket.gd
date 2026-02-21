class_name GatewaySocket extends Node

# Lifecycle
signal connected
signal disconnected(code: int, reason: String)
signal reconnecting(attempt: int, max_attempts: int)
signal ready_received(data: Dictionary)
signal resumed

# Spaces
signal space_create(space: AccordSpace)
signal space_update(space: AccordSpace)
signal space_delete(data: Dictionary)

# Channels
signal channel_create(channel: AccordChannel)
signal channel_update(channel: AccordChannel)
signal channel_delete(channel: AccordChannel)
signal channel_pins_update(data: Dictionary)

# Members
signal member_join(member: AccordMember)
signal member_leave(data: Dictionary)
signal member_update(member: AccordMember)
signal member_chunk(data: Dictionary)

# Roles
signal role_create(data: Dictionary)
signal role_update(data: Dictionary)
signal role_delete(data: Dictionary)

# Messages
signal message_create(message: AccordMessage)
signal message_update(message: AccordMessage)
signal message_delete(data: Dictionary)
signal message_delete_bulk(data: Dictionary)

# Reactions
signal reaction_add(data: Dictionary)
signal reaction_remove(data: Dictionary)
signal reaction_clear(data: Dictionary)
signal reaction_clear_emoji(data: Dictionary)

# Presence
signal presence_update(presence: AccordPresence)
signal typing_start(data: Dictionary)

# User
signal user_update(user: AccordUser)

# Voice
signal voice_state_update(state: AccordVoiceState)
signal voice_server_update(info: AccordVoiceServerUpdate)
signal voice_signal(data: Dictionary)

# Bans
signal ban_create(data: Dictionary)
signal ban_delete(data: Dictionary)

# Invites
signal invite_create(invite: AccordInvite)
signal invite_delete(data: Dictionary)

# Interactions
signal interaction_create(interaction: AccordInteraction)

# Emojis
signal emoji_create(data: Dictionary)
signal emoji_update(data: Dictionary)
signal emoji_delete(data: Dictionary)

# Soundboard
signal soundboard_create(sound: AccordSound)
signal soundboard_update(sound: AccordSound)
signal soundboard_delete(data: Dictionary)
signal soundboard_play(data: Dictionary)

# Raw event for anything not explicitly handled
signal raw_event(event_type: String, data: Dictionary)

enum State { DISCONNECTED, CONNECTING, CONNECTED, RESUMING }

var token: String = ""
var token_type: String = "Bot"
var intents: Array = []

var _socket: WebSocketPeer = WebSocketPeer.new()
var _state: State = State.DISCONNECTED
var _session_id: String = ""
var _sequence: int = 0
var _heartbeat_interval_ms: int = 45000
var _heartbeat_timer: float = 0.0
var _heartbeat_ack_received: bool = true
var _gateway_url: String = ""
var _reconnect_attempts: int = 0
var _max_reconnect_attempts: int = 10
var _reconnect_cancelled: bool = false
var _resume_pending: bool = false
var _config: AccordConfig


func setup(
	config: AccordConfig, tkn: String,
	tkn_type: String = "Bot", intent_list: Array = [],
) -> void:
	_config = config
	token = tkn
	token_type = tkn_type
	intents = intent_list if intent_list.size() > 0 else GatewayIntents.default()


func connect_to_gateway(url: String = "") -> void:
	if _state != State.DISCONNECTED:
		return
	_gateway_url = url if url != "" else _config.gateway_connect_url()
	_state = State.CONNECTING
	_reconnect_attempts = 0
	_reconnect_cancelled = false
	var err := _socket.connect_to_url(_gateway_url)
	if err != OK:
		_state = State.DISCONNECTED
		push_error("AccordKit: Failed to connect to gateway: " + str(err))
	set_process(true)


func disconnect_from_gateway(code: int = 1000, reason: String = "client disconnect") -> void:
	_reconnect_cancelled = true
	if _state == State.DISCONNECTED:
		return
	_socket.close(code, reason)
	_state = State.DISCONNECTED
	set_process(false)
	disconnected.emit(code, reason)


func _ready() -> void:
	set_process(false)

func _exit_tree() -> void:
	if _state != State.DISCONNECTED:
		_socket.close(1001, "going away")
		_state = State.DISCONNECTED
		set_process(false)


func _process(delta: float) -> void:
	_socket.poll()

	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _state == State.CONNECTING:
			_state = State.CONNECTED
			connected.emit()

		# Heartbeat
		_heartbeat_timer += delta * 1000.0
		if _heartbeat_timer >= _heartbeat_interval_ms:
			_send_heartbeat()
			_heartbeat_timer = 0.0

		# Read messages
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			var text := packet.get_string_from_utf8()
			_handle_message(text)

	elif state == WebSocketPeer.STATE_CLOSING:
		pass

	elif state == WebSocketPeer.STATE_CLOSED:
		var code := _socket.get_close_code()
		var reason := _socket.get_close_reason()
		# If a RESUME was sent but the connection dropped before
		# receiving resumed/ready, the session is dead (e.g. server
		# restarted).  Clear session so the next attempt uses IDENTIFY.
		if _resume_pending:
			_session_id = ""
			_sequence = 0
			_resume_pending = false
		_state = State.DISCONNECTED
		set_process(false)
		disconnected.emit(code, reason)
		if _should_reconnect(code):
			_attempt_reconnect()


func _send(payload: Dictionary) -> void:
	var text := JSON.stringify(payload)
	_socket.send_text(text)


func _send_heartbeat() -> void:
	if not _heartbeat_ack_received:
		push_warning("AccordKit: Heartbeat ACK not received, reconnecting")
		_socket.close(4000, "heartbeat timeout")
		return
	_heartbeat_ack_received = false
	_send({"op": GatewayOpcodes.HEARTBEAT, "data": _sequence})


func _send_identify() -> void:
	_send({
		"op": GatewayOpcodes.IDENTIFY,
		"data": {
			"token": token_type + " " + token,
			"intents": intents,
			"properties": {
				"os": OS.get_name().to_lower(),
				"client": "AccordKit",
				"version": AccordConfig.CLIENT_VERSION,
			},
		},
	})


func _send_resume() -> void:
	_state = State.RESUMING
	_resume_pending = true
	_send({
		"op": GatewayOpcodes.RESUME,
		"data": {
			"token": token_type + " " + token,
			"session_id": _session_id,
			"seq": _sequence,
		},
	})


func _handle_message(text: String) -> void:
	var parsed = JSON.parse_string(text)
	if parsed == null or not parsed is Dictionary:
		return

	var op: int = parsed.get("op", -1)
	var data = parsed.get("data", {})
	var seq = parsed.get("seq", null)
	var event_type: String = parsed.get("type", "")

	if seq != null and seq is float:
		_sequence = int(seq)

	match op:
		GatewayOpcodes.HELLO:
			_heartbeat_interval_ms = int(data.get("heartbeat_interval", 45000))
			_heartbeat_timer = 0.0
			_heartbeat_ack_received = true
			if _session_id != "" and _state == State.RESUMING:
				_send_resume()
			else:
				_send_identify()

		GatewayOpcodes.HEARTBEAT_ACK:
			_heartbeat_ack_received = true

		GatewayOpcodes.HEARTBEAT:
			_send_heartbeat()

		GatewayOpcodes.RECONNECT:
			_socket.close(4000, "server requested reconnect")

		GatewayOpcodes.INVALID_SESSION:
			var resumable: bool = data if data is bool else false
			if not resumable:
				_session_id = ""
				_sequence = 0
			# Stop if we've exhausted reconnect attempts
			if _reconnect_attempts >= _max_reconnect_attempts:
				_state = State.DISCONNECTED
				set_process(false)
				_socket.close(1000, "max reconnect attempts")
				disconnected.emit(4004, "session invalid after max attempts")
				return
			# Wait 1-5 seconds then reconnect
			if not is_inside_tree():
				return
			await get_tree().create_timer(randf_range(1.0, 5.0)).timeout
			if not is_inside_tree():
				return
			_attempt_reconnect()

		GatewayOpcodes.EVENT:
			_dispatch_event(event_type, data if data is Dictionary else {})


func _dispatch_event(event_type: String, data: Dictionary) -> void:
	match event_type:
		"ready":
			_session_id = data.get("session_id", "")
			_reconnect_attempts = 0
			_resume_pending = false
			ready_received.emit(data)
		"resumed":
			_reconnect_attempts = 0
			_resume_pending = false
			resumed.emit()
		"space.create":
			space_create.emit(AccordSpace.from_dict(data))
		"space.update":
			space_update.emit(AccordSpace.from_dict(data))
		"space.delete":
			space_delete.emit(data)
		"channel.create":
			channel_create.emit(AccordChannel.from_dict(data))
		"channel.update":
			channel_update.emit(AccordChannel.from_dict(data))
		"channel.delete":
			channel_delete.emit(AccordChannel.from_dict(data))
		"channel.pins_update":
			channel_pins_update.emit(data)
		"member.join":
			member_join.emit(AccordMember.from_dict(data))
		"member.leave":
			member_leave.emit(data)
		"member.update":
			member_update.emit(AccordMember.from_dict(data))
		"member.chunk":
			member_chunk.emit(data)
		"role.create":
			role_create.emit(data)
		"role.update":
			role_update.emit(data)
		"role.delete":
			role_delete.emit(data)
		"message.create":
			message_create.emit(AccordMessage.from_dict(data))
		"message.update":
			message_update.emit(AccordMessage.from_dict(data))
		"message.delete":
			message_delete.emit(data)
		"message.delete_bulk":
			message_delete_bulk.emit(data)
		"reaction.add":
			reaction_add.emit(data)
		"reaction.remove":
			reaction_remove.emit(data)
		"reaction.clear":
			reaction_clear.emit(data)
		"reaction.clear_emoji":
			reaction_clear_emoji.emit(data)
		"presence.update":
			presence_update.emit(AccordPresence.from_dict(data))
		"typing.start":
			typing_start.emit(data)
		"user.update":
			user_update.emit(AccordUser.from_dict(data))
		"voice.state_update":
			voice_state_update.emit(AccordVoiceState.from_dict(data))
		"voice.server_update":
			voice_server_update.emit(AccordVoiceServerUpdate.from_dict(data))
		"voice.signal":
			voice_signal.emit(data)
		"ban.create":
			ban_create.emit(data)
		"ban.delete":
			ban_delete.emit(data)
		"invite.create":
			invite_create.emit(AccordInvite.from_dict(data))
		"invite.delete":
			invite_delete.emit(data)
		"interaction.create":
			interaction_create.emit(AccordInteraction.from_dict(data))
		"emoji.create":
			emoji_create.emit(data)
		"emoji.update":
			emoji_update.emit(data)
		"emoji.delete":
			emoji_delete.emit(data)
		"soundboard.create":
			soundboard_create.emit(AccordSound.from_dict(data))
		"soundboard.update":
			soundboard_update.emit(AccordSound.from_dict(data))
		"soundboard.delete":
			soundboard_delete.emit(data)
		"soundboard.play":
			soundboard_play.emit(data)

	raw_event.emit(event_type, data)


func _should_reconnect(code: int) -> bool:
	# Non-reconnectable close codes
	var fatal_codes := [4003, 4004, 4012, 4013, 4014]
	if code in fatal_codes:
		return false
	return _reconnect_attempts < _max_reconnect_attempts


func _attempt_reconnect() -> void:
	_reconnect_attempts += 1
	reconnecting.emit(_reconnect_attempts, _max_reconnect_attempts)
	# Exponential backoff with jitter: base * 2^attempt + random jitter
	var base_delay := 1.0
	var delay := base_delay * pow(2.0, min(_reconnect_attempts - 1, 5)) + randf_range(0.0, 1.0)
	if not is_inside_tree():
		return
	await get_tree().create_timer(delay).timeout
	if not is_inside_tree() or _reconnect_cancelled:
		return

	_socket = WebSocketPeer.new()
	_state = State.CONNECTING
	if _session_id != "":
		_state = State.RESUMING
	var err := _socket.connect_to_url(_gateway_url)
	if err != OK:
		_state = State.DISCONNECTED
		push_error("AccordKit: Reconnect failed: " + str(err))
	else:
		set_process(true)


func update_presence(status: String, activity: Dictionary = {}) -> void:
	var data := {"status": status}
	if activity.size() > 0:
		data["activity"] = activity
	_send({"op": GatewayOpcodes.PRESENCE_UPDATE, "data": data})


func update_voice_state(
	space_id: String, channel_id,
	self_mute: bool = false, self_deaf: bool = false,
	self_video: bool = false, self_stream: bool = false,
) -> void:
	_send({
		"op": GatewayOpcodes.VOICE_STATE_UPDATE,
		"data": {
			"space_id": space_id,
			"channel_id": channel_id,
			"self_mute": self_mute,
			"self_deaf": self_deaf,
			"self_video": self_video,
			"self_stream": self_stream,
		},
	})


func request_members(space_id: String, query: String = "", limit: int = 0) -> void:
	_send({
		"op": GatewayOpcodes.REQUEST_MEMBERS,
		"data": {
			"space_id": space_id,
			"query": query,
			"limit": limit,
		},
	})


func send_voice_signal(
	space_id: String, channel_id: String,
	signal_type: String, payload: Dictionary,
) -> void:
	_send({
		"op": GatewayOpcodes.VOICE_SIGNAL,
		"data": {
			"space_id": space_id,
			"channel_id": channel_id,
			"type": signal_type,
			"payload": payload,
		},
	})
