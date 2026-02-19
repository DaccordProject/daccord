extends GutTest

var component: HBoxContainer


func before_each() -> void:
	# Ensure Client.current_user is populated for context menu checks
	Client.current_user = {
		"id": "test_user_1",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	component = load("res://scenes/messages/collapsed_message.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _msg_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "m_2",
		"channel_id": "c_1",
		"author": {
			"id": "u_author",
			"display_name": "Alice",
			"username": "alice",
			"color": Color.WHITE,
			"status": 0,
			"avatar": null,
		},
		"content": "Follow-up message",
		"timestamp": "Today at 10:31 AM",
		"edited": false,
		"reactions": [],
		"reply_to": "",
		"embed": {},
		"embeds": [],
		"attachments": [],
		"system": false,
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_populates_content() -> void:
	component.setup(_msg_data())
	# message_content child should have been set up
	assert_true(is_instance_valid(component.message_content))


func test_timestamp_extraction() -> void:
	component.setup(_msg_data({"timestamp": "Today at 10:31 AM"}))
	# Extracts short time: "Today at 10:31 AM" -> parts[2] = "10:31"
	assert_eq(component.timestamp_label.text, "10:31")


func test_has_context_menu_requested_signal() -> void:
	assert_true(component.has_signal("context_menu_requested"))


func test_context_menu_signal_emits_on_right_click() -> void:
	component.setup(_msg_data())
	watch_signals(component)
	component._emit_context_menu(Vector2i(100, 200))
	assert_signal_emitted(component, "context_menu_requested")


func test_timestamp_hidden_initially() -> void:
	# Before setup, timestamp should be hidden (set in _ready)
	assert_false(component.timestamp_label.visible)


func test_setup_stores_message_data() -> void:
	var data := _msg_data()
	component.setup(data)
	assert_eq(component._message_data["id"], "m_2")
	assert_eq(component._message_data["content"], "Follow-up message")
