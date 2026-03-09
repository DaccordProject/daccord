extends GutTest

## Integration tests for SyncManager push/pull flow.
##
## Requires daccord-sync running locally on port 3001:
##   cd code/daccord-sync && docker compose up --build -d
##
## The server must be started with ALLOW_UNLICENSED_REGISTRATION=true
## (set in docker-compose.yml for the test environment).
##
## These tests use SyncAPI directly (bypassing the Config base URL) so they
## are fully self-contained and do not modify the user's sync credentials.
##
## Run via:
##   ./test.sh sync

## Override SyncAPI to point at the local Docker instance.
class LocalSyncAPI extends SyncAPI:
	func _base_url() -> String:
		return "http://127.0.0.1:3001"


var _api: LocalSyncAPI
var _sm  ## SyncManager script class (not the autoload singleton)
var _token: String = ""
var _email: String = ""
var _passphrase := "integration-test-passphrase-x9"
var _key: PackedByteArray = PackedByteArray()

## Timestamps used to control version ordering across tests.
const _V_OLD := 1000
const _V_MID := 5000
const _V_NEW := 9000


func before_all() -> void:
	_sm = load("res://scripts/autoload/sync_manager.gd")
	assert_not_null(_sm, "sync_manager.gd must be loadable")

	_email = "sync_int_%d@example.com" % int(Time.get_unix_time_from_system())
	_key = _sm._derive_key(_passphrase, _email)

	_api = LocalSyncAPI.new()
	add_child(_api)

	# Register a fresh account — register returns a token directly.
	var reg: SyncAPI.SyncResult = await _api.register(_email, _passphrase)
	assert_true(reg.ok, "Registration must succeed (is daccord-sync running on port 3001?): " + reg.error)
	_token = reg.data.get("token", "")
	assert_false(_token.is_empty(), "Token must be present after registration")


func after_all() -> void:
	if is_instance_valid(_api):
		remove_child(_api)
		_api.queue_free()


# ---------------------------------------------------------------------------
# 1. Full push/pull roundtrip
# ---------------------------------------------------------------------------

func test_push_pull_roundtrip() -> void:
	var plaintext := JSON.stringify({
		"version": 1,
		"updated_at": _V_OLD,
		"sections": {"theme": {"preset": "midnight"}},
	})
	var blob: String = _sm._encrypt(plaintext, _key)

	var push_r: SyncAPI.SyncResult = await _api.push(_token, blob, _V_OLD)
	assert_true(push_r.ok, "Push should succeed: " + push_r.error)
	assert_true(push_r.data.has("version"), "Push response should include 'version'")

	var pull_r: SyncAPI.SyncResult = await _api.pull(_token)
	assert_true(pull_r.ok, "Pull should succeed: " + pull_r.error)

	var returned_blob: String = pull_r.data.get("blob", "")
	assert_false(returned_blob.is_empty(), "Pulled blob must not be empty")

	var decrypted: String = _sm._decrypt(returned_blob, _key)
	var parsed = JSON.parse_string(decrypted)
	assert_not_null(parsed, "Pulled blob should decrypt to valid JSON")
	assert_true(parsed is Dictionary, "Decrypted blob should be a Dictionary")
	assert_eq(
		parsed.get("sections", {}).get("theme", {}).get("preset", ""),
		"midnight",
		"Round-tripped theme should match what was pushed"
	)


# ---------------------------------------------------------------------------
# 2. Stale version push is rejected (409 conflict)
# ---------------------------------------------------------------------------

func test_stale_version_rejected() -> void:
	# Establish a known current version on the server.
	var newer_blob: String = _sm._encrypt(
		JSON.stringify({"version": 1, "updated_at": _V_MID, "sections": {}}),
		_key
	)
	var push1: SyncAPI.SyncResult = await _api.push(_token, newer_blob, _V_MID)
	assert_true(push1.ok, "Setup push with newer version must succeed: " + push1.error)

	# Attempt to push an older version — server should reject.
	var older_blob: String = _sm._encrypt(
		JSON.stringify({"version": 1, "updated_at": _V_OLD, "sections": {}}),
		_key
	)
	var push2: SyncAPI.SyncResult = await _api.push(_token, older_blob, _V_OLD)
	assert_false(push2.ok, "Push with stale version should be rejected")
	assert_true(
		push2.error.to_lower().contains("conflict") or push2.error.contains("409"),
		"Error should mention conflict or 409, got: " + push2.error
	)


