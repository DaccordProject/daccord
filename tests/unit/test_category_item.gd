extends GutTest

var component: VBoxContainer


func before_each() -> void:
	# Ensure Client has minimal state for permission checks
	Client.current_user = {
		"id": "test_user_1", "display_name": "TestUser",
		"username": "testuser", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	component = load("res://scenes/sidebar/channels/category_item.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _cat_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "cat_1",
		"space_id": "g_1",
		"name": "Text Channels",
	}
	d.merge(overrides, true)
	return d


func _ch_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "c_1",
		"space_id": "g_1",
		"name": "general",
		"type": ClientModels.ChannelType.TEXT,
		"unread": false,
		"voice_users": 0,
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_stores_space_id() -> void:
	component.setup(_cat_data(), [])
	assert_eq(component.space_id, "g_1")


func test_setup_uppercases_name() -> void:
	component.setup(_cat_data({"name": "text channels"}), [])
	assert_eq(component.category_name.text, "TEXT CHANNELS")


func test_setup_creates_count_label() -> void:
	var channels := [_ch_data(), _ch_data({"id": "c_2", "name": "random"})]
	component.setup(_cat_data(), channels)
	assert_not_null(component._count_label)
	assert_eq(component._count_label.text, "2")


func test_setup_creates_channel_items() -> void:
	var channels := [
		_ch_data({"id": "c_1"}),
		_ch_data({"id": "c_2", "name": "random"}),
	]
	component.setup(_cat_data(), channels)
	var items: Array = component.get_channel_items()
	assert_eq(items.size(), 2)


func test_setup_creates_voice_channel_items() -> void:
	var channels := [
		_ch_data({"id": "vc_1", "name": "Voice", "type": ClientModels.ChannelType.VOICE}),
	]
	component.setup(_cat_data(), channels)
	var items: Array = component.get_channel_items()
	assert_eq(items.size(), 1)


# --- collapse ---

func test_toggle_collapsed_hides_channels() -> void:
	component.setup(_cat_data(), [_ch_data()])
	component._toggle_collapsed()
	assert_true(component.is_collapsed)
	assert_false(component.channel_container.visible)


func test_toggle_collapsed_shows_count_label() -> void:
	component.setup(_cat_data(), [_ch_data()])
	component._toggle_collapsed()
	assert_true(component._count_label.visible)


func test_toggle_collapsed_twice_restores() -> void:
	component.setup(_cat_data(), [_ch_data()])
	component._toggle_collapsed()
	component._toggle_collapsed()
	assert_false(component.is_collapsed)
	assert_true(component.channel_container.visible)


# --- get_category_id ---

func test_get_category_id() -> void:
	component.setup(_cat_data(), [])
	assert_eq(component.get_category_id(), "cat_1")


# --- signal ---

func test_has_channel_pressed_signal() -> void:
	assert_true(component.has_signal("channel_pressed"))
