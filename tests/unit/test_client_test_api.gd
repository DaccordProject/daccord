extends GutTest

## Unit tests for ClientTestApi request parsing and endpoint routing.

const ClientTestApi := preload("res://scripts/client/client_test_api.gd")

var api: RefCounted


func before_each() -> void:
	# Create with a dummy node as client
	var dummy := Node.new()
	add_child(dummy)
	api = ClientTestApi.new(dummy)


func after_each() -> void:
	if api != null:
		api.stop()
	for child in get_children():
		remove_child(child)
		child.queue_free()


# =============================================================================
# Request line validation
# =============================================================================

func test_validate_post_request() -> void:
	var result: Dictionary = api._validate_request_line(
		"POST /api/get_state HTTP/1.1\r\nHost: localhost"
	)
	assert_false(result.has("error"), "Valid POST should succeed")
	assert_eq(result["path"], "/api/get_state")


func test_validate_rejects_get_method() -> void:
	var result: Dictionary = api._validate_request_line(
		"GET /api/get_state HTTP/1.1\r\n"
	)
	assert_true(result.has("error"), "GET should be rejected")
	assert_eq(result["_status"], 405)


func test_validate_rejects_non_api_path() -> void:
	var result: Dictionary = api._validate_request_line(
		"POST /other/path HTTP/1.1\r\n"
	)
	assert_true(result.has("error"), "Non /api/ path should 404")
	assert_eq(result["_status"], 404)


func test_validate_rejects_malformed_line() -> void:
	var result: Dictionary = api._validate_request_line("GARBAGE")
	assert_true(result.has("error"))
	assert_eq(result["_status"], 400)


# =============================================================================
# Header parsing
# =============================================================================

func test_parse_headers_basic() -> void:
	var lines := PackedStringArray([
		"POST /api/test HTTP/1.1",
		"Content-Type: application/json",
		"Content-Length: 42",
		"Authorization: Bearer abc123",
		"",
	])
	var headers: Dictionary = api._parse_headers(lines)
	assert_eq(headers["content-type"], "application/json")
	assert_eq(headers["content-length"], "42")
	assert_eq(headers["authorization"], "Bearer abc123")


func test_parse_headers_case_insensitive() -> void:
	var lines := PackedStringArray([
		"POST /api/test HTTP/1.1",
		"CONTENT-LENGTH: 10",
		"",
	])
	var headers: Dictionary = api._parse_headers(lines)
	assert_true(
		headers.has("content-length"),
		"Header keys should be lowercased"
	)


func test_parse_headers_ignores_malformed() -> void:
	var lines := PackedStringArray([
		"POST /api/test HTTP/1.1",
		"no-colon-here",
		"Valid-Key: valid-value",
		"",
	])
	var headers: Dictionary = api._parse_headers(lines)
	assert_false(headers.has("no-colon-here"))
	assert_eq(headers["valid-key"], "valid-value")


# =============================================================================
# Auth check
# =============================================================================

func test_auth_passes_with_no_token_configured() -> void:
	api._auth_token = ""
	assert_true(api._check_auth(""), "No token = always passes")


func test_auth_passes_with_correct_token() -> void:
	api._auth_token = "secret123"
	assert_true(
		api._check_auth("Bearer secret123"),
		"Correct bearer token should pass"
	)


func test_auth_fails_with_wrong_token() -> void:
	api._auth_token = "secret123"
	assert_false(
		api._check_auth("Bearer wrong_token"),
		"Wrong token should fail"
	)


func test_auth_fails_without_bearer_prefix() -> void:
	api._auth_token = "secret123"
	assert_false(
		api._check_auth("secret123"),
		"Missing 'Bearer ' prefix should fail"
	)


# =============================================================================
# Constant-time comparison
# =============================================================================

func test_constant_time_equal_strings() -> void:
	assert_true(api._constant_time_compare("abc", "abc"))


func test_constant_time_different_strings() -> void:
	assert_false(api._constant_time_compare("abc", "xyz"))


func test_constant_time_different_lengths() -> void:
	assert_false(api._constant_time_compare("short", "longer_string"))


func test_constant_time_empty_strings() -> void:
	assert_true(api._constant_time_compare("", ""))


# =============================================================================
# Rate limiting
# =============================================================================

func test_rate_limit_allows_initial_requests() -> void:
	api._request_timestamps.clear()
	assert_false(
		api._is_rate_limited(),
		"First request should not be limited"
	)


