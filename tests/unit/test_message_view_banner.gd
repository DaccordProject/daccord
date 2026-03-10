extends GutTest

## Unit tests for MessageViewBanner.
## MessageViewBanner is a RefCounted class that wraps UI nodes (PanelContainer,
## Label, Button, Timer) and a space-lookup Callable.

var banner: MessageViewBanner
var panel: PanelContainer
var label: Label
var retry_btn: Button
var timer: Timer
var _current_space_id: String = "g_1"


func before_each() -> void:
	panel = PanelContainer.new()
	label = Label.new()
	retry_btn = Button.new()
	timer = Timer.new()
	add_child(panel)
	add_child(label)
	add_child(retry_btn)
	add_child(timer)
	await get_tree().process_frame
	banner = MessageViewBanner.new(
		panel,
		label,
		retry_btn,
		timer,
		func() -> String: return _current_space_id,
	)


func after_each() -> void:
	banner = null
	for node: Node in [panel, label, retry_btn, timer]:
		if is_instance_valid(node):
			node.queue_free()
	await get_tree().process_frame


# --- on_server_disconnected ---

func test_disconnected_shows_banner_for_matching_space() -> void:
	_current_space_id = "g_1"
	banner.on_server_disconnected("g_1", 1000, "")
	assert_true(panel.visible)


func test_disconnected_ignores_different_space() -> void:
	_current_space_id = "g_1"
	panel.visible = false
	banner.on_server_disconnected("g_other", 1000, "")
	assert_false(panel.visible)


func test_disconnected_hides_retry_button() -> void:
	_current_space_id = "g_1"
	banner.on_server_disconnected("g_1", 1001, "")
	assert_false(retry_btn.visible)


func test_disconnected_sets_status_text() -> void:
	_current_space_id = "g_1"
	banner.on_server_disconnected("g_1", 4004, "")
	assert_true(label.text.length() > 0)
	assert_true(label.text.contains("Session expired"))


func test_disconnected_uses_fallback_reason() -> void:
	_current_space_id = "g_1"
	banner.on_server_disconnected("g_1", 9999, "Custom reason")
	assert_true(label.text.contains("Custom reason"))


func test_disconnected_defaults_to_connection_lost() -> void:
	_current_space_id = "g_1"
	banner.on_server_disconnected("g_1", 9999, "")
	assert_true(label.text.contains("Connection lost"))


# --- on_server_reconnecting ---

func test_reconnecting_shows_banner() -> void:
	_current_space_id = "g_1"
	banner.on_server_reconnecting("g_1", 2, 5)
	assert_true(panel.visible)


func test_reconnecting_ignores_different_space() -> void:
	_current_space_id = "g_1"
	panel.visible = false
	banner.on_server_reconnecting("g_other", 1, 5)
	assert_false(panel.visible)


func test_reconnecting_shows_attempt_info() -> void:
	_current_space_id = "g_1"
	banner.on_server_reconnecting("g_1", 3, 10)
	assert_true(label.text.contains("3"))
	assert_true(label.text.contains("10"))


func test_reconnecting_hides_retry_button() -> void:
	_current_space_id = "g_1"
	banner.on_server_reconnecting("g_1", 1, 5)
	assert_false(retry_btn.visible)


# --- on_server_reconnected ---

func test_reconnected_shows_banner() -> void:
	_current_space_id = "g_1"
	banner.on_server_reconnected("g_1")
	assert_true(panel.visible)


func test_reconnected_ignores_different_space() -> void:
	_current_space_id = "g_1"
	panel.visible = false
	banner.on_server_reconnected("g_other")
	assert_false(panel.visible)


# --- on_server_synced ---

func test_synced_shows_banner_and_starts_timer() -> void:
	_current_space_id = "g_1"
	banner.on_server_synced("g_1")
	assert_true(panel.visible)


func test_synced_ignores_different_space() -> void:
	_current_space_id = "g_1"
	panel.visible = false
	banner.on_server_synced("g_other")
	assert_false(panel.visible)


func test_synced_sets_reconnected_text() -> void:
	_current_space_id = "g_1"
	banner.on_server_synced("g_1")
	assert_true(label.text.contains("Reconnected"))


# --- on_server_connection_failed ---

func test_connection_failed_shows_banner() -> void:
	_current_space_id = "g_1"
	banner.on_server_connection_failed("g_1", "timeout")
	assert_true(panel.visible)


func test_connection_failed_ignores_different_space() -> void:
	_current_space_id = "g_1"
	panel.visible = false
	banner.on_server_connection_failed("g_other", "timeout")
	assert_false(panel.visible)


func test_connection_failed_shows_retry_button() -> void:
	_current_space_id = "g_1"
	banner.on_server_connection_failed("g_1", "timeout")
	assert_true(retry_btn.visible)


func test_connection_failed_includes_reason_in_label() -> void:
	_current_space_id = "g_1"
	banner.on_server_connection_failed("g_1", "timeout")
	assert_true(label.text.contains("timeout"))


# --- _code_to_message static ---

func test_code_4003_returns_auth_failed() -> void:
	assert_eq(MessageViewBanner._code_to_message(4003), "Authentication failed")


func test_code_4004_returns_session_expired() -> void:
	assert_eq(MessageViewBanner._code_to_message(4004), "Session expired")


func test_code_1000_returns_server_closed() -> void:
	assert_eq(MessageViewBanner._code_to_message(1000), "Server closed connection")


func test_unknown_code_returns_empty_string() -> void:
	assert_eq(MessageViewBanner._code_to_message(9999), "")
