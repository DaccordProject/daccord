extends GutTest

## Unit tests for SyncManager's E2E encryption layer.
##
## Tests are written against the spec in user_flows/daccord_sync.md:
##   - Key derivation: PBKDF2-HMAC-SHA256, 100,000 iterations
##   - Cipher: AES-256-CBC with random 16-byte IV
##   - Wire format: Base64(IV || ciphertext)
##   - Password hashes must NEVER appear in serialized config
##
## We load SyncManager directly (not via the autoload singleton) so that
## these crypto tests can run without the full autoload graph being wired.
## The static methods are called on the script class object.
##
## WARNING: _derive_key() runs 100,000 PBKDF2 iterations. Each call takes
## ~0.5–2 s on modern hardware (SHA-256 is accelerated by Godot's C++ layer).
## Tests that derive a key share a class-level pre-computed key to minimise
## total runtime.

var _sm  ## Loaded SyncManager script (class reference, not singleton)
var _sm_instance  ## Node instance for instance-method tests

## Pre-computed test fixtures — derived once in before_all() to avoid
## running 100,000 PBKDF2 iterations per test.
var _precomputed_key: PackedByteArray = PackedByteArray()
const _TEST_PASSPHRASE := "hunter2"
const _TEST_EMAIL := "alice@example.com"
const _TEST_PLAINTEXT := '{"theme":"dark","servers":[]}'


func before_all() -> void:
	_sm = load("res://scripts/autoload/sync_manager.gd")
	assert_not_null(_sm, "sync_manager.gd must exist at res://scripts/autoload/sync_manager.gd")
	_precomputed_key = _sm._derive_key(_TEST_PASSPHRASE, _TEST_EMAIL)


func before_each() -> void:
	_sm_instance = _sm.new()
	add_child(_sm_instance)


func after_each() -> void:
	if is_instance_valid(_sm_instance):
		remove_child(_sm_instance)
		_sm_instance.queue_free()


# ---------------------------------------------------------------------------
# 1. Roundtrip: _decrypt(_encrypt(plaintext, key), key) == plaintext
# ---------------------------------------------------------------------------

func test_roundtrip_simple_string() -> void:
	var blob: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	var recovered: String = _sm._decrypt(blob, _precomputed_key)
	assert_eq(recovered, _TEST_PLAINTEXT)


func test_roundtrip_empty_string() -> void:
	var blob: String = _sm._encrypt("", _precomputed_key)
	var recovered: String = _sm._decrypt(blob, _precomputed_key)
	assert_eq(recovered, "")


func test_roundtrip_unicode_content() -> void:
	var plaintext := "emoji: 🔐 日本語 naïve café"
	var blob: String = _sm._encrypt(plaintext, _precomputed_key)
	var recovered: String = _sm._decrypt(blob, _precomputed_key)
	assert_eq(recovered, plaintext)


func test_roundtrip_exactly_16_byte_plaintext() -> void:
	# 16 bytes forces an extra PKCS7 block (16 bytes of padding).
	var plaintext := "0123456789abcdef"
	var blob: String = _sm._encrypt(plaintext, _precomputed_key)
	var recovered: String = _sm._decrypt(blob, _precomputed_key)
	assert_eq(recovered, plaintext)


func test_roundtrip_long_json() -> void:
	# Simulate a realistic config blob.
	var plaintext := JSON.stringify({
		"servers": [
			{"base_url": "https://chat.example.com", "token": "tok_abc123", "space_name": "general"},
		],
		"theme": "discord_dark",
		"sound_volume": 0.8,
		"notifications": {"dm": true, "mentions": true},
		"space_order": ["g_1", "g_2"],
	})
	var blob: String = _sm._encrypt(plaintext, _precomputed_key)
	var recovered: String = _sm._decrypt(blob, _precomputed_key)
	assert_eq(recovered, plaintext)


# ---------------------------------------------------------------------------
# 2. Key isolation: different passphrases produce different derived keys
# ---------------------------------------------------------------------------

func test_different_passphrases_produce_different_keys() -> void:
	# Use 1 iteration here to keep the test fast (functional isolation
	# is a property of PBKDF2 independent of the iteration count).
	var key_a: PackedByteArray = _sm._pbkdf2_sha256(
		"passwordA".to_utf8_buffer(),
		"salt@example.com".to_utf8_buffer(),
		1,
		32,
	)
	var key_b: PackedByteArray = _sm._pbkdf2_sha256(
		"passwordB".to_utf8_buffer(),
		"salt@example.com".to_utf8_buffer(),
		1,
		32,
	)
	assert_ne(key_a, key_b)


