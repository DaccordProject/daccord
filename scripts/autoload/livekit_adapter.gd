class_name LiveKitAdapter
extends Node

## Wraps godot-livekit's LiveKitRoom and exposes the signal surface
## that client.gd / client_voice.gd expect.  Manages local audio/video
## tracks, remote audio playback, and speaking-level detection.

# --- Signals ---
signal session_state_changed(state: int)
signal peer_joined(user_id: String)
signal peer_left(user_id: String)
signal track_received(user_id: String, stream: RefCounted)
signal audio_level_changed(user_id: String, level: float)

# --- State enum (matches what ClientVoice expects) ---
enum State {
	DISCONNECTED = 0,
	CONNECTING = 1,
	CONNECTED = 2,
	RECONNECTING = 3,
	FAILED = 4,
}

# --- Internal state ---
var _room: LiveKitRoom
var _state: int = State.DISCONNECTED
var _muted: bool = false
var _deafened: bool = false

# Local tracks
var _local_audio_source: RefCounted  # LiveKitAudioSource
var _local_audio_track: RefCounted   # LiveKitLocalAudioTrack
var _local_audio_pub: RefCounted     # LiveKitLocalTrackPublication
var _local_video_source: RefCounted  # LiveKitVideoSource
var _local_video_track: RefCounted   # LiveKitLocalVideoTrack
var _local_video_pub: RefCounted     # LiveKitLocalTrackPublication
var _local_screen_source: RefCounted # LiveKitVideoSource
var _local_screen_track: RefCounted  # LiveKitLocalVideoTrack
var _local_screen_pub: RefCounted    # LiveKitLocalTrackPublication

# Remote playback: identity -> { stream, player, playback, generator }
var _remote_audio: Dictionary = {}
# Remote video: identity -> LiveKitVideoStream
var _remote_video: Dictionary = {}

# Participant identity -> user_id mapping
var _identity_to_user: Dictionary = {}

# --- Microphone capture via AudioEffectCapture ---
var _mic_record: AudioStreamPlayer
var _mic_effect: AudioEffectCapture
var _mic_bus_idx: int = -1

# --- Public API ---

func connect_to_room(url: String, token: String) -> void:
	if _room != null:
		disconnect_voice()
	_state = State.CONNECTING
	session_state_changed.emit(State.CONNECTING)
	_room = LiveKitRoom.new()
	_room.connected.connect(_on_connected)
	_room.disconnected.connect(_on_disconnected)
	_room.reconnecting.connect(_on_reconnecting)
	_room.reconnected.connect(_on_reconnected)
	_room.participant_connected.connect(_on_participant_connected)
	_room.participant_disconnected.connect(_on_participant_disconnected)
	_room.track_subscribed.connect(_on_track_subscribed)
	_room.track_unsubscribed.connect(_on_track_unsubscribed)
	_room.track_muted.connect(_on_track_muted)
	_room.track_unmuted.connect(_on_track_unmuted)
	_room.connect_to_room(url, token, {"auto_reconnect": false})

func disconnect_voice() -> void:
	# Skip the blocking unpublish_track() SDK calls — destroying the room
	# handles all track teardown.  Just drop local references.
	_local_audio_pub = null
	_local_audio_track = null
	_local_audio_source = null
	_local_video_pub = null
	_local_video_track = null
	_local_video_source = null
	_local_screen_pub = null
	_local_screen_track = null
	_local_screen_source = null
	_cleanup_all_remote()
	_cleanup_mic_capture()
	if _room != null:
		_room.disconnect_from_room()
		_room = null
	_state = State.DISCONNECTED
	session_state_changed.emit(State.DISCONNECTED)

func set_muted(muted: bool) -> void:
	_muted = muted
	if _local_audio_track != null:
		if muted:
			_local_audio_track.mute()
		else:
			_local_audio_track.unmute()

func set_deafened(deafened: bool) -> void:
	_deafened = deafened
	for identity in _remote_audio:
		var entry: Dictionary = _remote_audio[identity]
		var player: AudioStreamPlayer = entry.get("player")
		if player != null:
			player.volume_db = -80.0 if deafened else 0.0

func is_muted() -> bool:
	return _muted

func is_deafened() -> bool:
	return _deafened

func get_session_state() -> int:
	return _state

func publish_camera(res: Vector2i, _fps: int) -> RefCounted:
	if _room == null:
		return null
	_cleanup_local_video()
	_local_video_source = LiveKitVideoSource.create(res.x, res.y)
	_local_video_track = LiveKitLocalVideoTrack.create(
		"camera", _local_video_source
	)
	var local_part: LiveKitLocalParticipant = _room.get_local_participant()
	if local_part == null:
		return null
	_local_video_pub = local_part.publish_track(
		_local_video_track, {"source": LiveKitTrack.SOURCE_CAMERA}
	)
	# Return a LiveKitVideoStream for local preview
	var stream: LiveKitVideoStream = LiveKitVideoStream.from_track(
		_local_video_track
	)
	return stream

func unpublish_camera() -> void:
	_cleanup_local_video()

