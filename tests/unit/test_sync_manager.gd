extends GutTest

## Unit tests for SyncManager state machine and SyncAPI HTTP layer.
##
## Strategy:
##   SyncManager: load the script directly (not as singleton), add to tree
##   so _ready() wires up the timer and connects signals, then replace _api
##   with StubSyncAPI to avoid real HTTP calls.
##
##   SyncAPI: use StubSyncAPI (overrides _http_post/_http_get/_http_put) to
##   verify that public methods call the correct endpoints with correct bodies.

var _sm_script  ## Loaded SyncManager script class
var _sm: Node   ## SyncManager instance under test
var _stub_api: StubSyncAPI


# ---------------------------------------------------------------------------
# StubSyncAPI — overrides the internal HTTP helpers to avoid network calls.
# ---------------------------------------------------------------------------

class StubSyncAPI extends SyncAPI:
	## Records every call for assertion.
	var calls: Array = []
	## Preset responses keyed by "METHOD /path".
	var responses: Dictionary = {}

	func _http_get(path: String, token: String) -> SyncResult:
		calls.append({"method": "GET", "path": path, "token": token})
		var key: String = "GET " + path
		if responses.has(key):
			return responses[key]
		return SyncResult.failure("stub: not found")

	func _http_post(
		path: String, body: Dictionary, token: String,
	) -> SyncResult:
		calls.append(
			{"method": "POST", "path": path, "body": body, "token": token}
		)
		var key: String = "POST " + path
		if responses.has(key):
			return responses[key]
		return SyncResult.failure("stub: not found")

	func _http_put(
		path: String, body: Dictionary, token: String,
	) -> SyncResult:
		calls.append(
			{"method": "PUT", "path": path, "body": body, "token": token}
		)
		var key: String = "PUT " + path
		if responses.has(key):
			return responses[key]
		return SyncResult.failure("stub: not found")


# ---------------------------------------------------------------------------
# Setup / teardown
# ---------------------------------------------------------------------------

func before_all() -> void:
	_sm_script = load("res://scripts/autoload/sync_manager.gd")
	assert_not_null(_sm_script, "sync_manager.gd must exist")


func before_each() -> void:
	_sm = _sm_script.new()
	add_child(_sm)
	# Replace the real SyncAPI created by _ready() with our stub.
	_stub_api = StubSyncAPI.new()
	_sm._api = _stub_api
	watch_signals(_sm)


func after_each() -> void:
	if is_instance_valid(_sm):
		_sm.queue_free()
	_stub_api = null


# ===========================================================================
# Initial state
# ===========================================================================

func test_initial_state_is_disconnected() -> void:
	## State before any setup() call must be DISCONNECTED.
	assert_eq(_sm.state, _sm_script.SyncState.DISCONNECTED)


# ===========================================================================
# setup() — state transitions
# ===========================================================================

func test_setup_success_transitions_to_idle() -> void:
	## Successful login: DISCONNECTED → AUTHENTICATING → IDLE.
	_stub_api.responses["POST /api/auth/login"] = SyncAPI.SyncResult.success(
		{"token": "tok_abc"}
	)
	var states: Array = []
	_sm.sync_state_changed.connect(func(s): states.append(s))

	await _sm.setup("alice@example.com", "hunter2")

	assert_eq(_sm.state, _sm_script.SyncState.IDLE)
	assert_true(
		_sm_script.SyncState.AUTHENTICATING in states,
		"AUTHENTICATING must be emitted during setup"
	)
	assert_true(
		_sm_script.SyncState.IDLE in states,
		"IDLE must be emitted after successful setup"
	)


func test_setup_login_fail_register_success_transitions_to_idle() -> void:
	## Login fails first, then register + login succeed.
	_stub_api.responses["POST /api/auth/login"] = SyncAPI.SyncResult.failure(
		"not found"
	)
	_stub_api.responses["POST /api/auth/register"] = SyncAPI.SyncResult.success(
		{}
	)
	# Second login call must succeed — use a response that alternates.
	# Override _http_post to handle two different login outcomes.
	var call_count: int = 0
	_stub_api.set_meta("_original_responses", _stub_api.responses.duplicate())

	# A simpler approach: subclass on-the-fly is not possible in GDScript.
	# Instead, prime responses using the first-call pattern via a counter tracked
	# on the stub. We test this by asserting IDLE is reached.
	#
	# For this scenario, make the stub return failure for the first login,
	# success for register, and success for the second login.
	# Re-assign _api with a fresh stub that has both login responses queued.
	var seq_stub := _SeqStubSyncAPI.new()
	seq_stub.login_results = [
		SyncAPI.SyncResult.failure("not found"),
		SyncAPI.SyncResult.success({"token": "tok_reg"}),
	]
	seq_stub.register_results = [SyncAPI.SyncResult.success({})]
	_sm._api = seq_stub

	await _sm.setup("bob@example.com", "password")

	assert_eq(_sm.state, _sm_script.SyncState.IDLE)


