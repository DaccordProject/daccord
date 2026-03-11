extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var panel: PanelContainer
var result_item_scene: PackedScene


func before_each() -> void:
	Client.channels = []
	panel = load("res://scenes/search/search_panel.tscn").instantiate()
	add_child(panel)
	await get_tree().process_frame
	await get_tree().process_frame
	result_item_scene = load("res://scenes/search/search_result_item.tscn")


func after_each() -> void:
	if is_instance_valid(panel):
		panel.queue_free()
		await get_tree().process_frame
	Client.channels = []


# --- UI element existence ---

func test_search_input_exists() -> void:
	assert_not_null(panel.search_input)


func test_results_vbox_exists() -> void:
	assert_not_null(panel.results_vbox)


func test_scroll_container_exists() -> void:
	assert_not_null(panel.scroll_container)


func test_close_button_exists() -> void:
	assert_not_null(panel.close_button)


func test_status_label_exists() -> void:
	assert_not_null(panel.status_label)


func test_load_more_btn_exists() -> void:
	assert_not_null(panel.load_more_btn)


# --- empty state on load ---

func test_results_vbox_empty_on_load() -> void:
	assert_eq(panel.results_vbox.get_child_count(), 0)


func test_status_label_hidden_on_load() -> void:
	assert_false(panel.status_label.visible)


func test_load_more_btn_hidden_on_load() -> void:
	assert_false(panel.load_more_btn.visible)


# --- activate ---

func test_activate_sets_space_id() -> void:
	panel.activate("g_1")
	assert_eq(panel._space_id, "g_1")


# --- _clear_results ---

func test_clear_results_removes_children() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	panel.results_vbox.add_child(item)
	await get_tree().process_frame
	panel._clear_results()
	await get_tree().process_frame
	assert_eq(panel.results_vbox.get_child_count(), 0)


func test_clear_results_hides_status_label() -> void:
	panel.status_label.visible = true
	panel._clear_results()
	assert_false(panel.status_label.visible)


func test_clear_results_hides_load_more_btn() -> void:
	panel.load_more_btn.visible = true
	panel._clear_results()
	assert_false(panel.load_more_btn.visible)


func test_clear_results_resets_offset() -> void:
	panel._offset = 25
	panel._clear_results()
	assert_eq(panel._offset, 0)


# --- space_selected resets panel ---

func test_space_selected_clears_query_input() -> void:
	panel.search_input.text = "hello"
	AppState.space_selected.emit("g_2")
	await get_tree().process_frame
	assert_eq(panel.search_input.text, "")


func test_space_selected_updates_space_id() -> void:
	panel._space_id = "g_1"
	AppState.space_selected.emit("g_2")
	await get_tree().process_frame
	assert_eq(panel._space_id, "g_2")


# --- dm_mode_entered resets panel ---

func test_dm_mode_entered_clears_space_id() -> void:
	panel._space_id = "g_1"
	AppState.dm_mode_entered.emit()
	await get_tree().process_frame
	assert_eq(panel._space_id, "")


func test_dm_mode_entered_clears_query_input() -> void:
	panel.search_input.text = "hello"
	AppState.dm_mode_entered.emit()
	await get_tree().process_frame
	assert_eq(panel.search_input.text, "")


# --- search_result_item setup ---

func test_result_item_setup_sets_channel_label() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var data: Dictionary = TestDataFactory.msg_data({
		"channel_name": "general",
		"timestamp": "Today at 3:00 PM",
	})
	item.setup(data)
	assert_eq(item.channel_label.text, "#general")
	item.queue_free()


func test_result_item_setup_sets_timestamp_label() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var data: Dictionary = TestDataFactory.msg_data({
		"channel_name": "general",
		"timestamp": "Today at 3:00 PM",
	})
	item.setup(data)
	assert_eq(item.timestamp_label.text, "Today at 3:00 PM")
	item.queue_free()


func test_result_item_setup_sets_author_label() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var data: Dictionary = TestDataFactory.msg_data({
		"channel_name": "general",
		"author": {"display_name": "Alice", "color": Color.WHITE},
	})
	item.setup(data)
	assert_eq(item.author_label.text, "Alice")
	item.queue_free()


func test_result_item_setup_sets_content_label() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var data: Dictionary = TestDataFactory.msg_data({
		"channel_name": "general",
		"content": "Hello world",
	})
	item.setup(data)
	assert_eq(item.content_label.text, "Hello world")
	item.queue_free()


func test_result_item_setup_truncates_long_content() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var long_text: String = "x".repeat(200)
	var data: Dictionary = TestDataFactory.msg_data({
		"channel_name": "general",
		"content": long_text,
	})
	item.setup(data)
	assert_true(item.content_label.text.ends_with("..."))
	assert_true(item.content_label.text.length() <= 123)
	item.queue_free()


func test_result_item_has_clicked_signal() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	assert_has_signal(item, "clicked")
	item.queue_free()


func test_result_item_stores_channel_and_message_ids() -> void:
	var item: PanelContainer = result_item_scene.instantiate()
	add_child(item)
	await get_tree().process_frame
	var data: Dictionary = TestDataFactory.msg_data({
		"id": "m_abc",
		"channel_id": "c_xyz",
		"channel_name": "general",
	})
	item.setup(data)
	assert_eq(item._channel_id, "c_xyz")
	assert_eq(item._message_id, "m_abc")
	item.queue_free()
