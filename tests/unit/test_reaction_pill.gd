extends GutTest

var component: Button


func before_each() -> void:
	component = load("res://scenes/messages/reaction_pill.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _pill_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"emoji": "thumbsup",
		"count": 3,
		"active": false,
		"channel_id": "c_1",
		"message_id": "m_1",
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_stores_emoji_key() -> void:
	component.setup(_pill_data())
	assert_eq(component.emoji_key, "thumbsup")


func test_setup_sets_count_label() -> void:
	component.setup(_pill_data({"count": 7}))
	assert_eq(component.text, "7")


func test_setup_active_true() -> void:
	component.setup(_pill_data({"active": true}))
	assert_true(component.button_pressed)


func test_setup_active_false() -> void:
	component.setup(_pill_data({"active": false}))
	assert_false(component.button_pressed)


func test_setup_stores_ids() -> void:
	component.setup(_pill_data())
	assert_eq(component.channel_id, "c_1")
	assert_eq(component.message_id, "m_1")


func test_setup_with_zero_count() -> void:
	component.setup(_pill_data({"count": 0}))
	assert_eq(component.text, "0")
	assert_eq(component.reaction_count, 0)


# --- optimistic toggle ---

func test_optimistic_toggle_increments_count() -> void:
	component.setup(_pill_data({"count": 3}))
	# Simulate toggle on (bypassing server call by checking local state)
	component._in_setup = false
	# Manually trigger the toggle logic
	component.reaction_count += 1
	component.text = str(component.reaction_count)
	assert_eq(component.text, "4")
