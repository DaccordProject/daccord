class_name WebVoiceSession
extends Node

## Web-only voice session using livekit-client.js via JavaScriptBridge.
## Provides the same signal/API surface as LiveKitAdapter for web exports.
## On non-web builds all methods are no-ops (JavaScriptBridge unavailable).

# --- Signals (mirror LiveKitAdapter) ---
signal session_state_changed(state: int)
signal peer_joined(user_id: String)
signal peer_left(user_id: String)
signal track_received(user_id: String, stream)
signal track_removed(user_id: String)
signal audio_level_changed(user_id: String, level: float)

# --- State enum (aliases ClientModels.VoiceSessionState for local use) ---
const VOICE_STATE := ClientModels.VoiceSessionState

const CONNECT_TIMEOUT_SEC := 15.0

var _room  # JavaScriptObject (LivekitClient.Room) or null
var _state: int = VOICE_STATE.DISCONNECTED
var _muted: bool = false
var _deafened: bool = false
var _is_web: bool = false
var _connect_timer: Timer

# Remote video: participant identity -> JavaScriptObject (MediaStreamTrack)
var _remote_video: Dictionary = {}

# Participant identity -> user_id mapping
var _identity_to_user: Dictionary = {}

# JS callback objects — kept alive as vars so the GC doesn't free them
var _cb_connected
var _cb_disconnected
var _cb_reconnecting
var _cb_reconnected
var _cb_participant_connected
var _cb_participant_disconnected
var _cb_track_subscribed
var _cb_track_unsubscribed
var _cb_active_speakers


## Minimal stub returned from publish_camera() so callers know the
## publish succeeded even though no local preview is available on web.
class WebVideoStub extends RefCounted:
	const IS_STUB := true


func _ready() -> void:
	_is_web = OS.get_name() == "Web"


# --- Public API (mirrors LiveKitAdapter) ---

func connect_to_room(url: String, token: String) -> void:
	if not _is_web:
		return
	if _room != null:
		disconnect_voice()
	_state = VOICE_STATE.CONNECTING
	session_state_changed.emit(VOICE_STATE.CONNECTING)
	_start_connect_timer()
	_room = JavaScriptBridge.eval("new LivekitClient.Room()")
	if _room == null:
		push_error("[WebVoiceSession] LivekitClient.Room not found — is livekit-client.js loaded?")
		_stop_connect_timer()
		_state = VOICE_STATE.FAILED
		session_state_changed.emit(VOICE_STATE.FAILED)
		return
	_wire_room_events()
	_room.call("connect", url, token)


func disconnect_voice() -> void:
	if not _is_web:
		return
	_stop_connect_timer()
	_cleanup_all_remote()
	if _room != null:
		_room.call("disconnect")
		_room = null
	_free_callbacks()
	_state = VOICE_STATE.DISCONNECTED
	session_state_changed.emit(VOICE_STATE.DISCONNECTED)


func set_muted(muted: bool) -> void:
	_muted = muted
	if not _is_web or _room == null:
		return
	var local_p = _room["localParticipant"]
	if local_p != null:
		local_p.call("setMicrophoneEnabled", not muted)


func set_deafened(deafened: bool) -> void:
	_deafened = deafened


func is_muted() -> bool:
	return _muted


func is_deafened() -> bool:
	return _deafened


func get_session_state() -> int:
	return _state


## Enables the camera via livekit-client.js and returns a stub RefCounted
## so callers can detect success.  Local preview is not available on web.
func publish_camera(_resolution: Vector2i, _fps: int) -> RefCounted:
	if not _is_web or _room == null:
		return null
	var local_p = _room["localParticipant"]
	if local_p == null:
		return null
	local_p.call("setCameraEnabled", true)
	return WebVideoStub.new()


func unpublish_camera() -> void:
	if not _is_web or _room == null:
		return
	var local_p = _room["localParticipant"]
	if local_p != null:
		local_p.call("setCameraEnabled", false)


## Screen share is not supported on web exports.
func publish_screen(_source: Dictionary) -> RefCounted:
	return null


func unpublish_screen() -> void:
	pass


# --- Process: poll room state as safety-net for missed JS events ---

func _process(_delta: float) -> void:
	if not _is_web or _room == null:
		return
	var js_state: String = str(_room["state"])
	var polled: int = _js_state_to_enum(js_state)
	if polled != _state:
		_state = polled
		session_state_changed.emit(_state)


# --- JS room event wiring ---

func _wire_room_events() -> void:
	_cb_connected = JavaScriptBridge.create_callback(_on_connected)
	_cb_disconnected = JavaScriptBridge.create_callback(_on_disconnected)
	_cb_reconnecting = JavaScriptBridge.create_callback(_on_reconnecting)
	_cb_reconnected = JavaScriptBridge.create_callback(_on_reconnected)
	_cb_participant_connected = JavaScriptBridge.create_callback(
		_on_participant_connected
	)
	_cb_participant_disconnected = JavaScriptBridge.create_callback(
		_on_participant_disconnected
	)
	_cb_track_subscribed = JavaScriptBridge.create_callback(_on_track_subscribed)
	_cb_track_unsubscribed = JavaScriptBridge.create_callback(_on_track_unsubscribed)
	_cb_active_speakers = JavaScriptBridge.create_callback(_on_active_speakers_changed)
	_room.call("on", "connected", _cb_connected)
	_room.call("on", "disconnected", _cb_disconnected)
	_room.call("on", "reconnecting", _cb_reconnecting)
	_room.call("on", "reconnected", _cb_reconnected)
	_room.call("on", "participantConnected", _cb_participant_connected)
	_room.call("on", "participantDisconnected", _cb_participant_disconnected)
	_room.call("on", "trackSubscribed", _cb_track_subscribed)
	_room.call("on", "trackUnsubscribed", _cb_track_unsubscribed)
	_room.call("on", "activeSpeakersChanged", _cb_active_speakers)


