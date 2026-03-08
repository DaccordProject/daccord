extends Node

## SyncManager — Daccord Sync autoload.
##
## Handles E2E-encrypted config sync across devices.
## Registered in project.godot after Config.
##
## Usage:
##   await SyncManager.setup(email, passphrase)  # register-or-login
##   await SyncManager.sync_now()
##   SyncManager.disconnect_sync()

## Emitted after a sync attempt completes.
signal sync_completed(success: bool)
## Emitted whenever the sync state changes.
signal sync_state_changed(new_state: SyncState)

enum SyncState { DISCONNECTED, AUTHENTICATING, IDLE, SYNCING, ERROR }

var state: SyncState = SyncState.DISCONNECTED

var _email: String = ""
var _token: String = ""
var _last_synced: int = 0

# Derived sync key (PackedByteArray). Cleared when disconnect_sync() is called.
var _sync_key: PackedByteArray = PackedByteArray()

# Push debounce timer (5 second delay after last config change)
var _push_timer: Timer = null

const _PUSH_DELAY_SEC := 5.0
const _TOKEN_CIPHER_SALT := "daccord-sync-token-v1"

var _api: SyncAPI = null


func _ready() -> void:
	_api = SyncAPI.new()
	add_child(_api)

	_push_timer = Timer.new()
	_push_timer.one_shot = true
	_push_timer.wait_time = _PUSH_DELAY_SEC
	_push_timer.timeout.connect(_on_push_timer_timeout)
	add_child(_push_timer)

	AppState.config_changed.connect(_on_config_changed)

	# Startup pull: if stored credentials exist, reconnect and pull.
	var stored_email: String = Config.get_sync_email()
	var stored_enc_token: String = Config.get_sync_encrypted_token()
	if not stored_email.is_empty() and not stored_enc_token.is_empty():
		_email = stored_email
		# Decrypt the stored token using the stable per-email key.
		var stable_key: PackedByteArray = _derive_stable_key(stored_email)
		_token = _decrypt(stored_enc_token, stable_key)
		if not _token.is_empty():
			_set_state(SyncState.IDLE)
			# Pull remote config and merge on startup.
			_do_pull()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Register a new account or log in to an existing one.
## Returns SyncResult { ok, data, error }.
func setup(email: String, passphrase: String) -> SyncAPI.SyncResult:
	_set_state(SyncState.AUTHENTICATING)
	_email = email
	_sync_key = _derive_key(passphrase, email)

	# Try login first; if it fails with "not found", register.
	var result: SyncAPI.SyncResult = await _api.login(email, passphrase)
	if not result.ok:
		result = await _api.register(email, passphrase)
		if not result.ok:
			_set_state(SyncState.ERROR)
			return result
		# After registration, log in to get the token.
		result = await _api.login(email, passphrase)
		if not result.ok:
			_set_state(SyncState.ERROR)
			return result

	_token = result.data.get("token", "")
	if _token.is_empty():
		_set_state(SyncState.ERROR)
		return SyncAPI.SyncResult.failure("No token in login response")

	# Persist email and encrypted token.
	Config.set_sync_email(email)
	var stable_key: PackedByteArray = _derive_stable_key(email)
	Config.set_sync_encrypted_token(_encrypt(_token, stable_key))

	_set_state(SyncState.IDLE)
	return result


## Push current config to remote then pull and merge.
func sync_now() -> SyncAPI.SyncResult:
	if _token.is_empty():
		return SyncAPI.SyncResult.failure("Not authenticated")
	_set_state(SyncState.SYNCING)

	var push_result: SyncAPI.SyncResult = await _push()
	if not push_result.ok:
		_set_state(SyncState.ERROR)
		sync_completed.emit(false)
		return push_result

	var pull_result: SyncAPI.SyncResult = await _pull()
	if pull_result.ok:
		_last_synced = int(Time.get_unix_time_from_system())
		_set_state(SyncState.IDLE)
		sync_completed.emit(true)
	else:
		_set_state(SyncState.ERROR)
		sync_completed.emit(false)

	return pull_result


