extends Node

const _SFX_VOICE_JOIN := preload("res://assets/sfx/voice_join.wav")
const _SFX_VOICE_LEAVE := preload("res://assets/sfx/voice_leave.wav")

const SOUNDS := {
	"message_received": preload("res://assets/sfx/message_received.wav"),
	"mention_received": preload("res://assets/sfx/mention_received.wav"),
	"message_sent": preload("res://assets/sfx/message_sent.wav"),
	"voice_join": _SFX_VOICE_JOIN,
	"voice_leave": _SFX_VOICE_LEAVE,
	"mute": preload("res://assets/sfx/mute.wav"),
	"unmute": preload("res://assets/sfx/unmute.wav"),
	"deafen": preload("res://assets/sfx/deafen.wav"),
	"undeafen": preload("res://assets/sfx/undeafen.wav"),
	"peer_join": _SFX_VOICE_JOIN,
	"peer_leave": _SFX_VOICE_LEAVE,
}

const POOL_SIZE := 4

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _window_focused: bool = true

# Soundboard playback
var _soundboard_player: AudioStreamPlayer
var _audio_cache: Dictionary = {} # audio_url -> AudioStream
var _sound_meta_cache: Dictionary = {} # space_id -> Array[Dictionary]
var _soundboard_download_pending: Dictionary = {} # url -> true

func _ready() -> void:
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)

	_soundboard_player = AudioStreamPlayer.new()
	_soundboard_player.bus = &"SFX"
	add_child(_soundboard_player)

	AppState.message_sent.connect(_on_message_sent)
	AppState.voice_joined.connect(_on_voice_joined)
	AppState.voice_left.connect(_on_voice_left)
	AppState.voice_mute_changed.connect(_on_voice_mute_changed)
	AppState.voice_deafen_changed.connect(_on_voice_deafen_changed)
	AppState.soundboard_played.connect(_on_soundboard_played)
	AppState.soundboard_updated.connect(_on_soundboard_updated)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false

func play(sound_name: String) -> void:
	if not SOUNDS.has(sound_name):
		return
	if not Config.is_sound_enabled(sound_name):
		return
	if _is_dnd():
		return

	var vol: float = Config.get_sfx_volume()
	if vol <= 0.0:
		return

	var player := _players[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	player.stream = SOUNDS[sound_name]
	player.volume_db = linear_to_db(vol)
	player.play()

func play_for_message(
	channel_id: String, author_id: String,
	mentions: Array, mention_everyone: bool,
) -> void:
	var my_id: String = Client.current_user.get("id", "")
	if author_id == my_id:
		return
	if channel_id == AppState.current_channel_id:
		return

	var is_mention: bool = my_id in mentions or mention_everyone
	if is_mention:
		play("mention_received")
	elif not _window_focused:
		# Only play the generic message sound when the window is unfocused.
		# Mentions always play regardless of focus.
		play("message_received")

func play_for_voice_state(user_id: String, joined_channel: String, left_channel: String) -> void:
	var my_id: String = Client.current_user.get("id", "")
	if user_id == my_id:
		return
	var my_voice_channel: String = AppState.voice_channel_id
	if my_voice_channel.is_empty():
		return
	if joined_channel == my_voice_channel:
		play("peer_join")
	elif left_channel == my_voice_channel:
		play("peer_leave")

func _is_dnd() -> bool:
	var status: int = Client.current_user.get("status", 0)
	return status == ClientModels.UserStatus.DND

func _on_message_sent(_text: String) -> void:
	play("message_sent")

func _on_voice_joined(_channel_id: String) -> void:
	play("voice_join")

func _on_voice_left(_channel_id: String) -> void:
	play("voice_leave")
	_sound_meta_cache.clear()
	_audio_cache.clear()
	_soundboard_download_pending.clear()

func _on_voice_mute_changed(is_muted: bool) -> void:
	if is_muted:
		play("mute")
	else:
		play("unmute")

func _on_voice_deafen_changed(is_deafened: bool) -> void:
	if is_deafened:
		play("deafen")
	else:
		play("undeafen")

# --- Soundboard playback ---

func _on_soundboard_played(
	space_id: String, sound_id: String, _user_id: String,
) -> void:
	if AppState.is_voice_deafened:
		return
	if AppState.voice_channel_id.is_empty():
		return
	if _is_dnd():
		return
	_play_soundboard_sound(space_id, sound_id)

func _play_soundboard_sound(
	space_id: String, sound_id: String,
) -> void:
	var sounds: Array = await _get_sound_meta(space_id)
	var sound_dict: Dictionary = {}
	for s in sounds:
		if s.get("id", "") == sound_id:
			sound_dict = s
			break
	if sound_dict.is_empty():
		return

	var audio_url: String = sound_dict.get("audio_url", "")
	if audio_url.is_empty():
		return

	var full_url: String = Client.admin.get_sound_url(
		space_id, audio_url
	)
	var sound_volume: float = sound_dict.get("volume", 1.0)

	if _audio_cache.has(full_url):
		_play_cached_sound(_audio_cache[full_url], sound_volume)
		return

	if _soundboard_download_pending.has(full_url):
		return
	_soundboard_download_pending[full_url] = true

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(
			_result_code: int, response_code: int,
			headers: PackedStringArray,
			body: PackedByteArray,
		) -> void:
			http.queue_free()
			_soundboard_download_pending.erase(full_url)
			if response_code != 200:
				return
			var stream: AudioStream = _decode_audio(
				body, full_url, headers
			)
			if stream == null:
				return
			_audio_cache[full_url] = stream
			_play_cached_sound(stream, sound_volume)
	)
	http.request(full_url)