func test_setup_auth_failure_transitions_to_error() -> void:
	## Both login and register fail → ERROR.
	_stub_api.responses["POST /api/auth/login"] = SyncAPI.SyncResult.failure(
		"unauthorized"
	)
	_stub_api.responses["POST /api/auth/register"] = SyncAPI.SyncResult.failure(
		"email taken"
	)

	var result: SyncAPI.SyncResult = await _sm.setup(
		"bad@example.com", "wrong"
	)

	assert_false(result.ok)
	assert_eq(_sm.state, _sm_script.SyncState.ERROR)


func test_setup_emits_sync_state_changed() -> void:
	_stub_api.responses["POST /api/auth/login"] = SyncAPI.SyncResult.success(
		{"token": "t"}
	)
	await _sm.setup("alice@example.com", "pass")
	assert_signal_emitted(_sm, "sync_state_changed")


# ===========================================================================
# sync_now() — state transitions
# ===========================================================================

func _prime_idle(token: String = "tok") -> void:
	## Helper: put the manager into IDLE state with a valid token.
	_sm._token = token
	var key_bytes: Array = [
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
		17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
	]
	_sm._sync_key = PackedByteArray(key_bytes)
	_sm._email = "alice@example.com"
	_sm.state = _sm_script.SyncState.IDLE


func test_sync_now_success_transitions_back_to_idle() -> void:
	_prime_idle()
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.success(
		{"version": 1}
	)
	_stub_api.responses["GET /api/config"] = SyncAPI.SyncResult.success(
		{"blob": "", "version": 1}
	)

	await _sm.sync_now()

	assert_eq(_sm.state, _sm_script.SyncState.IDLE)


func test_sync_now_emits_sync_completed_true_on_success() -> void:
	_prime_idle()
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.success(
		{"version": 1}
	)
	_stub_api.responses["GET /api/config"] = SyncAPI.SyncResult.success(
		{"blob": "", "version": 1}
	)

	await _sm.sync_now()

	assert_signal_emitted_with_parameters(_sm, "sync_completed", [true])


func test_sync_now_push_failure_transitions_to_error() -> void:
	_prime_idle()
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.failure(
		"server error"
	)

	await _sm.sync_now()

	assert_eq(_sm.state, _sm_script.SyncState.ERROR)


func test_sync_now_push_failure_emits_sync_completed_false() -> void:
	_prime_idle()
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.failure(
		"server error"
	)

	await _sm.sync_now()

	assert_signal_emitted_with_parameters(_sm, "sync_completed", [false])


func test_sync_now_pull_failure_transitions_to_error() -> void:
	_prime_idle()
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.success(
		{"version": 1}
	)
	_stub_api.responses["GET /api/config"] = SyncAPI.SyncResult.failure(
		"not found"
	)

	await _sm.sync_now()

	assert_eq(_sm.state, _sm_script.SyncState.ERROR)


func test_sync_now_without_token_returns_failure() -> void:
	## Calling sync_now() while disconnected (no token) returns failure.
	var result: SyncAPI.SyncResult = await _sm.sync_now()
	assert_false(result.ok)
	# State should stay DISCONNECTED — no transition.
	assert_eq(_sm.state, _sm_script.SyncState.DISCONNECTED)


func test_sync_now_enters_syncing_state() -> void:
	_prime_idle()
	var states: Array = []
	_sm.sync_state_changed.connect(func(s): states.append(s))
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.success(
		{"version": 1}
	)
	_stub_api.responses["GET /api/config"] = SyncAPI.SyncResult.success(
		{"blob": "", "version": 1}
	)

	await _sm.sync_now()

	assert_true(
		_sm_script.SyncState.SYNCING in states,
		"SYNCING must be emitted during sync_now()"
	)


# ===========================================================================
# disconnect_sync()
# ===========================================================================

func test_disconnect_sync_returns_to_disconnected() -> void:
	_prime_idle()
	_sm.disconnect_sync()
	assert_eq(_sm.state, _sm_script.SyncState.DISCONNECTED)


