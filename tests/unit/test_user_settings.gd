extends GutTest

## Tests for the settings panels (app_settings.gd, server_settings.gd,
## settings_base.gd, and their delegates).

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

func test_settings_base_script_loads() -> void:
	var script = load("res://scenes/user/settings_base.gd")
	assert_not_null(
		script,
		"settings_base.gd should load without parse errors"
	)

func test_app_settings_script_loads() -> void:
	var script = load("res://scenes/user/app_settings.gd")
	assert_not_null(
		script,
		"app_settings.gd should load without parse errors"
	)

func test_server_settings_script_loads() -> void:
	var script = load("res://scenes/user/server_settings.gd")
	assert_not_null(
		script,
		"server_settings.gd should load without parse errors"
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


# --- App Settings instantiation ---

func test_app_settings_instantiates() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/app_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	assert_true(is_instance_valid(panel))
	panel.queue_free()
	await get_tree().process_frame


# --- Profiles page types ---

func test_refresh_profiles_list_types() -> void:
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


# --- App Settings page building ---

func test_app_settings_all_pages_created() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/app_settings.gd"
	).new()
	add_child(panel)
	await get_tree().process_frame
	# App settings has 6 pages
	assert_eq(panel._pages.size(), 6)
	for page in panel._pages:
		assert_true(is_instance_valid(page))
	panel.queue_free()
	await get_tree().process_frame


func test_app_settings_page_navigation() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/app_settings.gd"
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


# --- Input sensitivity ---

func test_default_input_sensitivity() -> void:
	assert_eq(
		config.voice.get_input_sensitivity(), 50,
		"Default input sensitivity should be 50"
	)

func test_set_input_sensitivity_persists() -> void:
	config.voice.set_input_sensitivity(75)
	assert_eq(
		config.voice.get_input_sensitivity(), 75,
		"Sensitivity should persist after set"
	)

func test_sensitivity_to_threshold_boundaries() -> void:
	config.voice.set_input_sensitivity(0)
	assert_almost_eq(
		config.voice.get_speaking_threshold(), 0.1, 0.001,
		"0% sensitivity should give threshold ~0.1"
	)
	config.voice.set_input_sensitivity(100)
	assert_almost_eq(
		config.voice.get_speaking_threshold(), 0.0001, 0.00001,
		"100% sensitivity should give threshold ~0.0001"
	)

func test_speaking_threshold_uses_config_value() -> void:
	config.voice.set_input_sensitivity(50)
	var threshold: float = config.voice.get_speaking_threshold()
	# 10^(-1 - 1.5) = 10^-2.5 ≈ 0.00316
	assert_almost_eq(
		threshold, 0.00316, 0.001,
		"50% sensitivity should give threshold ~0.003"
	)


func test_escape_closes_panel() -> void:
	var panel: ColorRect = load(
		"res://scenes/user/app_settings.gd"
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
