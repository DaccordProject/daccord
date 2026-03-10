extends GutTest

## Inline stub that makes verify_password return false, simulating wrong password.
class _StubProfilesReject:
	extends RefCounted
	func verify_password(_slug: String, _pw: String) -> bool:
		return false


var dialog: ColorRect
var _original_profiles: Object


func before_each() -> void:
	dialog = load("res://scenes/user/profile_password_dialog.tscn").instantiate()
	add_child(dialog)
	await get_tree().process_frame
	await get_tree().process_frame
	_original_profiles = Config.profiles


func after_each() -> void:
	Config.profiles = _original_profiles
	if is_instance_valid(dialog):
		dialog.queue_free()
		await get_tree().process_frame


# --- UI structure ---

func test_has_profile_label() -> void:
	assert_not_null(dialog._profile_label)
	assert_true(dialog._profile_label is Label)


func test_has_password_input() -> void:
	assert_not_null(dialog._password_input)


func test_has_unlock_button() -> void:
	assert_not_null(dialog._unlock_btn)
	assert_true(dialog._unlock_btn is Button)


func test_has_error_label() -> void:
	assert_not_null(dialog._error_label)


func test_error_label_hidden_initially() -> void:
	assert_false(dialog._error_label.visible)


# --- signals ---

func test_has_password_verified_signal() -> void:
	assert_has_signal(dialog, "password_verified")


# --- setup method ---

func test_setup_stores_slug() -> void:
	dialog.setup("my-profile", "My Profile")
	assert_eq(dialog._slug, "my-profile")


func test_setup_updates_profile_label_when_in_tree() -> void:
	dialog.setup("my-profile", "Cool Profile")
	await get_tree().process_frame
	assert_string_contains(dialog._profile_label.text, "Cool Profile")


# --- validation: empty password ---

func test_empty_password_shows_error() -> void:
	dialog._password_input.text = ""
	dialog._on_unlock()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "required")


func test_empty_password_does_not_emit_signal() -> void:
	watch_signals(dialog)
	dialog._password_input.text = ""
	dialog._on_unlock()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "password_verified")


# --- wrong password (stub rejects all passwords) ---

func test_wrong_password_shows_error() -> void:
	Config.profiles = _StubProfilesReject.new()
	dialog.setup("any-slug", "Test")
	dialog._password_input.text = "wrongpass"
	dialog._on_unlock()
	await get_tree().process_frame
	assert_true(dialog._error_label.visible)
	assert_string_contains(dialog._error_label.text, "Incorrect")


func test_wrong_password_clears_input() -> void:
	Config.profiles = _StubProfilesReject.new()
	dialog.setup("any-slug", "Test")
	dialog._password_input.text = "wrongpass"
	dialog._on_unlock()
	await get_tree().process_frame
	assert_eq(dialog._password_input.text, "")


func test_wrong_password_does_not_emit_signal() -> void:
	watch_signals(dialog)
	Config.profiles = _StubProfilesReject.new()
	dialog.setup("any-slug", "Test")
	dialog._password_input.text = "wrongpass"
	dialog._on_unlock()
	await get_tree().process_frame
	assert_signal_not_emitted(dialog, "password_verified")