# ---------------------------------------------------------------------------
# 3. Merge: remote section with newer updated_at overwrites local
# ---------------------------------------------------------------------------

func test_remote_newer_overwrites_local() -> void:
	var sm_instance = _sm.new()
	add_child(sm_instance)

	# Record what the theme was before so we can restore it.
	var original_theme: String = Config.get_theme_preset()
	var original_version: int = Config.get_sync_version()

	# Local is behind the remote.
	Config.set_sync_version(_V_OLD)

	var remote_data := {
		"version": 1,
		"updated_at": _V_NEW,
		"sections": {
			"theme": {"preset": "remote_light"},
		},
	}
	sm_instance._apply_config(remote_data)

	assert_eq(
		Config.get_theme_preset(),
		"remote_light",
		"Remote (newer) config should overwrite local theme"
	)
	assert_eq(
		Config.get_sync_version(),
		_V_NEW,
		"Sync version should advance to remote timestamp"
	)

	# Restore state.
	Config.set_theme_preset(original_theme)
	Config.set_sync_version(original_version)

	remove_child(sm_instance)
	sm_instance.queue_free()


# ---------------------------------------------------------------------------
# 4. Merge: local section with newer updated_at is preserved
# ---------------------------------------------------------------------------

func test_local_newer_preserved() -> void:
	var sm_instance = _sm.new()
	add_child(sm_instance)

	var original_theme: String = Config.get_theme_preset()
	var original_version: int = Config.get_sync_version()

	# Local is ahead — set a distinctive theme name to detect changes.
	Config.set_theme_preset("local_dark")
	Config.set_sync_version(_V_NEW)

	var remote_data := {
		"version": 1,
		"updated_at": _V_OLD,
		"sections": {
			"theme": {"preset": "remote_should_not_apply"},
		},
	}
	sm_instance._apply_config(remote_data)

	assert_eq(
		Config.get_theme_preset(),
		"local_dark",
		"Local (newer) config must not be overwritten by older remote"
	)
	assert_eq(
		Config.get_sync_version(),
		_V_NEW,
		"Sync version must not regress"
	)

	# Restore state.
	Config.set_theme_preset(original_theme)
	Config.set_sync_version(original_version)

	remove_child(sm_instance)
	sm_instance.queue_free()


# ---------------------------------------------------------------------------
# 5. Rapid config changes produce only one push after debounce window
# ---------------------------------------------------------------------------

func test_debounce_rapid_changes_single_push() -> void:
	var sm_instance = _sm.new()
	add_child(sm_instance)

	# Wire up the instance so it thinks it is authenticated and idle.
	sm_instance._token = _token
	sm_instance._email = _email
	sm_instance._sync_key = _key
	sm_instance._set_state(_sm.SyncState.IDLE)

	# Trigger 5 config-change events in rapid succession.
	for i in range(5):
		sm_instance._on_config_changed("theme", "preset")

	# After 5 calls the timer should be running with close to the full delay
	# (each call resets it), and no push should have fired yet.
	assert_true(
		sm_instance._push_timer.time_left > 0.0,
		"Push timer must be active after config changes"
	)
	assert_true(
		sm_instance._push_timer.time_left <= sm_instance._PUSH_DELAY_SEC,
		"Timer must not exceed the configured delay constant"
	)
	assert_eq(
		sm_instance.state,
		_sm.SyncState.IDLE,
		"State must still be IDLE — push has not fired yet"
	)

	# Stop the timer to avoid a real push during cleanup.
	sm_instance._push_timer.stop()

	remove_child(sm_instance)
	sm_instance.queue_free()
