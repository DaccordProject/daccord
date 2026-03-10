extends GutTest

## Unit tests for ThreadPanel component.
##
## ThreadPanel uses @onready nodes, so it must be instantiated from its scene
## file. Tests focus on structural presence, initial state, and behaviors that
## do not require a live server connection (close, send guard, signal wiring).

var component: PanelContainer


func before_each() -> void:
	# Ensure Client.current_user is populated to avoid null lookups.
	Client.current_user = {
		"id": "u_test",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	component = load("res://scenes/messages/thread_panel.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# UI structure
# ---------------------------------------------------------------------------

func test_has_thread_title_label() -> void:
	assert_not_null(component.thread_title)
	assert_true(component.thread_title is Label)


func test_has_close_button() -> void:
	assert_not_null(component.close_button)
	assert_true(component.close_button is Button)


func test_has_send_button() -> void:
	assert_not_null(component.send_button)
	assert_true(component.send_button is Button)


func test_has_thread_input() -> void:
	assert_not_null(component.thread_input)
	assert_true(component.thread_input is TextEdit)


func test_has_reply_count_label() -> void:
	assert_not_null(component.reply_count_label)
	assert_true(component.reply_count_label is Label)


func test_has_notify_button() -> void:
	assert_not_null(component.notify_button)
	assert_true(component.notify_button is Button)


func test_has_also_send_check() -> void:
	assert_not_null(component.also_send_check)
	assert_true(component.also_send_check is CheckBox)


# ---------------------------------------------------------------------------
# Thread closed state
# ---------------------------------------------------------------------------

func test_thread_closed_hides_panel() -> void:
	## _on_thread_closed() must set visible = false.
	component._on_thread_closed()
	assert_false(component.visible)


func test_thread_closed_clears_parent_message_id() -> void:
	component._parent_message_id = "m_old"
	component._on_thread_closed()
	assert_eq(component._parent_message_id, "")


func test_thread_closed_clears_parent_channel_id() -> void:
	component._parent_channel_id = "c_old"
	component._on_thread_closed()
	assert_eq(component._parent_channel_id, "")


# ---------------------------------------------------------------------------
# Send — empty input guard
# ---------------------------------------------------------------------------

func test_send_does_not_crash_with_empty_input() -> void:
	## _on_send() must silently return when thread_input is empty.
	component.thread_input.text = ""
	component._on_send()
	# If we reach here without error the guard worked.
	assert_true(true)


func test_send_clears_input_after_non_empty_text() -> void:
	## After a successful send, the input must be cleared.
	## We set a channel ID so the Client.send_message_to_channel path runs.
	component._parent_channel_id = "c_1"
	component._parent_message_id = "m_1"
	component.thread_input.text = "Hello thread"
	component._on_send()
	assert_eq(component.thread_input.text, "")


# ---------------------------------------------------------------------------
# Close — AppState.close_thread() wired to close_button
# ---------------------------------------------------------------------------

func test_close_button_is_connected() -> void:
	## The close_button pressed signal should have at least one connection.
	assert_true(component.close_button.pressed.get_connections().size() > 0)


# ---------------------------------------------------------------------------
# AppState signal connections
# ---------------------------------------------------------------------------

func test_connected_to_thread_opened() -> void:
	assert_true(AppState.thread_opened.is_connected(component._on_thread_opened))


func test_connected_to_thread_closed() -> void:
	assert_true(AppState.thread_closed.is_connected(component._on_thread_closed))


func test_connected_to_thread_messages_updated() -> void:
	assert_true(
		AppState.thread_messages_updated.is_connected(
			component._on_thread_messages_updated
		)
	)
