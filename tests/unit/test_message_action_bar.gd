extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var component: PanelContainer


func before_each() -> void:
	Client.current_user = {
		"id": "my_user_1",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	# Ensure no stale space mappings interfere
	Client._channel_to_space.clear()
	component = load("res://scenes/messages/message_action_bar.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- signals ---

func test_has_action_reply_signal() -> void:
	assert_true(component.has_signal("action_reply"))


func test_has_action_edit_signal() -> void:
	assert_true(component.has_signal("action_edit"))


func test_has_action_delete_signal() -> void:
	assert_true(component.has_signal("action_delete"))


func test_has_action_thread_signal() -> void:
	assert_true(component.has_signal("action_thread"))


# --- buttons exist ---

func test_react_button_exists() -> void:
	assert_true(is_instance_valid(component.react_btn))


func test_reply_button_exists() -> void:
	assert_true(is_instance_valid(component.reply_btn))


func test_edit_button_exists() -> void:
	assert_true(is_instance_valid(component.edit_btn))


func test_delete_button_exists() -> void:
	assert_true(is_instance_valid(component.delete_btn))


func test_thread_button_exists() -> void:
	assert_true(is_instance_valid(component.thread_btn))


# --- visibility for other-user messages ---

func test_edit_hidden_for_other_user_no_permissions() -> void:
	# author id differs from current_user; no manage perms configured
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "other_user"}),
	})
	component.show_for_message(component, msg)
	assert_false(component.edit_btn.visible)


func test_delete_hidden_for_other_user_no_permissions() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "other_user"}),
	})
	component.show_for_message(component, msg)
	assert_false(component.delete_btn.visible)


# --- visibility for own messages ---

func test_edit_visible_for_own_message() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "my_user_1"}),
	})
	component.show_for_message(component, msg)
	assert_true(component.edit_btn.visible)


func test_delete_visible_for_own_message() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "my_user_1"}),
	})
	component.show_for_message(component, msg)
	assert_true(component.delete_btn.visible)


# --- signal emission ---

func test_reply_button_emits_action_reply() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({"channel_id": "c_1"})
	component.show_for_message(component, msg)
	watch_signals(component)
	component.reply_btn.pressed.emit()
	assert_signal_emitted(component, "action_reply")


func test_edit_button_emits_action_edit() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "my_user_1"}),
	})
	component.show_for_message(component, msg)
	watch_signals(component)
	component.edit_btn.pressed.emit()
	assert_signal_emitted(component, "action_edit")


func test_delete_button_emits_action_delete() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({
		"channel_id": "c_1",
		"author": TestDataFactory.user_data({"id": "my_user_1"}),
	})
	component.show_for_message(component, msg)
	watch_signals(component)
	component.delete_btn.pressed.emit()
	assert_signal_emitted(component, "action_delete")


# --- show/hide ---

func test_show_for_message_makes_bar_visible() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({"channel_id": "c_1"})
	component.show_for_message(component, msg)
	assert_true(component.visible)


func test_hide_bar_hides_component() -> void:
	var msg: Dictionary = TestDataFactory.msg_data({"channel_id": "c_1"})
	component.show_for_message(component, msg)
	component.hide_bar()
	# Give reduced-motion path time (bar becomes invisible immediately)
	await get_tree().process_frame
	# Either visible=false or animation in progress; verify not still showing
	# We can't rely on tween timing, so test the get_message_node() is cleared
	assert_null(component.get_message_node())
