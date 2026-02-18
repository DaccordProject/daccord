extends GutTest

var component: PanelContainer


func before_each() -> void:
	component = load("res://scenes/messages/composer/composer.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# --- UI elements exist ---

func test_text_input_exists() -> void:
	assert_not_null(component.text_input)


func test_send_button_exists() -> void:
	assert_not_null(component.send_button)


func test_emoji_button_exists() -> void:
	assert_not_null(component.emoji_button)


func test_upload_button_exists() -> void:
	assert_not_null(component.upload_button)


# --- Initial state ---

func test_reply_bar_hidden_initially() -> void:
	assert_false(component.reply_bar.visible)


func test_error_label_hidden_initially() -> void:
	assert_false(component.error_label.visible)


# --- Channel name ---

func test_set_channel_name_updates_placeholder() -> void:
	component.set_channel_name("general")
	assert_eq(component.text_input.placeholder_text, "Message #general")


# --- Reply signals ---

func test_reply_cancel_hides_bar() -> void:
	# Simulate reply bar being shown
	component.reply_bar.visible = true
	component.reply_label.text = "Replying to Alice"
	# Cancel reply
	component._on_reply_cancelled()
	assert_false(component.reply_bar.visible)
	assert_eq(component.reply_label.text, "")