func test_disconnect_sync_clears_sync_key() -> void:
	_prime_idle()
	_sm.disconnect_sync()
	assert_eq(_sm._sync_key.size(), 0)


func test_disconnect_sync_clears_token() -> void:
	_prime_idle()
	_sm.disconnect_sync()
	assert_eq(_sm._token, "")


func test_disconnect_sync_emits_state_changed() -> void:
	_prime_idle()
	_sm.disconnect_sync()
	assert_signal_emitted(_sm, "sync_state_changed")


# ===========================================================================
# Push debounce timer
# ===========================================================================

func test_config_change_starts_push_timer() -> void:
	## Emitting config_changed while IDLE with a token starts the debounce timer.
	_prime_idle()
	assert_true(
		_sm._push_timer.is_stopped(),
		"Timer must be stopped before config change"
	)
	AppState.config_changed.emit("servers", "base_url")
	assert_false(
		_sm._push_timer.is_stopped(),
		"Timer must start after config change when IDLE"
	)


func test_config_change_does_not_start_timer_when_disconnected() -> void:
	## Config changes while DISCONNECTED must not start the timer.
	AppState.config_changed.emit("servers", "base_url")
	assert_true(
		_sm._push_timer.is_stopped(),
		"Timer must remain stopped when DISCONNECTED"
	)


# ===========================================================================
# SyncAPI endpoint routing
# ===========================================================================

func test_sync_api_register_calls_correct_endpoint() -> void:
	_stub_api.responses["POST /api/auth/register"] = SyncAPI.SyncResult.success(
		{}
	)
	await _stub_api.register("alice@example.com", "hunter2")
	assert_eq(_stub_api.calls.size(), 1)
	var call: Dictionary = _stub_api.calls[0]
	assert_eq(call["method"], "POST")
	assert_eq(call["path"], "/api/auth/register")
	assert_eq(call["body"].get("email", ""), "alice@example.com")
	assert_eq(call["body"].get("password", ""), "hunter2")


func test_sync_api_login_calls_correct_endpoint() -> void:
	_stub_api.responses["POST /api/auth/login"] = SyncAPI.SyncResult.success(
		{"token": "t"}
	)
	await _stub_api.login("alice@example.com", "hunter2")
	assert_eq(_stub_api.calls.size(), 1)
	var call: Dictionary = _stub_api.calls[0]
	assert_eq(call["method"], "POST")
	assert_eq(call["path"], "/api/auth/login")
	assert_eq(call["body"].get("email", ""), "alice@example.com")


func test_sync_api_push_calls_correct_endpoint() -> void:
	_stub_api.responses["PUT /api/config"] = SyncAPI.SyncResult.success(
		{"version": 1}
	)
	await _stub_api.push("my_token", "encrypted_blob", 42)
	assert_eq(_stub_api.calls.size(), 1)
	var call: Dictionary = _stub_api.calls[0]
	assert_eq(call["method"], "PUT")
	assert_eq(call["path"], "/api/config")
	assert_eq(call["token"], "my_token")
	assert_eq(call["body"].get("blob", ""), "encrypted_blob")
	assert_eq(call["body"].get("version", 0), 42)


func test_sync_api_pull_calls_correct_endpoint() -> void:
	_stub_api.responses["GET /api/config"] = SyncAPI.SyncResult.success(
		{"blob": "b64data", "version": 1}
	)
	await _stub_api.pull("my_token")
	assert_eq(_stub_api.calls.size(), 1)
	var call: Dictionary = _stub_api.calls[0]
	assert_eq(call["method"], "GET")
	assert_eq(call["path"], "/api/config")
	assert_eq(call["token"], "my_token")


# ===========================================================================
# Helper inner class for sequenced responses
# ===========================================================================

class _SeqStubSyncAPI extends SyncAPI:
	## Returns responses in sequence from pre-set arrays.
	var login_results: Array = []
	var register_results: Array = []
	var _login_idx: int = 0
	var _register_idx: int = 0

	func login(_email: String, _password: String) -> SyncResult:
		if _login_idx < login_results.size():
			var r: SyncResult = login_results[_login_idx]
			_login_idx += 1
			return r
		return SyncResult.failure("stub: no more login results")

	func register(_email: String, _password: String) -> SyncResult:
		if _register_idx < register_results.size():
			var r: SyncResult = register_results[_register_idx]
			_register_idx += 1
			return r
		return SyncResult.failure("stub: no more register results")