## Clear in-memory credentials and return to DISCONNECTED state.
func disconnect_sync() -> void:
	_email = ""
	_token = ""
	_sync_key = PackedByteArray()
	_last_synced = 0
	Config.clear_sync_credentials()
	_set_state(SyncState.DISCONNECTED)


## Return slot availability from the sync server.
func get_slots() -> SyncAPI.SyncResult:
	return await _api.get_slots()


## Return the email address of the connected account (empty if disconnected).
func get_email() -> String:
	return _email


## Return the Unix timestamp of the last successful sync (0 if never).
func get_last_synced() -> int:
	return _last_synced


# ---------------------------------------------------------------------------
# Config serialization / deserialization
# ---------------------------------------------------------------------------

## Serializes the current local config into a dictionary for sync.
## Password hashes are NEVER included at any nesting level.
func _serialize_config() -> Dictionary:
	var servers: Array = []
	for s in Config.get_servers():
		servers.append({
			"base_url": s.get("base_url", ""),
			"token": s.get("token", ""),
			"space_name": s.get("space_name", ""),
			"username": s.get("username", ""),
			"display_name": s.get("display_name", ""),
		})

	# Collect folder mappings: space_id → folder_name
	var folders: Dictionary = {}
	if Config._config.has_section("folders"):
		for key in Config._config.get_section_keys("folders"):
			var fname: String = Config._config.get_value("folders", key, "")
			if not fname.is_empty():
				folders[key] = fname

	# Collect profile metadata (slug + name, no password hashes)
	var profiles: Array = []
	var order: Array = Config._registry.get_value("order", "list", [])
	for slug in order:
		var pname: String = Config._registry.get_value(
			"profile_" + slug, "name", slug
		)
		profiles.append({"slug": slug, "name": pname})

	return {
		"version": 1,
		"updated_at": int(Time.get_unix_time_from_system()),
		"sections": {
			"servers": servers,
			"state": {
				"user_status": Config.get_user_status(),
				"custom_status": Config.get_custom_status(),
			},
			"notifications": {
				"suppress_everyone": Config.get_suppress_everyone(),
			},
			"sounds": {
				"volume": Config.get_sfx_volume(),
			},
			"accessibility": {
				"reduced_motion": Config.get_reduced_motion(),
				"ui_scale": Config.get_ui_scale(),
			},
			"theme": {
				"preset": Config.get_theme_preset(),
				"custom_palette": Config.get_custom_palette(),
			},
			"space_order": Config.get_space_order(),
			"folders": folders,
			"emoji": {
				"skin_tone": Config.get_emoji_skin_tone(),
				"recent": Config.get_recent_emoji(),
			},
			"profiles": profiles,
		},
	}


## Applies a remote config dictionary using last-write-wins (by updated_at).
## Does not overwrite if local state is newer than the remote blob.
func _apply_config(data: Dictionary) -> void:
	if not data.has("updated_at") or not data.has("sections"):
		return
	var remote_ts: int = int(data.get("updated_at", 0))
	# If remote is not newer, keep local state unchanged.
	if remote_ts <= 0:
		return
	var local_ts: int = Config.get_sync_version()
	if local_ts >= remote_ts:
		return

	var sections: Dictionary = data.get("sections", {})

	# Apply state
	var st: Dictionary = sections.get("state", {})
	if st.has("user_status"):
		Config.set_user_status(int(st.get("user_status", 0)))
	if st.has("custom_status"):
		Config.set_custom_status(str(st.get("custom_status", "")))

	# Apply notifications
	var notif: Dictionary = sections.get("notifications", {})
	if notif.has("suppress_everyone"):
		Config.set_suppress_everyone(bool(notif.get("suppress_everyone", false)))

	# Apply sounds
	var sounds: Dictionary = sections.get("sounds", {})
	if sounds.has("volume"):
		Config.set_sfx_volume(float(sounds.get("volume", 1.0)))

	# Apply accessibility
	var acc: Dictionary = sections.get("accessibility", {})
	if acc.has("reduced_motion"):
		Config.set_reduced_motion(bool(acc.get("reduced_motion", false)))

	# Apply theme
	var theme: Dictionary = sections.get("theme", {})
	if theme.has("preset"):
		Config.set_theme_preset(str(theme.get("preset", "dark")))
	if theme.has("custom_palette") and theme.get("custom_palette") is Dictionary:
		Config.set_custom_palette(theme.get("custom_palette"))

	# Apply space order
	if sections.has("space_order") and sections.get("space_order") is Array:
		Config.set_space_order(sections.get("space_order"))

	# Apply emoji prefs
	var emoji: Dictionary = sections.get("emoji", {})
	if emoji.has("skin_tone"):
		Config.set_emoji_skin_tone(int(emoji.get("skin_tone", 0)))

	# Track remote version as the new baseline.
	Config.set_sync_version(remote_ts)