# --- JS event callbacks ---
# JavaScriptBridge wraps JS callback arguments in a JavaScriptObject array.
# args[0] is the first JS argument, args[1] the second, etc.

func _on_connected(_args) -> void:
	_stop_connect_timer()
	_state = VOICE_STATE.CONNECTED
	session_state_changed.emit(VOICE_STATE.CONNECTED)
	# Enable microphone respecting the current mute state
	if _room != null:
		var local_p = _room["localParticipant"]
		if local_p != null:
			local_p.call("setMicrophoneEnabled", not _muted)


func _on_disconnected(_args) -> void:
	_state = VOICE_STATE.DISCONNECTED
	session_state_changed.emit(VOICE_STATE.DISCONNECTED)


func _on_reconnecting(_args) -> void:
	_state = VOICE_STATE.RECONNECTING
	session_state_changed.emit(VOICE_STATE.RECONNECTING)


func _on_reconnected(_args) -> void:
	_state = VOICE_STATE.CONNECTED
	session_state_changed.emit(VOICE_STATE.CONNECTED)


func _on_participant_connected(args) -> void:
	var participant = args[0]
	if participant == null:
		return
	var identity: String = str(participant["identity"])
	_identity_to_user[identity] = identity
	peer_joined.emit(identity)


func _on_participant_disconnected(args) -> void:
	var participant = args[0]
	if participant == null:
		return
	var identity: String = str(participant["identity"])
	var uid: String = _identity_to_user.get(identity, identity)
	if _remote_video.has(identity):
		_remote_video.erase(identity)
		track_removed.emit(uid)
	_identity_to_user.erase(identity)
	peer_left.emit(uid)


func _on_track_subscribed(args) -> void:
	# JS args: (track, publication, participant)
	var track = args[0]
	var participant = args[2]
	if track == null or participant == null:
		return
	var identity: String = str(participant["identity"])
	var uid: String = _identity_to_user.get(identity, identity)
	var kind: String = str(track["kind"])
	if kind == "video":
		_remote_video[identity] = track
		track_received.emit(uid, track)
	# Audio is played back automatically by the livekit-client.js SDK on web


func _on_track_unsubscribed(args) -> void:
	# JS args: (track, publication, participant)
	var track = args[0]
	var participant = args[2]
	if track == null or participant == null:
		return
	var identity: String = str(participant["identity"])
	var uid: String = _identity_to_user.get(identity, identity)
	var kind: String = str(track["kind"])
	if kind == "video":
		_remote_video.erase(identity)
		track_removed.emit(uid)


func _on_active_speakers_changed(args) -> void:
	# JS args: (speakers: Participant[])
	if _deafened:
		return
	var speakers = args[0]
	if speakers == null:
		return
	var count: int = int(speakers["length"])
	for i in count:
		var speaker = speakers[i]
		if speaker == null:
			continue
		var identity: String = str(speaker["identity"])
		var uid: String = _identity_to_user.get(identity, identity)
		var level: float = float(speaker["audioLevel"])
		audio_level_changed.emit(uid, level)


# --- Helpers ---

func _js_state_to_enum(js_state: String) -> int:
	match js_state:
		"connecting":
			return VOICE_STATE.CONNECTING
		"connected":
			return VOICE_STATE.CONNECTED
		"reconnecting":
			return VOICE_STATE.RECONNECTING
		_:
			return VOICE_STATE.DISCONNECTED


func _cleanup_all_remote() -> void:
	_remote_video.clear()
	_identity_to_user.clear()


func _free_callbacks() -> void:
	_cb_connected = null
	_cb_disconnected = null
	_cb_reconnecting = null
	_cb_reconnected = null
	_cb_participant_connected = null
	_cb_participant_disconnected = null
	_cb_track_subscribed = null
	_cb_track_unsubscribed = null
	_cb_active_speakers = null


func _start_connect_timer() -> void:
	_stop_connect_timer()
	_connect_timer = Timer.new()
	_connect_timer.wait_time = CONNECT_TIMEOUT_SEC
	_connect_timer.one_shot = true
	_connect_timer.timeout.connect(_on_connect_timeout)
	add_child(_connect_timer)
	_connect_timer.start()


func _stop_connect_timer() -> void:
	if _connect_timer != null:
		_connect_timer.stop()
		_connect_timer.queue_free()
		_connect_timer = null


func _on_connect_timeout() -> void:
	if _state == VOICE_STATE.CONNECTING:
		push_error(
			"[WebVoiceSession] Connection timed out after %ds" % int(CONNECT_TIMEOUT_SEC)
		)
		_stop_connect_timer()
		_state = VOICE_STATE.FAILED
		session_state_changed.emit(VOICE_STATE.FAILED)
		if _room != null:
			_room.call("disconnect")
		_room = null


func _exit_tree() -> void:
	_stop_connect_timer()
	disconnect_voice()
