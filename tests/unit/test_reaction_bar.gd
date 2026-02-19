extends GutTest

var component: FlowContainer


func before_each() -> void:
	component = load("res://scenes/messages/reaction_bar.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- setup ---

func test_empty_reactions_hidden() -> void:
	component.setup([], "c_1", "m_1")
	assert_false(component.visible)


func test_non_empty_creates_pills() -> void:
	var reactions := [
		{"emoji": "thumbsup", "count": 1, "active": false},
		{"emoji": "heart", "count": 2, "active": true},
	]
	component.setup(reactions, "c_1", "m_1")
	await get_tree().process_frame
	assert_true(component.visible)
	# Count non-queued children
	var count := 0
	for child in component.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	assert_eq(count, 2)


func test_channel_message_ids_injected() -> void:
	var reactions := [
		{"emoji": "thumbsup", "count": 1, "active": false},
	]
	component.setup(reactions, "c_99", "m_42")
	# The reaction data dict should have the IDs injected
	assert_eq(reactions[0]["channel_id"], "c_99")
	assert_eq(reactions[0]["message_id"], "m_42")


func test_setup_clears_previous_children() -> void:
	var r1 := [{"emoji": "a", "count": 1, "active": false}]
	component.setup(r1, "c_1", "m_1")
	await get_tree().process_frame
	# Call setup again with different data
	var r2 := [
		{"emoji": "x", "count": 1, "active": false},
		{"emoji": "y", "count": 1, "active": false},
	]
	component.setup(r2, "c_1", "m_1")
	await get_tree().process_frame
	await get_tree().process_frame
	var count := 0
	for child in component.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	assert_eq(count, 2)


func test_single_reaction_creates_single_pill() -> void:
	var reactions := [{"emoji": "star", "count": 5, "active": true}]
	component.setup(reactions, "c_1", "m_1")
	await get_tree().process_frame
	var count := 0
	for child in component.get_children():
		if not child.is_queued_for_deletion():
			count += 1
	assert_eq(count, 1)