# ---------------------------------------------------------------------------
# Internal push / pull
# ---------------------------------------------------------------------------

func _push() -> SyncAPI.SyncResult:
	var config_dict: Dictionary = _serialize_config()
	var config_json: String = JSON.stringify(config_dict)
	var key: PackedByteArray = _active_key()
	if key.is_empty():
		return SyncAPI.SyncResult.failure("No encryption key — call setup() first")
	var blob: String = _encrypt(config_json, key)
	var version: int = int(config_dict.get("updated_at", 0))
	return await _api.push(_token, blob, version)


func _pull() -> SyncAPI.SyncResult:
	var result: SyncAPI.SyncResult = await _api.pull(_token)
	if result.ok:
		var blob: String = result.data.get("blob", "")
		var remote_version: int = int(result.data.get("version", 0))
		if not blob.is_empty():
			var key: PackedByteArray = _active_key()
			if not key.is_empty():
				var plaintext: String = _decrypt(blob, key)
				if not plaintext.is_empty():
					var parsed = JSON.parse_string(plaintext)
					if parsed is Dictionary:
						_apply_config(parsed)
		if remote_version > 0:
			Config.set_sync_version(remote_version)
	return result


func _do_pull() -> void:
	if _token.is_empty() or state == SyncState.DISCONNECTED:
		return
	_set_state(SyncState.SYNCING)
	var result: SyncAPI.SyncResult = await _pull()
	if result.ok:
		_last_synced = int(Time.get_unix_time_from_system())
		_set_state(SyncState.IDLE)
	else:
		_set_state(SyncState.ERROR)


# ---------------------------------------------------------------------------
# Config change → debounced push
# ---------------------------------------------------------------------------

func _on_config_changed(_section: String, _key: String) -> void:
	if state == SyncState.DISCONNECTED or _token.is_empty():
		return
	_push_timer.stop()
	_push_timer.start(_PUSH_DELAY_SEC)


func _on_push_timer_timeout() -> void:
	if _token.is_empty() or state == SyncState.DISCONNECTED:
		return
	_set_state(SyncState.SYNCING)
	var result: SyncAPI.SyncResult = await _push()
	if result.ok:
		_last_synced = int(Time.get_unix_time_from_system())
		_set_state(SyncState.IDLE)
	else:
		_set_state(SyncState.ERROR)


# ---------------------------------------------------------------------------
# State helper
# ---------------------------------------------------------------------------

func _set_state(new_state: SyncState) -> void:
	if state != new_state:
		state = new_state
		sync_state_changed.emit(state)


# ---------------------------------------------------------------------------
# E2E encryption
# ---------------------------------------------------------------------------