func publish_screen() -> RefCounted:
	if _room == null:
		return null
	_cleanup_local_screen()
	# Use a reasonable default resolution for screen share
	_local_screen_source = LiveKitVideoSource.create(1920, 1080)
	_local_screen_track = LiveKitLocalVideoTrack.create(
		"screen", _local_screen_source
	)
	var local_part: LiveKitLocalParticipant = _room.get_local_participant()
	if local_part == null:
		return null
	_local_screen_pub = local_part.publish_track(
		_local_screen_track, {"source": LiveKitTrack.SOURCE_SCREENSHARE}
	)
	var stream: LiveKitVideoStream = LiveKitVideoStream.from_track(
		_local_screen_track
	)
	return stream

func unpublish_screen() -> void:
	_cleanup_local_screen()

# --- Process loop: poll remote streams, compute audio levels ---

func _process(_delta: float) -> void:
	if _room == null:
		return
	# Drain the thread-safe event queue (connection results, participant
	# joins/leaves, track subscriptions, etc.) on the main thread.
	_room.poll_events()
	# Poll remote video streams
	for identity in _remote_video:
		var stream: LiveKitVideoStream = _remote_video[identity]
		if stream != null:
			stream.poll()
	# Poll remote audio streams and compute speaking levels
	for identity in _remote_audio:
		var entry: Dictionary = _remote_audio[identity]
		var stream: LiveKitAudioStream = entry.get("stream")
		var playback: AudioStreamGeneratorPlayback = entry.get("playback")
		if stream != null and playback != null:
			stream.poll(playback)
		# Compute audio level from generator playback buffer
		var player: AudioStreamPlayer = entry.get("player")
		var level: float = 0.0
		if player != null and player.playing:
			level = _estimate_audio_level(player)
		var uid: String = _identity_to_user.get(identity, identity)
		if level > 0.001:
			audio_level_changed.emit(uid, level)
	# Local mic level via AudioEffectCapture
	if _mic_effect != null and _local_audio_track != null and not _muted:
		var frames_avail: int = _mic_effect.get_frames_available()
		if frames_avail > 0:
			var buf: PackedVector2Array = _mic_effect.get_buffer(
				mini(frames_avail, 480)
			)
			var rms: float = 0.0
			for frame in buf:
				var sample: float = (frame.x + frame.y) * 0.5
				rms += sample * sample
			if buf.size() > 0:
				rms = sqrt(rms / buf.size())
			if rms > 0.001:
				audio_level_changed.emit("@local", rms)

# --- Room signal handlers ---

func _on_connected() -> void:
	_state = State.CONNECTED
	session_state_changed.emit(State.CONNECTED)
	# Publish local microphone audio
	_publish_local_audio()

func _on_disconnected() -> void:
	_state = State.DISCONNECTED
	session_state_changed.emit(State.DISCONNECTED)

func _on_reconnecting() -> void:
	_state = State.RECONNECTING
	session_state_changed.emit(State.RECONNECTING)

func _on_reconnected() -> void:
	_state = State.CONNECTED
	session_state_changed.emit(State.CONNECTED)

func _on_participant_connected(participant: LiveKitRemoteParticipant) -> void:
	var identity: String = participant.get_identity()
	# For now, identity == user_id (server sets identity to user ID)
	_identity_to_user[identity] = identity
	peer_joined.emit(identity)

func _on_participant_disconnected(participant: LiveKitRemoteParticipant) -> void:
	var identity: String = participant.get_identity()
	var uid: String = _identity_to_user.get(identity, identity)
	_cleanup_remote_audio(identity)
	_cleanup_remote_video(identity)
	_identity_to_user.erase(identity)
	peer_left.emit(uid)

func _on_track_subscribed(
	track: LiveKitTrack,
	_publication: LiveKitRemoteTrackPublication,
	participant: LiveKitRemoteParticipant,
) -> void:
	var identity: String = participant.get_identity()
	var uid: String = _identity_to_user.get(identity, identity)
	var kind: int = track.get_kind()
	if kind == LiveKitTrack.KIND_VIDEO:
		var stream: LiveKitVideoStream = LiveKitVideoStream.from_track(track)
		_remote_video[identity] = stream
		track_received.emit(uid, stream)
	elif kind == LiveKitTrack.KIND_AUDIO:
		_setup_remote_audio(identity, track)

func _on_track_unsubscribed(
	track: LiveKitTrack,
	_publication: LiveKitRemoteTrackPublication,
	participant: LiveKitRemoteParticipant,
) -> void:
	var identity: String = participant.get_identity()
	var kind: int = track.get_kind()
	if kind == LiveKitTrack.KIND_VIDEO:
		_cleanup_remote_video(identity)
	elif kind == LiveKitTrack.KIND_AUDIO:
		_cleanup_remote_audio(identity)

func _on_track_muted(
	_participant: LiveKitParticipant,
	_publication: LiveKitTrackPublication,
) -> void:
	pass # UI picks up mute state from voice_state_update gateway events

func _on_track_unmuted(
	_participant: LiveKitParticipant,
	_publication: LiveKitTrackPublication,
) -> void:
	pass

