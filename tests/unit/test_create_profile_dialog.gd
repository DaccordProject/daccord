extends GutTest

var dialog: ColorRect


func before_each() -> void:
	dialog = load("res://scenes/user/create_profile_dialog.tscn").instantiate()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame


# --- UI structure ---

func test_has_name_input() -> void:
	assert_not_null(dialog._name_input)
	assert_true(dialog._name_input is LineEdit)


func test_has_password_input() -> void:
	assert_not_null(dialog._password_input)


func test_has_confirm_input() -> void:
	assert_not_null(dialog._confirm_input)


func test_has_create_button() -> void:
	assert_not_null(dialog._create_btn)
	assert_true(dialog._create_btn is Button)


func test_has_error_label() -> void:
	assert_not_null(dialog._error_label)


func test_error_label_hidden_initially() -> void:
	assert_false(dialog._error_label.visible)


func test_confirm_input_hidden_initially() -> void:
	assert_false(dialog._confirm_input.visible)


func test_confirm_label_hidden_initially() -> void:
	assert_false(dialog._confirm_label.visible)


# --- signals ---

func test_has_profile_created_signal() -> void:
	assert_has_signal(dialog, "profile_created")


# --- validation: empty name ---

func test_empty_name_shows_error() -> void:
	dialog._name_input.text = ""
	dialog._on_create()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "required")


func test_empty_name_does_not_emit_signal() -> void:
	watch_signals(dialog)
	dialog._name_input.text = ""
	dialog._on_create()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "profile_created")


# --- validation: name too long ---

func test_name_too_long_shows_error() -> void:
	dialog._name_input.text = "a".repeat(33)
	dialog._on_create()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "32")


func test_name_at_max_length_clears_error_path() -> void:
	# 32 chars is valid — error label should NOT be shown for length reason
	# (may still fail later if Config.profiles is called, but validation passes)
	dialog._name_input.text = "a".repeat(32)
	# No password — would pass length validation
	# We only assert the length error is NOT triggered
	dialog._error_label.visible = false
	dialog._on_create()
	await get_tree().process_frame
	if dialog._error_label.visible:
		assert_false(
			dialog._error_label.text.contains("32"),
			"A 32-char name should not trigger the length error"
		)


# --- validation: password mismatch ---

func test_password_mismatch_shows_error() -> void:
	dialog._name_input.text = "Test Profile"
	dialog._password_input.text = "secret"
	dialog._confirm_input.text = "different"
	dialog._on_create()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "match")


func test_password_mismatch_does_not_emit_signal() -> void:
	watch_signals(dialog)
	dialog._name_input.text = "Test Profile"
	dialog._password_input.text = "secret"
	dialog._confirm_input.text = "different"
	dialog._on_create()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "profile_created")


# --- password visibility toggle ---

func test_password_typed_shows_confirm_fields() -> void:
	dialog._password_input.emit_signal("text_changed", "hello")
	await get_tree().process_frame
	assert_true(dialog._confirm_label.visible)
	assert_true(dialog._confirm_input.visible)


func test_password_cleared_hides_confirm_fields() -> void:
	dialog._password_input.emit_signal("text_changed", "hello")
	await get_tree().process_frame
	dialog._password_input.emit_signal("text_changed", "")
	await get_tree().process_frame
	assert_false(dialog._confirm_label.visible)
	assert_false(dialog._confirm_input.visible)
