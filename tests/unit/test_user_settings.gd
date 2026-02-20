extends GutTest

## Tests for the UserSettings panel (scenes/user/user_settings.gd).
##
## Strategy: create a Config with profiles/voice initialized in memory,
## set up minimal Client state, then instantiate the script and verify
## it loads and builds pages without parse or runtime errors.

var config: Node
var _original_user: Dictionary


func before_each() -> void:
	# Set up Config with profiles + voice sub-objects
	config = load("res://scripts/autoload/config.gd").new()
	config._load_ok = true
	config._registry = ConfigFile.new()
	config._registry.set_value("state", "active", "default")
	config._registry.set_value("order", "list", ["default"])
	config._registry.set_value("profile_default", "name", "Default")
	config._profile_slug = "default"
	var ProfilesScript = load(
		"res://scripts/autoload/config_profiles.gd"
	)
	config.profiles = ProfilesScript.new(
		config, "daccord-profile-v1"
	)
	var VoiceScript = load(
		"res://scripts/autoload/config_voice.gd"
	)
	config.voice = VoiceScript.new(config)

	# Save and replace the real Config autoload's state
	_original_user = Client.current_user
	Client.current_user = {
		"id": "test_u1",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color(0.345, 0.396, 0.949),
		"status": 0,
		"avatar": null,
		"bio": "Hello world",
		"accent_color": 0,
		"created_at": "2025-01-15T12:00:00Z",
	}


func after_each() -> void:
	Client.current_user = _original_user
	config.free()


# --- Script loading ---

func test_user_settings_script_loads_without_parse_error() -> void:
	var script = load("res://scenes/user/user_settings.gd")
	assert_not_null(
		script,
		"user_settings.gd should load without parse errors"
	)


func test_user_settings_profile_script_loads() -> void:
	var script = load(
		"res://scenes/user/user_settings_profile.gd"
	)
	assert_not_null(script)


func test_user_settings_danger_script_loads() -> void:
	var script = load(
		"res://scenes/user/user_settings_danger.gd"
	)
	assert_not_null(script)


func test_user_settings_twofa_script_loads() -> void:
	var script = load(
		"res://scenes/user/user_settings_twofa.gd"
	)
	assert_not_null(script)


# --- Instantiation ---

func test_user_settings_instantiates() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/user_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	assert_true(is_instance_valid(panel))
	panel.queue_free()
	await get_tree().process_frame


# --- Profiles page types ---

func test_refresh_profiles_list_types() -> void:
	# Verify that get_profiles returns Array and get_active_slug
	# returns String — the root cause of the parse errors.
	var prof_list = Config.profiles.get_profiles()
	assert_true(
		prof_list is Array,
		"get_profiles() should return Array"
	)
	var active_slug = Config.profiles.get_active_slug()
	assert_true(
		active_slug is String,
		"get_active_slug() should return String"
	)


func test_profiles_list_contains_default() -> void:
	var prof_list: Array = Config.profiles.get_profiles()
	assert_true(prof_list.size() >= 1)
	var slugs: Array = []
	for p in prof_list:
		slugs.append(p["slug"])
	assert_has(slugs, "default")


# --- Page building ---

func test_all_pages_created() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/user_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	# The panel builds 9 pages (My Account includes profile editing)
	assert_eq(panel._pages.size(), 9)
	for page in panel._pages:
		assert_true(is_instance_valid(page))
	panel.queue_free()
	await get_tree().process_frame


func test_page_navigation() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/user_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	# First page should be visible by default
	assert_true(panel._pages[0].visible)
	assert_false(panel._pages[1].visible)
	# Switch to page 1
	panel._show_page(1)
	assert_false(panel._pages[0].visible)
	assert_true(panel._pages[1].visible)
	panel.queue_free()
	await get_tree().process_frame


func test_escape_closes_panel() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/user_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	assert_true(is_instance_valid(panel))
	# Simulate Escape key
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	panel._unhandled_input(event)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(
		not is_instance_valid(panel) or panel.is_queued_for_deletion()
	)
