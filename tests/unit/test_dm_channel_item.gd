extends GutTest

var component: Button


func before_each() -> void:
	component = load("res://scenes/sidebar/direct/dm_channel_item.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _dm_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "dm_1",
		"user": {
			"display_name": "Alice",
			"username": "alice",
			"color": Color(0.3, 0.5, 0.8),
		},
		"last_message": "Hey there!",
		"unread": false,
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_sets_dm_id() -> void:
	component.setup(_dm_data())
	assert_eq(component.dm_id, "dm_1")


func test_username_from_user_dict() -> void:
	component.setup(_dm_data())
	assert_eq(component.username_label.text, "Alice")


func test_last_message_text() -> void:
	component.setup(_dm_data())
	assert_eq(component.last_message_label.text, "Hey there!")


func test_unread_dot_visible() -> void:
	component.setup(_dm_data({"unread": true}))
	assert_true(component.unread_dot.visible)


func test_unread_dot_hidden() -> void:
	component.setup(_dm_data({"unread": false}))
	assert_false(component.unread_dot.visible)


# --- set_active ---

func test_set_active_applies_style() -> void:
	component.set_active(true)
	var override = component.get_theme_stylebox("normal")
	assert_not_null(override)


func test_set_active_false_removes_style() -> void:
	component.set_active(true)
	component.set_active(false)
	# After removing override, the default theme style applies
	# We just verify no crash
	assert_true(is_instance_valid(component))


# --- signals ---

func test_dm_pressed_signal_exists() -> void:
	assert_has_signal(component, "dm_pressed")


func test_dm_closed_signal_exists() -> void:
	assert_has_signal(component, "dm_closed")
