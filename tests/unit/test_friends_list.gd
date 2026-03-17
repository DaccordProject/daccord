extends GutTest

var component: VBoxContainer


func before_each() -> void:
	# Clear friend book to isolate tests
	Config.friend_book.save_entries([])
	component = load("res://scenes/sidebar/direct/friends_list.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- tab switching ---

func test_initial_tab_is_all() -> void:
	assert_eq(component._current_tab, component.TAB_ALL)


func test_click_online_tab_switches_tab() -> void:
	component.online_btn.pressed.emit()
	assert_eq(component._current_tab, component.TAB_ONLINE)


func test_click_pending_tab_switches_tab() -> void:
	component.pending_btn.pressed.emit()
	assert_eq(component._current_tab, component.TAB_PENDING)


func test_click_blocked_tab_switches_tab() -> void:
	component.blocked_btn.pressed.emit()
	assert_eq(component._current_tab, component.TAB_BLOCKED)


func test_clicking_all_after_switch_returns_to_all() -> void:
	component.online_btn.pressed.emit()
	component.all_btn.pressed.emit()
	assert_eq(component._current_tab, component.TAB_ALL)


# --- empty state (no server connections in tests) ---

func test_empty_label_visible_when_no_friends() -> void:
	assert_true(component.empty_label.visible)


func test_scroll_hidden_when_no_friends() -> void:
	assert_false(component.scroll.visible)


func test_empty_state_in_online_tab() -> void:
	component.online_btn.pressed.emit()
	await get_tree().process_frame
	assert_true(component.empty_label.visible)


func test_empty_state_in_pending_tab() -> void:
	component.pending_btn.pressed.emit()
	await get_tree().process_frame
	assert_true(component.empty_label.visible)


func test_empty_state_in_blocked_tab() -> void:
	component.blocked_btn.pressed.emit()
	await get_tree().process_frame
	assert_true(component.empty_label.visible)


# --- pending badge ---

func test_pending_badge_hidden_when_no_pending() -> void:
	assert_false(component.pending_badge.visible)


# --- signal connections ---

func test_ready_does_not_crash() -> void:
	assert_true(is_instance_valid(component))


func test_has_dm_opened_signal() -> void:
	assert_has_signal(component, "dm_opened")


# --- relationships_updated refresh ---

func test_relationships_updated_signal_does_not_crash() -> void:
	AppState.relationships_updated.emit()
	await get_tree().process_frame
	assert_true(is_instance_valid(component))


# --- friend_request_received switches to pending tab ---

func test_friend_request_received_switches_to_pending() -> void:
	AppState.friend_request_received.emit("u_1")
	assert_eq(component._current_tab, component.TAB_PENDING)
