extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var component: PanelContainer


func before_each() -> void:
	Client.current_user = {
		"id": "test_user_1",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	Client._dm_channel_cache = {}
	component = load("res://scenes/sidebar/direct/dm_list.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame
	Client._dm_channel_cache = {}


# --- signal declaration ---

func test_dm_selected_signal_exists() -> void:
	assert_has_signal(component, "dm_selected")


# --- initial tab state ---

func test_initial_mode_shows_friends_list() -> void:
	assert_true(component.friends_list.visible)


func test_initial_mode_hides_dm_panel() -> void:
	assert_false(component.dm_panel.visible)


# --- _set_friends_mode ---

func test_set_friends_mode_false_shows_dm_panel() -> void:
	component._set_friends_mode(false)
	assert_true(component.dm_panel.visible)


func test_set_friends_mode_false_hides_friends_list() -> void:
	component._set_friends_mode(false)
	assert_false(component.friends_list.visible)


func test_set_friends_mode_true_restores_friends_list() -> void:
	component._set_friends_mode(false)
	component._set_friends_mode(true)
	assert_true(component.friends_list.visible)


func test_set_friends_mode_true_hides_dm_panel() -> void:
	component._set_friends_mode(false)
	component._set_friends_mode(true)
	assert_false(component.dm_panel.visible)


# --- _populate_dms ---

func test_populate_dms_creates_items_for_each_channel() -> void:
	Client._dm_channel_cache = {
		"dm_1": TestDataFactory.dm_data({"id": "dm_1"}),
		"dm_2": TestDataFactory.dm_data({"id": "dm_2",
			"user": {"display_name": "Bob", "username": "bob",
				"color": Color.WHITE}}),
	}
	component._populate_dms()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(component.dm_vbox.get_child_count(), 2)


func test_populate_dms_with_empty_cache_clears_vbox() -> void:
	Client._dm_channel_cache = {
		"dm_1": TestDataFactory.dm_data({"id": "dm_1"}),
	}
	component._populate_dms()
	await get_tree().process_frame
	Client._dm_channel_cache = {}
	component._populate_dms()
	await get_tree().process_frame
	assert_eq(component.dm_vbox.get_child_count(), 0)


func test_populate_dms_registers_item_nodes() -> void:
	Client._dm_channel_cache = {
		"dm_1": TestDataFactory.dm_data({"id": "dm_1"}),
	}
	component._populate_dms()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(component.dm_item_nodes.has("dm_1"))


# --- _set_active_dm ---

func test_set_active_dm_updates_active_id() -> void:
	Client._dm_channel_cache = {
		"dm_1": TestDataFactory.dm_data({"id": "dm_1"}),
	}
	component._populate_dms()
	await get_tree().process_frame
	await get_tree().process_frame
	component._set_active_dm("dm_1")
	assert_eq(component.active_dm_id, "dm_1")


func test_set_active_dm_deactivates_previous() -> void:
	Client._dm_channel_cache = {
		"dm_1": TestDataFactory.dm_data({"id": "dm_1"}),
		"dm_2": TestDataFactory.dm_data({"id": "dm_2",
			"user": {"display_name": "Bob", "username": "bob",
				"color": Color.WHITE}}),
	}
	component._populate_dms()
	await get_tree().process_frame
	await get_tree().process_frame
	component._set_active_dm("dm_1")
	component._set_active_dm("dm_2")
	assert_eq(component.active_dm_id, "dm_2")


func test_set_active_dm_unknown_id_no_crash() -> void:
	component._set_active_dm("nonexistent")
	assert_eq(component.active_dm_id, "nonexistent")