func _play_cached_sound(
	stream: AudioStream, sound_volume: float,
) -> void:
	var vol: float = Config.get_sfx_volume()
	if vol <= 0.0:
		return
	_soundboard_player.stream = stream
	_soundboard_player.volume_db = linear_to_db(
		vol * clampf(sound_volume, 0.0, 2.0)
	)
	_soundboard_player.play()

func _decode_audio(
	body: PackedByteArray, url: String,
	headers: PackedStringArray,
) -> AudioStream:
	var content_type := ""
	for header in headers:
		if header.to_lower().begins_with("content-type:"):
			content_type = header.substr(
				header.find(":") + 1
			).strip_edges().to_lower()
			break

	var ext := url.get_extension().to_lower()

	if content_type.contains("ogg") or ext == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(body)
	if content_type.contains("mpeg") \
		or content_type.contains("mp3") or ext == "mp3":
		var stream := AudioStreamMP3.new()
		stream.data = body
		return stream
	if content_type.contains("wav") or ext == "wav":
		var stream := AudioStreamWAV.new()
		stream.data = body
		return stream

	# Fallback: try OGG
	return AudioStreamOggVorbis.load_from_buffer(body)

func _get_sound_meta(space_id: String) -> Array:
	if _sound_meta_cache.has(space_id):
		return _sound_meta_cache[space_id]

	var result: RestResult = await Client.admin.get_sounds(
		space_id
	)
	if result == null or not result.ok:
		return []

	var sounds: Array = result.data if result.data is Array else []
	var dicts: Array = []
	for sound in sounds:
		if sound is AccordSound:
			dicts.append(ClientModels.sound_to_dict(sound))
		elif sound is Dictionary:
			dicts.append(sound)
	_sound_meta_cache[space_id] = dicts
	return dicts

func play_preview(url: String, volume: float = 1.0) -> void:
	if _audio_cache.has(url):
		_play_cached_sound(_audio_cache[url], volume)
		return

	if _soundboard_download_pending.has(url):
		return
	_soundboard_download_pending[url] = true

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(
			_result_code: int, response_code: int,
			headers: PackedStringArray,
			body: PackedByteArray,
		) -> void:
			http.queue_free()
			_soundboard_download_pending.erase(url)
			if response_code != 200:
				return
			var stream: AudioStream = _decode_audio(
				body, url, headers
			)
			if stream == null:
				return
			_audio_cache[url] = stream
			_play_cached_sound(stream, volume)
	)
	http.request(url)

func _on_soundboard_updated(space_id: String) -> void:
	_sound_meta_cache.erase(space_id)
