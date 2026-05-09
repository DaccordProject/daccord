extends GutTest

const _REGISTRY_PATH := "user://profile_registry.cfg"
const _DEFAULT_CFG := "user://profiles/default/config.cfg"

var dialog: ColorRect
var _saved_registry := PackedByteArray()
var _saved_config := PackedByteArray()
var _had_registry := false
var _had_config := false


func before_each() -> void:
	# _on_create() persists profiles via the real Config autoload, which would
	# pollute user data between runs. Snapshot the registry + default config so
	# after_each can restore them and remove any test-created profile dirs.
	_had_registry = FileAccess.file_exists(_REGISTRY_PATH)
	if _had_registry:
		_saved_registry = FileAccess.get_file_as_bytes(_REGISTRY_PATH)
	_had_config = FileAccess.file_exists(_DEFAULT_CFG)
	if _had_config:
		_saved_config = FileAccess.get_file_as_bytes(_DEFAULT_CFG)
	dialog = load("res://scenes/user/create_profile_dialog.tscn").instantiate()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame
	# Remove any profile dirs created by _on_create() during the test
	var dir := DirAccess.open("user://profiles")
	if dir:
		dir.list_dir_begin()
		var dname := dir.get_next()
		while not dname.is_empty():
			if dir.current_is_dir() and dname != "default":
				_remove_dir_recursive("user://profiles/" + dname)
			dname = dir.get_next()
		dir.list_dir_end()
	# Restore registry + default profile config
	if _had_registry:
		var f := FileAccess.open(_REGISTRY_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_saved_registry)
			f.close()
	elif FileAccess.file_exists(_REGISTRY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_REGISTRY_PATH))
	if _had_config:
		var f := FileAccess.open(_DEFAULT_CFG, FileAccess.WRITE)
		if f:
			f.store_buffer(_saved_config)
			f.close()


func _remove_dir_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		var child := path + "/" + name
		if dir.current_is_dir():
			_remove_dir_recursive(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# --- UI structure ---

func test_has_name_input() -> void:
	assert_not_null(dialog._name_input)
	assert_true(dialog._name_input is LineEdit)


func test_has_password_input() -> void:
	assert_not_null(dialog._password_input)


func test_has_confirm_input() -> void:
	assert_not_null(dialog._confirm_input)


func test_has_create_button() -> void:
	assert_not_null(dialog._create_btn)
	assert_true(dialog._create_btn is Button)


func test_has_error_label() -> void:
	assert_not_null(dialog._error_label)


func test_error_label_hidden_initially() -> void:
	assert_false(dialog._error_label.visible)


func test_confirm_input_hidden_initially() -> void:
	assert_false(dialog._confirm_input.visible)


func test_confirm_label_hidden_initially() -> void:
	assert_false(dialog._confirm_label.visible)


# --- signals ---

func test_has_profile_created_signal() -> void:
	assert_has_signal(dialog, "profile_created")


# --- validation: empty name ---

func test_empty_name_shows_error() -> void:
	dialog._name_input.text = ""
	dialog._on_create()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "required")


func test_empty_name_does_not_emit_signal() -> void:
	watch_signals(dialog)
	dialog._name_input.text = ""
	dialog._on_create()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "profile_created")


# --- validation: name too long ---

func test_name_too_long_truncated_by_line_edit() -> void:
	# LineEdit has max_length=32, so setting 33 chars gets truncated
	dialog._name_input.text = "a".repeat(33)
	assert_eq(dialog._name_input.text.length(), 32,
		"LineEdit should truncate to max_length")


func test_name_at_max_length_accepted() -> void:
	# 32 chars is valid — the length validation in _on_create should not trigger
	dialog._name_input.text = "a".repeat(32)
	assert_eq(dialog._name_input.text.length(), 32)
	dialog._error_label.visible = false
	dialog._on_create()
	# Error may show for other reasons (Config.profiles not available in test),
	# but NOT for the length reason
	if dialog._error_label.visible:
		assert_false(
			dialog._error_label.text.contains("32"),
			"A 32-char name should not trigger the length error"
		)
	else:
		pass_test("No error shown for valid-length name")


# --- validation: password mismatch ---

func test_password_mismatch_shows_error() -> void:
	dialog._name_input.text = "Test Profile"
	dialog._password_input.text = "secret"
	dialog._confirm_input.text = "different"
	dialog._on_create()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "match")


func test_password_mismatch_does_not_emit_signal() -> void:
	watch_signals(dialog)
	dialog._name_input.text = "Test Profile"
	dialog._password_input.text = "secret"
	dialog._confirm_input.text = "different"
	dialog._on_create()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "profile_created")


# --- password visibility toggle ---

func test_password_typed_shows_confirm_fields() -> void:
	dialog._password_input.emit_signal("text_changed", "hello")
	await get_tree().process_frame
	assert_true(dialog._confirm_label.visible)
	assert_true(dialog._confirm_input.visible)


func test_password_cleared_hides_confirm_fields() -> void:
	dialog._password_input.emit_signal("text_changed", "hello")
	await get_tree().process_frame
	dialog._password_input.emit_signal("text_changed", "")
	await get_tree().process_frame
	assert_false(dialog._confirm_label.visible)
	assert_false(dialog._confirm_input.visible)