## Derives a 256-bit AES key from passphrase + email via PBKDF2-HMAC-SHA256.
## Salt: email.to_lower() encoded as UTF-8. Iterations: 100,000.
static func _derive_key(passphrase: String, email: String) -> PackedByteArray:
	var password: PackedByteArray = passphrase.to_utf8_buffer()
	var salt: PackedByteArray = email.to_lower().to_utf8_buffer()
	return _pbkdf2_sha256(password, salt, 100000, 32)


## Derives a stable per-email key for token storage (doesn't require passphrase).
## Uses the Config SALT as password — always reproducible on this device.
static func _derive_stable_key(email: String) -> PackedByteArray:
	var password: PackedByteArray = (_TOKEN_CIPHER_SALT).to_utf8_buffer()
	var salt: PackedByteArray = email.to_lower().to_utf8_buffer()
	return _pbkdf2_sha256(password, salt, 10000, 32)


## Returns the active encryption key. Prefers the user's passphrase-derived
## key when available; falls back to the stable device key for token decryption.
func _active_key() -> PackedByteArray:
	if not _sync_key.is_empty():
		return _sync_key
	if not _email.is_empty():
		return _derive_stable_key(_email)
	return PackedByteArray()


## Encrypts a UTF-8 plaintext string with AES-256-CBC.
## Returns Base64(random_16_byte_IV || ciphertext).
static func _encrypt(plaintext: String, key: PackedByteArray) -> String:
	var crypto := Crypto.new()
	var iv: PackedByteArray = crypto.generate_random_bytes(16)
	var aes := AESContext.new()
	var plaintext_bytes: PackedByteArray = plaintext.to_utf8_buffer()
	var padded: PackedByteArray = _pkcs7_pad(plaintext_bytes, 16)
	aes.start(AESContext.MODE_CBC_ENCRYPT, key, iv)
	var ciphertext: PackedByteArray = aes.update(padded)
	aes.finish()
	return Marshalls.raw_to_base64(iv + ciphertext)


## Decrypts a Base64 blob produced by _encrypt().
static func _decrypt(blob: String, key: PackedByteArray) -> String:
	var combined: PackedByteArray = Marshalls.base64_to_raw(blob)
	if combined.size() <= 16:
		return ""
	var iv: PackedByteArray = combined.slice(0, 16)
	var ciphertext: PackedByteArray = combined.slice(16)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key, iv)
	var padded: PackedByteArray = aes.update(ciphertext)
	aes.finish()
	return _pkcs7_unpad(padded).get_string_from_utf8()


# ---------------------------------------------------------------------------
# Crypto helpers
# ---------------------------------------------------------------------------

## PKCS#7 pads data to a multiple of block_size bytes.
static func _pkcs7_pad(data: PackedByteArray, block_size: int) -> PackedByteArray:
	var pad: int = block_size - (data.size() % block_size)
	var padded: PackedByteArray = data.duplicate()
	for _i in range(pad):
		padded.append(pad)
	return padded


## Strips PKCS#7 padding. Returns data unchanged if the pad byte is invalid.
static func _pkcs7_unpad(data: PackedByteArray) -> PackedByteArray:
	if data.is_empty():
		return data
	var pad_byte: int = data[data.size() - 1]
	if pad_byte == 0 or pad_byte > 16:
		return data
	return data.slice(0, data.size() - pad_byte)


## Single-block PBKDF2-HMAC-SHA256. Supports dk_len <= 32 bytes.
static func _pbkdf2_sha256(
	password: PackedByteArray,
	salt: PackedByteArray,
	iterations: int,
	dk_len: int,
) -> PackedByteArray:
	var crypto := Crypto.new()
	var block_counter: PackedByteArray = PackedByteArray([0, 0, 0, 1])
	var u: PackedByteArray = crypto.hmac_digest(
		HashingContext.HASH_SHA256, password, salt + block_counter
	)
	var result: PackedByteArray = u.duplicate()
	for _i in range(iterations - 1):
		u = crypto.hmac_digest(HashingContext.HASH_SHA256, password, u)
		for j in range(result.size()):
			result[j] ^= u[j]
	return result.slice(0, dk_len)
