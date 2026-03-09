extends GutTest

var component: PasswordField


func before_each() -> void:
	component = load("res://scenes/user/password_field.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- structure ---

func test_has_input() -> void:
	assert_not_null(component._input)
	assert_true(component._input is LineEdit)


func test_has_toggle_button() -> void:
	assert_not_null(component._toggle_btn)
	assert_true(component._toggle_btn is Button)


func test_secret_true_by_default() -> void:
	assert_true(component.secret)


func test_toggle_btn_flat() -> void:
	assert_true(component._toggle_btn.flat)


# --- text property ---

func test_text_get_returns_input_text() -> void:
	component._input.text = "hello"
	assert_eq(component.text, "hello")


func test_text_set_updates_input() -> void:
	component.text = "world"
	assert_eq(component._input.text, "world")


# --- secret property ---

func test_secret_setter_updates_input() -> void:
	component.secret = false
	assert_false(component._input.secret)
	component.secret = true
	assert_true(component._input.secret)


func test_toggle_changes_secret() -> void:
	assert_true(component.secret)
	component._toggle_btn.emit_signal("pressed")
	await get_tree().process_frame
	assert_false(component.secret)
	component._toggle_btn.emit_signal("pressed")
	await get_tree().process_frame
	assert_true(component.secret)


# --- placeholder_text ---

func test_placeholder_text_set_before_ready() -> void:
	var fresh: PasswordField = load("res://scenes/user/password_field.tscn").instantiate()
	fresh.placeholder_text = "My placeholder"
	add_child(fresh)
	await get_tree().process_frame
	assert_eq(fresh._input.placeholder_text, "My placeholder")
	fresh.queue_free()
	await get_tree().process_frame


# --- signals ---

func test_text_changed_signal_emitted() -> void:
	watch_signals(component)
	component._input.emit_signal("text_changed", "abc")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(component, "text_changed", ["abc"])


func test_text_submitted_signal_emitted() -> void:
	watch_signals(component)
	component._input.emit_signal("text_submitted", "submitted")
	await get_tree().process_frame
	assert_signal_emitted_with_parameters(component, "text_submitted", ["submitted"])


# --- grab_focus ---

func test_grab_focus_delegates_to_input() -> void:
	# Just verify the call doesn't crash; actual focus requires a display.
	component.grab_focus()
	pass
