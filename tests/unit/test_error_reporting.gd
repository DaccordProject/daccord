extends GutTest

var er: Node


func before_each() -> void:
	er = load("res://scripts/autoload/error_reporting.gd").new()
	add_child(er)


func after_each() -> void:
	remove_child(er)
	er.free()


# =============================================================================
# 1. Guard clauses -- Sentry is NOT initialized in tests
# =============================================================================

func test_not_initialized_by_default() -> void:
	assert_false(er._initialized,
		"Should not be initialized without calling init_sentry()")


func test_add_breadcrumb_returns_early_when_not_initialized() -> void:
	# Should not crash -- the _initialized guard prevents SentrySDK calls
	er._add_breadcrumb("test message", "test")
	assert_false(er._initialized,
		"Still not initialized after _add_breadcrumb")


func test_update_context_returns_early_when_not_initialized() -> void:
	er.update_context()
	assert_false(er._initialized,
		"Still not initialized after update_context")


func test_report_problem_returns_early_when_not_initialized() -> void:
	er.report_problem("something broke")
	assert_false(er._initialized,
		"Still not initialized after report_problem")


# =============================================================================
# 2. Signal handlers -- should not crash when not initialized
# =============================================================================

func test_on_guild_selected_no_crash() -> void:
	er._on_guild_selected("guild_123")
	pass_test("No crash")


func test_on_channel_selected_no_crash() -> void:
	er._on_channel_selected("chan_456")
	pass_test("No crash")


func test_on_dm_mode_entered_no_crash() -> void:
	er._on_dm_mode_entered()
	pass_test("No crash")


func test_on_message_sent_no_crash() -> void:
	er._on_message_sent("hello world")
	pass_test("No crash")


func test_on_reply_initiated_no_crash() -> void:
	er._on_reply_initiated("msg_789")
	pass_test("No crash")


func test_on_layout_mode_changed_compact_no_crash() -> void:
	er._on_layout_mode_changed(AppState.LayoutMode.COMPACT)
	pass_test("No crash")


func test_on_layout_mode_changed_medium_no_crash() -> void:
	er._on_layout_mode_changed(AppState.LayoutMode.MEDIUM)
	pass_test("No crash")


func test_on_layout_mode_changed_full_no_crash() -> void:
	er._on_layout_mode_changed(AppState.LayoutMode.FULL)
	pass_test("No crash")


func test_on_sidebar_drawer_toggled_no_crash() -> void:
	er._on_sidebar_drawer_toggled(true)
	er._on_sidebar_drawer_toggled(false)
	pass_test("No crash")


# =============================================================================
# 3. PII scrubbing
# =============================================================================

func test_scrub_bearer_token() -> void:
	var input := "Error: Bearer eyJhbGciOi.secret_token in request"
	var result: String = er.scrub_pii_text(input)
	assert_string_contains(result, "Bearer [REDACTED]")
	assert_false(result.contains("eyJhbGciOi"),
		"Token should be redacted")


func test_scrub_multiple_bearer_tokens() -> void:
	var input := "Bearer abc.123 and Bearer def.456"
	var result: String = er.scrub_pii_text(input)
	assert_eq(result, "Bearer [REDACTED] and Bearer [REDACTED]")


func test_scrub_token_query_param() -> void:
	var input := "GET /api?token=secret123&other=val"
	var result: String = er.scrub_pii_text(input)
	assert_string_contains(result, "token=[REDACTED]")
	assert_false(result.contains("secret123"),
		"Token value should be redacted")
	assert_string_contains(result, "&other=val",
		"Other params should be preserved")


func test_scrub_url_with_port() -> void:
	var input := "Connected to https://192.168.1.100:39099/api/v1"
	var result: String = er.scrub_pii_text(input)
	assert_string_contains(result, "[URL REDACTED]")
	assert_false(result.contains("192.168.1.100"),
		"Server IP should be redacted")


func test_scrub_http_url_with_port() -> void:
	var input := "Error at http://myserver.com:8080/path"
	var result: String = er.scrub_pii_text(input)
	assert_string_contains(result, "[URL REDACTED]")
	assert_false(result.contains("myserver.com"),
		"Server hostname should be redacted")


func test_scrub_preserves_plain_text() -> void:
	var input := "Something went wrong with the parser"
	var result: String = er.scrub_pii_text(input)
	assert_eq(result, input,
		"Plain text without PII should be unchanged")


func test_scrub_combined_pii() -> void:
	var input := "Bearer my.token at https://server:39099/api?token=abc"
	var result: String = er.scrub_pii_text(input)
	assert_false(result.contains("my.token"),
		"Bearer token should be redacted")
	assert_false(result.contains("server"),
		"URL should be redacted")
	assert_false(result.contains("abc"),
		"Query token should be redacted")
