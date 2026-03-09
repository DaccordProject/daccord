extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var component: HBoxContainer


func before_each() -> void:
	component = load("res://scenes/sidebar/direct/friend_item.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _rel_data(overrides: Dictionary = {}) -> Dictionary:
	return TestDataFactory.rel_data(overrides)


# --- setup: display name ---

func test_setup_sets_name_label() -> void:
	component.setup(_rel_data())
	assert_eq(component.name_label.text, "Alice")


func test_setup_empty_user_shows_unknown() -> void:
	component.setup(_rel_data({"user": {}}))
	assert_eq(component.name_label.text, "Unknown")


# --- setup: status label text ---

func test_setup_friend_shows_status_label() -> void:
	component.setup(_rel_data({"type": 1}))
	assert_ne(component.status_label.text, "")


func test_setup_blocked_shows_blocked_label() -> void:
	component.setup(_rel_data({"type": 2}))
	assert_eq(component.status_label.text, "Blocked")


func test_setup_pending_incoming_shows_label() -> void:
	component.setup(_rel_data({"type": 3}))
	assert_eq(component.status_label.text, "Incoming Friend Request")


func test_setup_pending_outgoing_shows_label() -> void:
	component.setup(_rel_data({"type": 4}))
	assert_eq(component.status_label.text, "Outgoing Friend Request")


# --- setup: action buttons ---

func _get_button_labels() -> Array:
	var labels: Array = []
	for child in component.action_box.get_children():
		if child is Button:
			labels.append(child.text)
	return labels


func test_friend_has_message_button() -> void:
	component.setup(_rel_data({"type": 1}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Message"))


func test_friend_has_remove_button() -> void:
	component.setup(_rel_data({"type": 1}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Remove"))


func test_friend_has_block_button() -> void:
	component.setup(_rel_data({"type": 1}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Block"))


func test_blocked_has_unblock_button() -> void:
	component.setup(_rel_data({"type": 2}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Unblock"))


func test_blocked_has_no_message_button() -> void:
	component.setup(_rel_data({"type": 2}))
	await get_tree().process_frame
	assert_false(_get_button_labels().has("Message"))


func test_pending_incoming_has_accept_button() -> void:
	component.setup(_rel_data({"type": 3}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Accept"))


func test_pending_incoming_has_decline_button() -> void:
	component.setup(_rel_data({"type": 3}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Decline"))


func test_pending_outgoing_has_cancel_button() -> void:
	component.setup(_rel_data({"type": 4}))
	await get_tree().process_frame
	assert_true(_get_button_labels().has("Cancel"))


func test_pending_outgoing_has_no_accept_button() -> void:
	component.setup(_rel_data({"type": 4}))
	await get_tree().process_frame
	assert_false(_get_button_labels().has("Accept"))


# --- signals ---

func test_has_message_pressed_signal() -> void:
	assert_has_signal(component, "message_pressed")


func test_has_remove_pressed_signal() -> void:
	assert_has_signal(component, "remove_pressed")


func test_has_block_pressed_signal() -> void:
	assert_has_signal(component, "block_pressed")


func test_has_accept_pressed_signal() -> void:
	assert_has_signal(component, "accept_pressed")


func test_has_decline_pressed_signal() -> void:
	assert_has_signal(component, "decline_pressed")


func test_has_cancel_pressed_signal() -> void:
	assert_has_signal(component, "cancel_pressed")


func test_has_unblock_pressed_signal() -> void:
	assert_has_signal(component, "unblock_pressed")
