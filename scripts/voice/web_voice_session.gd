class_name WebVoiceSession
extends Node

## Web-only voice session using godot-livekit-web.js via JavaScriptBridge.
## Provides the same signal/API surface as LiveKitAdapter for web exports.
## On non-web builds all methods are no-ops (JavaScriptBridge unavailable).
##
## All JS interaction goes through JavaScriptBridge.eval() because Godot's
## JavaScriptObject.call() cannot invoke methods on wrapped JS objects
## (prototype or own-property — obj[method] lookup fails at the WASM boundary).

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

var _has_room: bool = false
var _state: int = VOICE_STATE.DISCONNECTED
var _muted: bool = false
var _deafened: bool = false
var _is_web: bool = false
var _connect_timer: Timer

# Remote video: participant identity -> wrapped track object
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


# --- Helpers for JS eval ---

func _js(code: String) -> Variant:
	return JavaScriptBridge.eval(code, true)


func _js_void(code: String) -> void:
	JavaScriptBridge.eval(code, true)


# --- Public API (mirrors LiveKitAdapter) ---

func connect_to_room(url: String, token: String) -> void:
	if not _is_web:
		return
	if _has_room:
		disconnect_voice()
	_state = VOICE_STATE.CONNECTING
	session_state_changed.emit(VOICE_STATE.CONNECTING)
	_start_connect_timer()

	# Create room and store on window (all access goes through eval)
	_js_void("window._godotLkRoom = GodotLiveKit.createRoom()")
	var check = _js("typeof window._godotLkRoom")
	if str(check) != "object":
		push_error(
			"[WebVoiceSession] GodotLiveKit not found — is godot-livekit-web.js loaded?"
		)
		_stop_connect_timer()
		_state = VOICE_STATE.FAILED
		session_state_changed.emit(VOICE_STATE.FAILED)
		return
	_has_room = true

	_wire_room_events()

	# Escape URL and token for JS string literals
	var safe_url: String = url.replace("\\", "\\\\").replace("'", "\\'")
	var safe_token: String = token.replace("\\", "\\\\").replace("'", "\\'")
	_js_void("window._godotLkRoom.connectToRoom('%s', '%s')" % [safe_url, safe_token])


func disconnect_voice() -> void:
	if not _is_web:
		return
	_stop_connect_timer()
	_cleanup_all_remote()
	if _has_room:
		_js_void(
			"if(window._godotLkRoom){"
			+ "window._godotLkRoom.cleanupAudio();"
			+ "window._godotLkRoom.disconnectFromRoom()}"
		)
		_js_void(
			"delete window._godotLkRoom;"
			+ "for(var i=0;i<9;i++)delete window['_glkCb'+i]"
		)
		_has_room = false
	_free_callbacks()
	_state = VOICE_STATE.DISCONNECTED
	session_state_changed.emit(VOICE_STATE.DISCONNECTED)


func set_muted(muted: bool) -> void:
	_muted = muted
	if not _is_web or not _has_room:
		return
	var enabled_str: String = "true" if not muted else "false"
	_js_void(
		"(function(){var r=window._godotLkRoom;if(r){"
		+ "var p=r.getLocalParticipant();"
		+ "if(p)p.setMicrophoneEnabled(%s)}})()" % enabled_str
	)


func set_deafened(deafened: bool) -> void:
	_deafened = deafened
	if _is_web and _has_room:
		var val: String = "true" if deafened else "false"
		_js_void(
			"(function(){var r=window._godotLkRoom;if(r&&r.setDeafened)"
			+ "r.setDeafened(%s)})()" % val
		)


func is_muted() -> bool:
	return _muted


func is_deafened() -> bool:
	return _deafened


func get_session_state() -> int:
	return _state


## Enables the camera via livekit-client.js and returns a stub RefCounted
## so callers can detect success.  Local preview is not available on web.
func publish_camera(_resolution: Vector2i, _fps: int) -> RefCounted:
	if not _is_web or not _has_room:
		return null
	_js_void(
		"(function(){var r=window._godotLkRoom;if(r){"
		+ "var p=r.getLocalParticipant();"
		+ "if(p)p.setCameraEnabled(true)}})()"
	)
	return WebVideoStub.new()


func unpublish_camera() -> void:
	if not _is_web or not _has_room:
		return
	_js_void(
		"(function(){var r=window._godotLkRoom;if(r){"
		+ "var p=r.getLocalParticipant();"
		+ "if(p)p.setCameraEnabled(false)}})()"
	)


