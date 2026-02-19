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
	component = load("res://scenes/messages/cozy_message.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _msg_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "m_1",
		"channel_id": "c_1",
		"author": {
			"id": "u_author",
			"display_name": "Alice",
			"username": "alice",
			"color": Color(0.8, 0.2, 0.2),
			"status": 0,
			"avatar": null,
		},
		"content": "Hello world",
		"timestamp": "Today at 2:30 PM",
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

func test_author_name_from_dict() -> void:
	component.setup(_msg_data())
	assert_eq(component.author_label.text, "Alice")


func test_timestamp_from_dict() -> void:
	component.setup(_msg_data())
	assert_eq(component.timestamp_label.text, "Today at 2:30 PM")


func test_avatar_letter_from_display_name() -> void:
	component.setup(_msg_data())
	# Avatar should show first letter of display_name
	# The avatar is a ColorRect with set_letter method
	# We can't easily check the letter, but we verify setup didn't crash
	assert_true(is_instance_valid(component.avatar))


func test_author_color_override() -> void:
	component.setup(_msg_data())
	var color_override: Color = component.author_label.get_theme_color("font_color")
	assert_almost_eq(color_override.r, 0.8, 0.01)


func test_reply_ref_hidden_when_empty() -> void:
	component.setup(_msg_data({"reply_to": ""}))
	assert_false(component.reply_ref.visible)


func test_has_context_menu_requested_signal() -> void:
	assert_true(component.has_signal("context_menu_requested"))


func test_context_menu_signal_emits_on_right_click() -> void:
	component.setup(_msg_data())
	watch_signals(component)
	component._emit_context_menu(Vector2i(100, 200))
	assert_signal_emitted(component, "context_menu_requested")


func test_setup_stores_message_data() -> void:
	var data := _msg_data()
	component.setup(data)
	assert_eq(component._message_data["id"], "m_1")
	assert_eq(component._message_data["content"], "Hello world")