# --- Local audio publishing ---

func _publish_local_audio() -> void:
	if _room == null:
		return
	_local_audio_source = LiveKitAudioSource.create(48000, 1, 200)
	_local_audio_track = LiveKitLocalAudioTrack.create(
		"microphone", _local_audio_source
	)
	if _muted:
		_local_audio_track.mute()
	var local_part: LiveKitLocalParticipant = _room.get_local_participant()
	if local_part == null:
		return
	_local_audio_pub = local_part.publish_track(
		_local_audio_track, {"source": LiveKitTrack.SOURCE_MICROPHONE}
	)
	_setup_mic_capture()

func _setup_mic_capture() -> void:
	# Create an audio bus for mic capture with an AudioEffectCapture
	_mic_bus_idx = AudioServer.bus_count
	AudioServer.add_bus(_mic_bus_idx)
	AudioServer.set_bus_name(_mic_bus_idx, "MicCapture")
	AudioServer.set_bus_mute(_mic_bus_idx, true) # Don't play mic audio locally
	var effect := AudioEffectCapture.new()
	AudioServer.add_bus_effect(_mic_bus_idx, effect)
	_mic_effect = effect
	# Create a record player on this bus
	_mic_record = AudioStreamPlayer.new()
	_mic_record.stream = AudioStreamMicrophone.new()
	_mic_record.bus = "MicCapture"
	add_child(_mic_record)
	_mic_record.play()

func _cleanup_mic_capture() -> void:
	if _mic_record != null:
		_mic_record.stop()
		_mic_record.queue_free()
		_mic_record = null
	_mic_effect = null
	if _mic_bus_idx >= 0 and _mic_bus_idx < AudioServer.bus_count:
		AudioServer.remove_bus(_mic_bus_idx)
		_mic_bus_idx = -1

# --- Remote audio playback ---

func _setup_remote_audio(identity: String, track: LiveKitTrack) -> void:
	_cleanup_remote_audio(identity)
	var stream: LiveKitAudioStream = LiveKitAudioStream.from_track(track)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = stream.get_sample_rate()
	generator.buffer_length = 0.1
	var player := AudioStreamPlayer.new()
	player.stream = generator
	if _deafened:
		player.volume_db = -80.0
	add_child(player)
	player.play()
	var playback: AudioStreamGeneratorPlayback = player.get_stream_playback()
	_remote_audio[identity] = {
		"stream": stream,
		"player": player,
		"playback": playback,
		"generator": generator,
	}

func _cleanup_remote_audio(identity: String) -> void:
	if not _remote_audio.has(identity):
		return
	var entry: Dictionary = _remote_audio[identity]
	var stream: LiveKitAudioStream = entry.get("stream")
	if stream != null:
		stream.close()
	var player: AudioStreamPlayer = entry.get("player")
	if player != null:
		player.stop()
		player.queue_free()
	_remote_audio.erase(identity)

func _cleanup_remote_video(identity: String) -> void:
	if not _remote_video.has(identity):
		return
	var stream: LiveKitVideoStream = _remote_video[identity]
	if stream != null:
		stream.close()
	_remote_video.erase(identity)

func _cleanup_all_remote() -> void:
	for identity in _remote_audio.keys():
		_cleanup_remote_audio(identity)
	for identity in _remote_video.keys():
		_cleanup_remote_video(identity)
	_identity_to_user.clear()

# --- Local track cleanup ---

func _cleanup_local_audio() -> void:
	if _local_audio_pub != null and _room != null:
		var local_part: LiveKitLocalParticipant = _room.get_local_participant()
		if local_part != null and _local_audio_track != null:
			local_part.unpublish_track(_local_audio_track.get_sid())
	_local_audio_pub = null
	_local_audio_track = null
	_local_audio_source = null

func _cleanup_local_video() -> void:
	if _local_video_pub != null and _room != null:
		var local_part: LiveKitLocalParticipant = _room.get_local_participant()
		if local_part != null and _local_video_track != null:
			local_part.unpublish_track(_local_video_track.get_sid())
	_local_video_pub = null
	_local_video_track = null
	_local_video_source = null

func _cleanup_local_screen() -> void:
	if _local_screen_pub != null and _room != null:
		var local_part: LiveKitLocalParticipant = _room.get_local_participant()
		if local_part != null and _local_screen_track != null:
			local_part.unpublish_track(_local_screen_track.get_sid())
	_local_screen_pub = null
	_local_screen_track = null
	_local_screen_source = null

# --- Audio level estimation ---

func _estimate_audio_level(player: AudioStreamPlayer) -> float:
	# Use Godot's built-in VU meter via AudioServer bus peak
	var bus_idx: int = AudioServer.get_bus_index(player.bus)
	if bus_idx < 0:
		return 0.0
	var peak: float = AudioServer.get_bus_peak_volume_left_db(bus_idx, 0)
	# Convert from dB to linear (0..1 range, clamped)
	if peak < -60.0:
		return 0.0
	return clampf(db_to_linear(peak), 0.0, 1.0)

func _exit_tree() -> void:
	disconnect_voice()