func test_different_emails_produce_different_keys() -> void:
	var key_a: PackedByteArray = _sm._pbkdf2_sha256(
		"samepassword".to_utf8_buffer(),
		"alice@example.com".to_utf8_buffer(),
		1,
		32,
	)
	var key_b: PackedByteArray = _sm._pbkdf2_sha256(
		"samepassword".to_utf8_buffer(),
		"bob@example.com".to_utf8_buffer(),
		1,
		32,
	)
	assert_ne(key_a, key_b)


func test_derive_key_same_inputs_produce_same_key() -> void:
	# Key derivation must be deterministic.
	var key_a: PackedByteArray = _sm._pbkdf2_sha256(
		_TEST_PASSPHRASE.to_utf8_buffer(),
		_TEST_EMAIL.to_utf8_buffer(),
		1,
		32,
	)
	var key_b: PackedByteArray = _sm._pbkdf2_sha256(
		_TEST_PASSPHRASE.to_utf8_buffer(),
		_TEST_EMAIL.to_utf8_buffer(),
		1,
		32,
	)
	assert_eq(key_a, key_b)


func test_derive_key_email_case_insensitive() -> void:
	# Salt uses email.to_lower() so upper/lower-case emails must match.
	var key_lower: PackedByteArray = _sm._derive_key("pass", "alice@example.com")
	var key_upper: PackedByteArray = _sm._derive_key("pass", "ALICE@EXAMPLE.COM")
	assert_eq(key_lower, key_upper)


func test_derive_key_output_is_32_bytes() -> void:
	assert_eq(_precomputed_key.size(), 32)


# ---------------------------------------------------------------------------
# 3. IV randomness: two encryptions of the same plaintext differ
# ---------------------------------------------------------------------------

func test_two_encryptions_produce_different_blobs() -> void:
	var blob_a: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	var blob_b: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	assert_ne(blob_a, blob_b, "Each encryption should use a fresh random IV")


func test_blob_contains_iv_prefix() -> void:
	# Decoded blob must be at least 17 bytes: 16 IV + at least 1 ciphertext block.
	var blob: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	var raw: PackedByteArray = Marshalls.base64_to_raw(blob)
	assert_true(raw.size() >= 32, "Blob must contain IV (16 B) + at least one cipher block (16 B)")


func test_blobs_share_same_plaintext_but_differ_in_iv() -> void:
	var blob_a: String = _sm._encrypt("hello", _precomputed_key)
	var blob_b: String = _sm._encrypt("hello", _precomputed_key)
	var iv_a: PackedByteArray = Marshalls.base64_to_raw(blob_a).slice(0, 16)
	var iv_b: PackedByteArray = Marshalls.base64_to_raw(blob_b).slice(0, 16)
	assert_ne(iv_a, iv_b, "IVs should differ between encryptions")


# ---------------------------------------------------------------------------
# 4. Passphrase not in blob: passphrase string must not appear in ciphertext
# ---------------------------------------------------------------------------

func test_passphrase_not_in_blob() -> void:
	var blob: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	assert_false(
		blob.contains(_TEST_PASSPHRASE),
		"Passphrase must not appear in the Base64 blob"
	)


func test_passphrase_not_in_raw_ciphertext() -> void:
	var blob: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	var raw_bytes: PackedByteArray = Marshalls.base64_to_raw(blob)
	var raw_str: String = raw_bytes.get_string_from_utf8()
	assert_false(
		raw_str.contains(_TEST_PASSPHRASE),
		"Passphrase must not appear in the raw ciphertext bytes"
	)


func test_email_not_in_blob() -> void:
	var blob: String = _sm._encrypt(_TEST_PLAINTEXT, _precomputed_key)
	assert_false(
		blob.contains(_TEST_EMAIL),
		"Email must not appear in the Base64 blob"
	)


# ---------------------------------------------------------------------------
# 5. No password_hash: _serialize_config() output must never contain it
# ---------------------------------------------------------------------------

func _dict_contains_key_recursive(d: Dictionary, needle: String) -> bool:
	for key in d:
		if key == needle:
			return true
		if d[key] is Dictionary:
			if _dict_contains_key_recursive(d[key], needle):
				return true
	return false


func test_serialize_config_contains_no_password_hash_key() -> void:
	var config: Dictionary = _sm_instance._serialize_config()
	assert_false(
		_dict_contains_key_recursive(config, "password_hash"),
		"_serialize_config() must not include 'password_hash' at any nesting level"
	)


func test_serialize_config_contains_no_password_hash_value() -> void:
	# Also check that the string "password_hash" doesn't appear anywhere in
	# the JSON-serialised output.
	var config: Dictionary = _sm_instance._serialize_config()
	var json_str: String = JSON.stringify(config)
	assert_false(
		json_str.contains("password_hash"),
		"JSON of _serialize_config() must not contain the string 'password_hash'"
	)


func test_serialize_config_returns_dictionary() -> void:
	var config = _sm_instance._serialize_config()
	assert_true(config is Dictionary, "_serialize_config() must return a Dictionary")
