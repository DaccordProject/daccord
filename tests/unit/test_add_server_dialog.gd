extends GutTest

var dialog: ColorRect


func before_each() -> void:
	dialog = load("res://scenes/sidebar/guild_bar/add_server_dialog.tscn").instantiate()
	add_child(dialog)
	# Wait for _ready() to complete (it awaits one frame for focus)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame


# --- UI structure ---

func test_dialog_has_url_input() -> void:
	assert_not_null(dialog._url_input)
	assert_eq(dialog._url_input.placeholder_text, "example.com or example.com?invite=CODE")


func test_dialog_has_add_button() -> void:
	assert_not_null(dialog._add_btn)
	assert_eq(dialog._add_btn.text, "Add")


func test_dialog_error_label_hidden_initially() -> void:
	assert_false(dialog._error_label.visible)


# --- Validation ---

func test_empty_url_shows_error() -> void:
	dialog._url_input.text = ""
	dialog._on_add_pressed()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "server URL")


func test_whitespace_only_url_shows_error() -> void:
	dialog._url_input.text = "   "
	dialog._on_add_pressed()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "server URL")


# --- URL parsing ---

func test_parse_bare_host() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com")
	assert_eq(r["base_url"], "https://example.com")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "")


func test_parse_host_with_port() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com:8080")
	assert_eq(r["base_url"], "https://example.com:8080")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "")


func test_parse_host_with_http_protocol() -> void:
	var r: Dictionary = dialog.parse_server_url("http://example.com")
	assert_eq(r["base_url"], "http://example.com")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "")


func test_parse_host_with_https_protocol() -> void:
	var r: Dictionary = dialog.parse_server_url("https://example.com:443")
	assert_eq(r["base_url"], "https://example.com:443")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "")


func test_parse_host_with_space() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com#my-guild")
	assert_eq(r["base_url"], "https://example.com")
	assert_eq(r["space_name"], "my-guild")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "")


func test_parse_host_with_token() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com?token=abc123")
	assert_eq(r["base_url"], "https://example.com")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "abc123")
	assert_eq(r["invite_code"], "")


func test_parse_full_url() -> void:
	var r: Dictionary = dialog.parse_server_url("http://example.com:3000#my-guild?token=abc123")
	assert_eq(r["base_url"], "http://example.com:3000")
	assert_eq(r["space_name"], "my-guild")
	assert_eq(r["token"], "abc123")
	assert_eq(r["invite_code"], "")


func test_parse_empty_fragment_defaults_to_general() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com#")
	assert_eq(r["space_name"], "general")


func test_parse_strips_whitespace() -> void:
	var r: Dictionary = dialog.parse_server_url("  example.com  ")
	assert_eq(r["base_url"], "https://example.com")


func test_parse_host_with_invite() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com?invite=ABCDEF")
	assert_eq(r["base_url"], "https://example.com")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "")
	assert_eq(r["invite_code"], "ABCDEF")


func test_parse_host_with_token_and_invite() -> void:
	var r: Dictionary = dialog.parse_server_url("example.com?token=abc123&invite=XYZ")
	assert_eq(r["base_url"], "https://example.com")
	assert_eq(r["space_name"], "general")
	assert_eq(r["token"], "abc123")
	assert_eq(r["invite_code"], "XYZ")


# --- Close behavior ---

func test_close_frees_dialog() -> void:
	dialog._close()
	await get_tree().process_frame
	assert_false(is_instance_valid(dialog))


func test_server_added_signal_exists() -> void:
	assert_has_signal(dialog, "server_added")