## Screen share is not supported on web exports.
func publish_screen(_source: Dictionary) -> RefCounted:
	return null


func unpublish_screen() -> void:
	pass


# --- Process: poll room state as safety-net for missed JS events ---

func _process(_delta: float) -> void:
	if not _is_web or not _has_room:
		return
	var polled = _js(
		"window._godotLkRoom ? window._godotLkRoom.getConnectionState() : 0"
	)
	if polled == null:
		return
	var polled_int: int = int(polled)
	if polled_int != _state:
		_state = polled_int
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
	_cb_track_unsubscribed = JavaScriptBridge.create_callback(
		_on_track_unsubscribed
	)
	_cb_active_speakers = JavaScriptBridge.create_callback(
		_on_active_speakers_changed
	)

	# Store each callback on window individually, then wire via eval
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	win._glkCb0 = _cb_connected
	win._glkCb1 = _cb_disconnected
	win._glkCb2 = _cb_reconnecting
	win._glkCb3 = _cb_reconnected
	win._glkCb4 = _cb_participant_connected
	win._glkCb5 = _cb_participant_disconnected
	win._glkCb6 = _cb_track_subscribed
	win._glkCb7 = _cb_track_unsubscribed
	win._glkCb8 = _cb_active_speakers

	_js_void(
		"(function(){var r=window._godotLkRoom;if(!r)return;"
		+ "r.on('connected',window._glkCb0);"
		+ "r.on('disconnected',window._glkCb1);"
		+ "r.on('reconnecting',window._glkCb2);"
		+ "r.on('reconnected',window._glkCb3);"
		+ "r.on('participantConnected',window._glkCb4);"
		+ "r.on('participantDisconnected',window._glkCb5);"
		+ "r.on('trackSubscribed',window._glkCb6);"
		+ "r.on('trackUnsubscribed',window._glkCb7);"
		+ "r.on('activeSpeakersChanged',window._glkCb8)"
		+ "})()"
	)
	# Note: Event names match GDExtension signal names (camelCase for JS).
	# The wrapper delivers pre-wrapped participant/track objects with
	# getIdentity(), getKind(), etc. matching the GDExtension API.


# --- JS event callbacks ---
# JavaScriptBridge wraps JS callback arguments in a JavaScriptObject array.
# args[0] is the first JS argument, args[1] the second, etc.

func _on_connected(_args) -> void:
	_stop_connect_timer()
	_state = VOICE_STATE.CONNECTED
	session_state_changed.emit(VOICE_STATE.CONNECTED)
	# Enable microphone respecting the current mute state
	if _has_room:
		var enabled_str: String = "true" if not _muted else "false"
		_js_void(
			"(function(){var r=window._godotLkRoom;if(r){"
			+ "var p=r.getLocalParticipant();"
			+ "if(p)p.setMicrophoneEnabled(%s)}})()" % enabled_str
		)


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
	# Wrapper delivers: (wrappedTrack, wrappedPublication, wrappedParticipant)
	var track = args[0]
	var participant = args[2]
	if track == null or participant == null:
		return
	var identity: String = str(participant["identity"])
	var uid: String = _identity_to_user.get(identity, identity)
	var kind: int = int(track["kind"])
	if kind == 1:  # TrackKind.VIDEO
		_remote_video[identity] = track
		track_received.emit(uid, track)
	# Audio playback is handled by track.attach() in godot-livekit-web.js


func _on_track_unsubscribed(args) -> void:
	# Wrapper delivers: (wrappedTrack, wrappedPublication, wrappedParticipant)
	var track = args[0]
	var participant = args[2]
	if track == null or participant == null:
		return
	var identity: String = str(participant["identity"])
	var uid: String = _identity_to_user.get(identity, identity)
	var kind: int = int(track["kind"])
	if kind == 1:  # TrackKind.VIDEO
		_remote_video.erase(identity)
		track_removed.emit(uid)


func _on_active_speakers_changed(args) -> void:
	# Wrapper delivers: (speakers: Array of {identity, audioLevel})
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
			"[WebVoiceSession] Connection timed out after %ds"
			% int(CONNECT_TIMEOUT_SEC)
		)
		_stop_connect_timer()
		_state = VOICE_STATE.FAILED
		session_state_changed.emit(VOICE_STATE.FAILED)
		_js_void(
			"if(window._godotLkRoom){window._godotLkRoom.disconnectFromRoom()}"
		)
		_has_room = false


func _exit_tree() -> void:
	_stop_connect_timer()
	disconnect_voice()
