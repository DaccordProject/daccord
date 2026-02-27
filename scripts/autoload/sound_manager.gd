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
const _CACHE_DIR := "user://soundboard_cache/"

var _players: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _window_focused: bool = true

# Soundboard playback
var _soundboard_player: AudioStreamPlayer
var _audio_cache: Dictionary = {} # url -> AudioStream (in-memory)
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
	_audio_cache.clear() # clear in-memory; disk cache persists
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
	space_id: String, sound_id: String, user_id: String,
) -> void:
	# Skip echo of our own plays — already played locally on click
	var my_id: String = Client.current_user.get("id", "")
	if user_id == my_id:
		return
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
		push_warning(
			"[SoundManager] Sound not found: ", sound_id
		)
		return

	var audio_url: String = sound_dict.get("audio_url", "")
	if audio_url.is_empty():
		push_warning(
			"[SoundManager] Sound has no audio_url: ", sound_id
		)
		return

	var full_url: String = Client.admin.get_sound_url(
		space_id, audio_url
	)
	var sound_volume: float = sound_dict.get("volume", 1.0)
	_download_and_play(full_url, sound_volume)

func _play_cached_sound(
	stream: AudioStream, sound_volume: float,
) -> void:
	var vol: float = Config.get_sfx_volume()
	if vol <= 0.0:
		push_warning("[SoundManager] SFX volume is 0, skipping")
		return
	_soundboard_player.stream = stream
	_soundboard_player.volume_db = linear_to_db(
		vol * clampf(sound_volume, 0.0, 2.0)
	)
	_soundboard_player.play()

# --- File-based cache ---

func _ensure_cache_dir() -> void:
	DirAccess.make_dir_recursive_absolute(_CACHE_DIR)

func _cache_path_for(url: String, ext: String) -> String:
	return _CACHE_DIR + str(url.hash()) + "." + ext

func _find_cached_file(url: String) -> String:
	for ext in ["ogg", "mp3", "wav"]:
		var path: String = _cache_path_for(url, ext)
		if FileAccess.file_exists(path):
			return path
	return ""

func _detect_audio_ext(
	url: String, headers: PackedStringArray = [],
) -> String:
	for header in headers:
		var low: String = header.to_lower()
		if low.begins_with("content-type:"):
			var ct: String = low.substr(low.find(":") + 1).strip_edges()
			if ct.contains("ogg"):
				return "ogg"
			if ct.contains("mpeg") or ct.contains("mp3"):
				return "mp3"
			if ct.contains("wav"):
				return "wav"
	var ext: String = url.get_extension().to_lower()
	if ext in ["ogg", "mp3", "wav"]:
		return ext
	return "ogg"

func _save_to_cache(
	url: String, body: PackedByteArray,
	headers: PackedStringArray,
) -> String:
	_ensure_cache_dir()
	var ext: String = _detect_audio_ext(url, headers)
	var path: String = _cache_path_for(url, ext)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning(
			"[SoundManager] Cannot write cache file: ", path
		)
		return ""
	file.store_buffer(body)
	file.close()
	return path

func _load_ogg_from_file(path: String) -> AudioStream:
	var stream = AudioStreamOggVorbis.load_from_file(path)
	if stream != null:
		return stream
	var probe: FileAccess = FileAccess.open(path, FileAccess.READ)
	if probe != null:
		var header: PackedByteArray = probe.get_buffer(
			mini(40, probe.get_length())
		)
		probe.close()
		if header.get_string_from_ascii().contains("OpusHead"):
			push_warning(
				"[SoundManager] OGG Opus is not supported"
				+ " by Godot; cannot play: ", path
			)
			return null
	push_warning(
		"[SoundManager] Failed to load OGG from: ", path
	)
	return null

func _load_from_file(path: String) -> AudioStream:
	var ext: String = path.get_extension().to_lower()
	if ext == "ogg":
		return _load_ogg_from_file(path)

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning(
			"[SoundManager] Cannot open cached file: ", path
		)
		return null
	var body: PackedByteArray = file.get_buffer(file.get_length())
	file.close()

	if ext == "mp3":
		var stream := AudioStreamMP3.new()
		stream.data = body
		return stream
	if ext == "wav":
		return _decode_wav(body, path)

	# Unknown extension — try OGG buffer, then MP3
	var ogg = AudioStreamOggVorbis.load_from_buffer(body)
	if ogg != null:
		return ogg
	var mp3 := AudioStreamMP3.new()
	mp3.data = body
	return mp3