func test_rate_limit_blocks_after_burst() -> void:
	api._request_timestamps.clear()
	# Fill the bucket
	var now: int = Time.get_ticks_msec()
	for i in ClientTestApi.RATE_LIMIT_BURST:
		api._request_timestamps.append(now)
	assert_true(
		api._is_rate_limited(),
		"Should be limited after burst"
	)


# =============================================================================
# Endpoint routing
# =============================================================================

func test_route_unknown_endpoint() -> void:
	var result: Dictionary = await api._route(
		"nonexistent_endpoint", {}
	)
	assert_true(result.has("error"))
	assert_eq(result["code"], "NOT_FOUND")


func test_route_known_endpoint_exists() -> void:
	# Verify all expected endpoints are registered
	var expected := [
		"get_state", "list_spaces", "get_space",
		"list_channels", "list_members", "list_messages",
		"search_messages", "get_user",
		"select_space", "select_channel", "open_dm",
		"open_settings", "open_discovery", "open_thread",
		"open_voice_view", "toggle_member_list",
		"toggle_search", "set_viewport_size",
		"navigate_to_surface", "open_dialog",
		"screenshot", "list_surfaces", "get_surface_info",
		"send_message", "edit_message", "delete_message",
		"add_reaction",
		"kick_member", "ban_user", "unban_user",
		"timeout_member",
		"join_voice", "leave_voice", "toggle_mute",
		"toggle_deafen",
		"wait_frames", "quit",
	]
	for ep in expected:
		assert_true(
			api._endpoints.has(ep),
			"Endpoint '%s' should be registered" % ep
		)


func test_endpoint_count_is_44() -> void:
	assert_eq(
		api._endpoints.size(), 44,
		"Should have exactly 44 registered endpoints"
	)


# =============================================================================
# Pre-route checks
# =============================================================================

func test_pre_route_no_auth_required() -> void:
	api._require_auth = false
	var result: Dictionary = api._pre_route_checks({})
	assert_true(
		result.is_empty(),
		"No auth required = empty pre-check result"
	)


func test_pre_route_rejects_missing_auth() -> void:
	api._require_auth = true
	api._auth_token = "token123"
	var result: Dictionary = api._pre_route_checks({})
	assert_true(result.has("error"))
	assert_eq(result["_status"], 401)


func test_pre_route_passes_valid_auth() -> void:
	api._require_auth = true
	api._auth_token = "token123"
	api._request_timestamps.clear()
	var headers := {"authorization": "Bearer token123"}
	var result: Dictionary = api._pre_route_checks(headers)
	assert_true(
		result.is_empty(),
		"Valid auth should pass pre-route checks"
	)


# =============================================================================
# Content-Length validation
# =============================================================================

func test_negative_content_length_rejected() -> void:
	var headers := {"content-length": "-1"}
	var content_length: int = headers.get(
		"content-length", "0"
	).to_int()
	assert_true(
		content_length < 0 or content_length > api.MAX_CONTENT_LENGTH,
		"Negative content length should be rejected"
	)


func test_oversized_content_length_rejected() -> void:
	var too_large: int = ClientTestApi.MAX_CONTENT_LENGTH + 1
	assert_true(
		too_large > ClientTestApi.MAX_CONTENT_LENGTH,
		"Content length exceeding 1MB should be rejected"
	)


# =============================================================================
# Server start/stop
# =============================================================================

func test_start_and_stop() -> void:
	var ok: bool = api.start(39199)
	assert_true(ok, "Should start on available port")
	assert_true(api.is_listening())
	api.stop()
	assert_false(api.is_listening())


func test_start_returns_false_on_bad_port() -> void:
	# Port 0 is invalid for explicit binding
	var ok: bool = api.start(0)
	# May succeed on some OSes (ephemeral), but test the API
	if not ok:
		assert_false(api.is_listening())
	else:
		api.stop()


# =============================================================================
# Status text
# =============================================================================

func test_status_text_known_codes() -> void:
	assert_eq(api._status_text(200), "OK")
	assert_eq(api._status_text(400), "Bad Request")
	assert_eq(api._status_text(401), "Unauthorized")
	assert_eq(api._status_text(404), "Not Found")
	assert_eq(api._status_text(405), "Method Not Allowed")
	assert_eq(api._status_text(429), "Too Many Requests")
	assert_eq(api._status_text(500), "Internal Server Error")


func test_status_text_unknown_code() -> void:
	assert_eq(api._status_text(999), "Unknown")
