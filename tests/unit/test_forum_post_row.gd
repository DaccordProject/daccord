extends GutTest

## Unit tests for ForumPostRow component.
##
## ForumPostRow builds its own UI in _ready() so we can instantiate
## the script directly (via new()) or load the scene. We load the scene
## to test the full node tree including the avatar.

var component: PanelContainer


func before_each() -> void:
	component = load("res://scenes/messages/forum_post_row.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _post_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "post_1",
		"title": "Hello Forum",
		"content": "This is the body of the post.",
		"author": {
			"id": "u_1",
			"display_name": "Alice",
			"username": "alice",
			"color": Color.WHITE,
			"avatar": null,
		},
		"reply_count": 3,
		"timestamp": "2025-01-01T12:00:00Z",
		"last_reply_at": "",
	}
	d.merge(overrides, true)
	return d


# ---------------------------------------------------------------------------
# Signal existence
# ---------------------------------------------------------------------------

func test_has_post_pressed_signal() -> void:
	assert_true(component.has_signal("post_pressed"))


func test_has_context_menu_requested_signal() -> void:
	assert_true(component.has_signal("context_menu_requested"))


# ---------------------------------------------------------------------------
# setup() — title
# ---------------------------------------------------------------------------

func test_setup_sets_title_from_title_field() -> void:
	component.setup(_post_data())
	assert_eq(component._title_label.text, "Hello Forum")


func test_setup_fallback_title_from_content_first_line() -> void:
	## When title is empty, uses content up to the first newline.
	component.setup(_post_data({"title": "", "content": "First line\nRest"}))
	assert_eq(component._title_label.text, "First line")


func test_setup_fallback_title_from_content_short() -> void:
	## When title is empty and content has no newline, uses content directly.
	component.setup(_post_data({"title": "", "content": "Short post"}))
	assert_eq(component._title_label.text, "Short post")


func test_setup_fallback_title_untitled_when_both_empty() -> void:
	component.setup(_post_data({"title": "", "content": ""}))
	assert_eq(component._title_label.text, "Untitled Post")


# ---------------------------------------------------------------------------
# setup() — author
# ---------------------------------------------------------------------------

func test_setup_sets_author_display_name() -> void:
	component.setup(_post_data())
	assert_eq(component._author_label.text, "Alice")


func test_setup_author_unknown_when_missing() -> void:
	component.setup(_post_data({"author": {}}))
	assert_eq(component._author_label.text, "Unknown")


# ---------------------------------------------------------------------------
# setup() — reply count
# ---------------------------------------------------------------------------

func test_setup_reply_count_plural() -> void:
	component.setup(_post_data({"reply_count": 3}))
	assert_eq(component._reply_count_label.text, "3 replies")


func test_setup_reply_count_singular() -> void:
	component.setup(_post_data({"reply_count": 1}))
	assert_eq(component._reply_count_label.text, "1 reply")


func test_setup_reply_count_zero() -> void:
	component.setup(_post_data({"reply_count": 0}))
	assert_eq(component._reply_count_label.text, "0 replies")


# ---------------------------------------------------------------------------
# setup() — preview text
# ---------------------------------------------------------------------------

func test_setup_sets_preview_text() -> void:
	component.setup(_post_data({"content": "Preview content here."}))
	assert_eq(component._preview_label.text, "Preview content here.")


func test_setup_preview_hidden_when_empty_content() -> void:
	component.setup(_post_data({"title": "T", "content": ""}))
	assert_false(component._preview_label.visible)


func test_setup_preview_visible_when_content_present() -> void:
	component.setup(_post_data({"content": "Some text."}))
	assert_true(component._preview_label.visible)


func test_setup_truncates_long_content() -> void:
	var long_str := "x".repeat(200)
	component.setup(_post_data({"content": long_str}))
	assert_true(component._preview_label.text.ends_with("..."))
	assert_true(component._preview_label.text.length() <= 124) # 120 + "..."


# ---------------------------------------------------------------------------
# _gui_input — post_pressed signal
# ---------------------------------------------------------------------------

func test_post_pressed_emits_correct_id() -> void:
	component.setup(_post_data())
	watch_signals(component)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	component._gui_input(ev)
	assert_signal_emitted_with_parameters(component, "post_pressed", ["post_1"])