func _clear_disk_cache() -> void:
	_audio_cache.clear()
	var dir: DirAccess = DirAccess.open(_CACHE_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir():
			dir.remove(file_name)
		file_name = dir.get_next()

func _decode_wav(
	body: PackedByteArray, source: String,
) -> AudioStream:
	if body.size() < 44:
		push_warning("[SoundManager] WAV too small: ", source)
		return null
	var riff: String = body.slice(0, 4).get_string_from_ascii()
	var wave: String = body.slice(8, 12).get_string_from_ascii()
	if riff != "RIFF" or wave != "WAVE":
		push_warning("[SoundManager] Invalid WAV header: ", source)
		return null

	var audio_format: int = 0
	var channels: int = 1
	var sample_rate: int = 44100
	var bits_per_sample: int = 16
	var pcm_data := PackedByteArray()
	var pos: int = 12
	while pos + 8 <= body.size():
		var chunk_id: String = body.slice(
			pos, pos + 4
		).get_string_from_ascii()
		var chunk_size: int = body.decode_u32(pos + 4)
		var chunk_start: int = pos + 8
		if chunk_id == "fmt ":
			if chunk_size >= 16:
				audio_format = body.decode_u16(chunk_start)
				channels = body.decode_u16(chunk_start + 2)
				sample_rate = body.decode_u32(chunk_start + 4)
				bits_per_sample = body.decode_u16(
					chunk_start + 14
				)
		elif chunk_id == "data":
			pcm_data = body.slice(
				chunk_start, chunk_start + chunk_size
			)
		pos = chunk_start + chunk_size
		if pos % 2 != 0:
			pos += 1

	if pcm_data.is_empty():
		push_warning(
			"[SoundManager] No data chunk in WAV: ", source
		)
		return null
	if audio_format != 1:
		push_warning(
			"[SoundManager] Unsupported WAV format: ",
			audio_format, " in ", source
		)
		return null

	var stream := AudioStreamWAV.new()
	match bits_per_sample:
		8:
			stream.format = AudioStreamWAV.FORMAT_8_BITS
		16:
			stream.format = AudioStreamWAV.FORMAT_16_BITS
		_:
			push_warning(
				"[SoundManager] Unsupported bit depth: ",
				bits_per_sample, " in ", source
			)
			return null
	stream.mix_rate = sample_rate
	stream.stereo = channels >= 2
	stream.data = pcm_data
	return stream

# --- Download and play (shared by preview and gateway paths) ---

func _download_and_play(url: String, volume: float) -> void:
	# 1. In-memory cache
	if _audio_cache.has(url):
		_play_cached_sound(_audio_cache[url], volume)
		return

	# 2. Disk cache
	var cached_path: String = _find_cached_file(url)
	if not cached_path.is_empty():
		var stream: AudioStream = _load_from_file(cached_path)
		if stream != null:
			_audio_cache[url] = stream
			_play_cached_sound(stream, volume)
			return
		# Corrupted cache file — delete so next attempt re-downloads
		DirAccess.remove_absolute(cached_path)

	# 3. Download
	if _soundboard_download_pending.has(url):
		return
	_soundboard_download_pending[url] = true

	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(
			result_code: int, response_code: int,
			headers: PackedStringArray,
			body: PackedByteArray,
		) -> void:
			http.queue_free()
			_soundboard_download_pending.erase(url)
			if result_code != HTTPRequest.RESULT_SUCCESS:
				push_warning(
					"[SoundManager] Download failed (result=%d): %s"
					% [result_code, url]
				)
				return
			if response_code != 200:
				push_warning(
					"[SoundManager] HTTP %d: %s"
					% [response_code, url]
				)
				return

			var path: String = _save_to_cache(
				url, body, headers
			)
			if path.is_empty():
				return
			var stream: AudioStream = _load_from_file(path)
			if stream == null:
				return
			_audio_cache[url] = stream
			_play_cached_sound(stream, volume)
	)
	var err := http.request(url)
	if err != OK:
		push_warning(
			"[SoundManager] Request failed (err=%d): %s"
			% [err, url]
		)
		http.queue_free()
		_soundboard_download_pending.erase(url)

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
	_download_and_play(url, volume)

func _on_soundboard_updated(space_id: String) -> void:
	_sound_meta_cache.erase(space_id)
	_clear_disk_cache()
