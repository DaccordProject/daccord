extends GutTest

var dialog: ColorRect


func before_each() -> void:
	dialog = load("res://scenes/sidebar/screen_picker_dialog.tscn").instantiate()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame
	# Clear sources populated by _ready() so helper tests start clean
	dialog._clear_list()
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame


# --- UI structure ---

func test_has_close_button() -> void:
	assert_not_null(dialog._close_btn)


func test_has_source_list() -> void:
	assert_not_null(dialog._source_list)


func test_has_source_selected_signal() -> void:
	assert_has_signal(dialog, "source_selected")


# --- Permission check uses enum, not string ---

func test_check_permissions_returns_int_status() -> void:
	var status: Dictionary = LiveKitScreenCapture.check_permissions()
	assert_true(
		status.get("status") is int,
		"status should be an int enum value, not a string",
	)


func test_permission_error_enum_value() -> void:
	assert_eq(
		LiveKitScreenCapture.PERMISSION_ERROR, 2,
		"PERMISSION_ERROR should be 2",
	)


# --- Helper methods ---

func test_add_section_label() -> void:
	dialog._add_section_label("Test Section")
	assert_eq(dialog._source_list.get_child_count(), 1)
	var lbl: Label = dialog._source_list.get_child(0)
	assert_eq(lbl.text, "Test Section")


func test_add_source_button() -> void:
	var source: Dictionary = {"id": 1, "_type": "monitor"}
	dialog._add_source_button("Display 1", "1920x1080", source)
	assert_eq(dialog._source_list.get_child_count(), 1)
	var btn: Button = dialog._source_list.get_child(0)
	assert_string_contains(btn.text, "Display 1")
	assert_string_contains(btn.text, "1920x1080")


func test_source_button_has_pressed_connection() -> void:
	var source: Dictionary = {"id": 1, "_type": "monitor"}
	dialog._add_source_button("Display 1", "1920x1080", source)
	var btn: Button = dialog._source_list.get_child(0)
	var connections: Array = btn.pressed.get_connections()
	assert_eq(connections.size(), 1, "Button should have one pressed connection")


func test_add_empty_label() -> void:
	dialog._add_empty_label("No sources")
	assert_eq(dialog._source_list.get_child_count(), 1)
	var lbl: Label = dialog._source_list.get_child(0)
	assert_eq(lbl.text, "No sources")


func test_add_error_label() -> void:
	dialog._add_error_label("Permission denied")
	assert_eq(dialog._source_list.get_child_count(), 1)
	var lbl: Label = dialog._source_list.get_child(0)
	assert_eq(lbl.text, "Permission denied")


func test_clear_list() -> void:
	dialog._add_section_label("A")
	dialog._add_section_label("B")
	assert_eq(dialog._source_list.get_child_count(), 2)
	dialog._clear_list()
	await get_tree().process_frame
	assert_eq(dialog._source_list.get_child_count(), 0)


func test_populate_sources_adds_children() -> void:
	dialog._populate_sources()
	assert_gt(
		dialog._source_list.get_child_count(), 0,
		"Should populate at least one source or empty label",
	)


# --- Close behavior ---

func test_close_frees_dialog() -> void:
	dialog._close()
	await get_tree().process_frame
	assert_false(is_instance_valid(dialog))
