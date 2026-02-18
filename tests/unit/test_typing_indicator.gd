extends GutTest

var component: HBoxContainer


func before_each() -> void:
	component = load("res://scenes/messages/typing_indicator.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- Initial state ---

func test_initially_not_visible() -> void:
	# The parent scene sets this hidden; but instantiated standalone it depends
	# on the .tscn default. Check that processing is off (set in _ready).
	assert_false(component.is_processing())


# --- show_typing ---

func test_show_sets_visible_and_text() -> void:
	component.show_typing("Alice")
	assert_true(component.visible)
	assert_eq(component.text_label.text, "Alice is typing...")


func test_show_enables_processing() -> void:
	component.show_typing("Bob")
	assert_true(component.is_processing())


func test_show_resets_anim_time() -> void:
	component.anim_time = 5.0
	component.show_typing("Charlie")
	assert_eq(component.anim_time, 0.0)


# --- hide_typing ---

func test_hide_hides() -> void:
	component.show_typing("Alice")
	component.hide_typing()
	assert_false(component.visible)


func test_hide_disables_processing() -> void:
	component.show_typing("Alice")
	component.hide_typing()
	assert_false(component.is_processing())
