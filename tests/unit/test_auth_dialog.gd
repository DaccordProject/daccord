extends GutTest

var dialog: ColorRect


func before_each() -> void:
	dialog = load("res://scenes/sidebar/guild_bar/auth_dialog.tscn").instantiate()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame


# --- UI structure ---

func test_dialog_has_username_input() -> void:
	assert_not_null(dialog._username_input)


func test_dialog_has_password_input() -> void:
	assert_not_null(dialog._password_input)
	assert_true(dialog._password_input.secret)


func test_dialog_has_display_name_input() -> void:
	assert_not_null(dialog._display_name_input)


func test_dialog_has_submit_button() -> void:
	assert_not_null(dialog._submit_btn)


func test_dialog_error_label_hidden_initially() -> void:
	assert_false(dialog._error_label.visible)


func test_dialog_has_mode_toggle_buttons() -> void:
	assert_not_null(dialog._sign_in_btn)
	assert_not_null(dialog._register_btn)


# --- Mode toggling ---

func test_initial_mode_is_sign_in() -> void:
	assert_eq(dialog._submit_btn.text, "Sign In")
	assert_true(dialog._sign_in_btn.disabled)
	assert_false(dialog._register_btn.disabled)
	assert_false(dialog._display_name_label.visible)
	assert_false(dialog._display_name_input.visible)


func test_switch_to_register_mode() -> void:
	dialog._register_btn.pressed.emit()
	await get_tree().process_frame
	assert_eq(dialog._submit_btn.text, "Register")
	assert_false(dialog._sign_in_btn.disabled)
	assert_true(dialog._register_btn.disabled)
	assert_true(dialog._display_name_label.visible)
	assert_true(dialog._display_name_input.visible)


func test_switch_back_to_sign_in_mode() -> void:
	dialog._register_btn.pressed.emit()
	await get_tree().process_frame
	dialog._sign_in_btn.pressed.emit()
	await get_tree().process_frame
	assert_eq(dialog._submit_btn.text, "Sign In")
	assert_true(dialog._sign_in_btn.disabled)
	assert_false(dialog._register_btn.disabled)
	assert_false(dialog._display_name_label.visible)
	assert_false(dialog._display_name_input.visible)


# --- Validation ---

func test_empty_username_shows_error() -> void:
	dialog._username_input.text = ""
	dialog._password_input.text = "password123"
	dialog._on_submit()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "Username")


func test_empty_password_shows_error() -> void:
	dialog._username_input.text = "testuser"
	dialog._password_input.text = ""
	dialog._on_submit()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "Password")


# --- Signal ---

func test_auth_completed_signal_exists() -> void:
	assert_has_signal(dialog, "auth_completed")


# --- Close behavior ---

func test_close_frees_dialog() -> void:
	dialog._close()
	await get_tree().process_frame
	assert_false(is_instance_valid(dialog))
