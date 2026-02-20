extends GutTest

var component: VBoxContainer


func before_each() -> void:
	component = load("res://scenes/messages/message_content.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- setup ---

func test_setup_plain_text() -> void:
	component.setup({"content": "Hello world", "edited": false, "reactions": [], "embeds": []})
	assert_string_contains(component.text_content.text, "Hello world")


func test_setup_edited_shows_indicator() -> void:
	component.setup({"content": "edited msg", "edited": true, "reactions": [], "embeds": []})
	assert_string_contains(component.text_content.text, "(edited)")


func test_setup_not_edited_no_indicator() -> void:
	component.setup({"content": "normal msg", "edited": false, "reactions": [], "embeds": []})
	assert_false(component.text_content.text.contains("(edited)"))


func test_setup_system_message_italic() -> void:
	component.setup({"content": "User joined", "system": true, "reactions": [], "embeds": []})
	assert_string_contains(component.text_content.text, "[i]")
	assert_string_contains(component.text_content.text, "User joined")


func test_setup_system_message_not_edited() -> void:
	component.setup({"content": "System msg", "system": true, "edited": true, "reactions": [], "embeds": []})
	# System messages don't show edited indicator
	assert_false(component.text_content.text.contains("(edited)"))


# --- _format_file_size (static) ---

func test_format_file_size_bytes() -> void:
	var result: String = component._format_file_size(512)
	assert_eq(result, "512 B")


func test_format_file_size_kilobytes() -> void:
	var result: String = component._format_file_size(2048)
	assert_eq(result, "2.0 KB")


func test_format_file_size_megabytes() -> void:
	var result: String = component._format_file_size(5242880)
	assert_eq(result, "5.0 MB")


# --- edit mode ---

func test_enter_edit_mode_hides_text() -> void:
	component.setup({"content": "original", "edited": false, "reactions": [], "embeds": []})
	component.enter_edit_mode("msg_1", "original")
	assert_false(component.text_content.visible)


func test_is_editing_state() -> void:
	component.setup({"content": "test", "edited": false, "reactions": [], "embeds": []})
	assert_false(component.is_editing())
	component.enter_edit_mode("msg_1", "test")
	assert_true(component.is_editing())
