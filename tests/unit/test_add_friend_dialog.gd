extends GutTest

var component: ColorRect


func before_each() -> void:
	component = load("res://scenes/sidebar/direct/add_friend_dialog.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- structure ---

func test_has_username_input() -> void:
	assert_not_null(component._username_input)
	assert_true(component._username_input is LineEdit)


func test_has_send_button() -> void:
	assert_not_null(component._send_btn)
	assert_true(component._send_btn is Button)


func test_has_error_label() -> void:
	assert_not_null(component._error_label)
	assert_true(component._error_label is Label)


func test_error_label_hidden_on_open() -> void:
	assert_false(component._error_label.visible)


# --- empty input validation ---

func test_send_with_empty_input_shows_error() -> void:
	component._username_input.text = ""
	component._on_send()
	assert_true(component._error_label.visible)


func test_send_with_empty_input_error_message() -> void:
	component._username_input.text = ""
	component._on_send()
	assert_string_contains(component._error_label.text, "Please enter")


# --- user not found ---

func test_send_with_unknown_username_shows_error() -> void:
	component._username_input.text = "nonexistent_user_xyz_99"
	component._on_send()
	assert_true(component._error_label.visible)


func test_send_with_unknown_username_error_message() -> void:
	component._username_input.text = "nonexistent_user_xyz_99"
	component._on_send()
	assert_string_contains(component._error_label.text, "not found")


# --- error clears on retry ---

func test_error_clears_before_new_attempt() -> void:
	component._username_input.text = ""
	component._on_send()
	assert_true(component._error_label.visible)
	# Subsequent call with different input clears and re-evaluates
	component._username_input.text = "another_missing_user"
	component._on_send()
	# Should now show "not found" (empty error was cleared, new one set)
	assert_string_contains(component._error_label.text, "not found")
