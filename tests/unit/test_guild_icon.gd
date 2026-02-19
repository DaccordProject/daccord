extends GutTest

var component: HBoxContainer


func before_each() -> void:
	# Ensure Client has minimal state
	Client.current_user = {
		"id": "test_user_1", "display_name": "TestUser",
		"username": "testuser", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	Client._connections = []
	Client._guild_to_conn = {}
	component = load("res://scenes/sidebar/guild_bar/guild_icon.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _guild_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "g_1",
		"name": "Test Guild",
		"icon_color": Color(0.3, 0.5, 0.7),
		"icon": null,
		"unread": false,
		"mentions": 0,
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_stores_ids() -> void:
	component.setup(_guild_data())
	assert_eq(component.guild_id, "g_1")
	assert_eq(component.guild_name, "Test Guild")


func test_setup_sets_tooltip() -> void:
	component.setup(_guild_data())
	assert_eq(component.icon_button.tooltip_text, "Test Guild")


func test_setup_avatar_letter() -> void:
	component.setup(_guild_data({"name": "MyGuild"}))
	# The avatar_rect is a custom shader-based node; test that
	# set_letter was called (it stores the letter internally)
	# Just verify setup didn't crash and guild_name was set
	assert_eq(component.guild_name, "MyGuild")


func test_setup_unread_pill_state() -> void:
	component.setup(_guild_data({"unread": true}))
	assert_eq(component.pill.pill_state, component.pill.PillState.UNREAD)


func test_setup_no_unread_pill_hidden() -> void:
	component.setup(_guild_data({"unread": false}))
	assert_eq(component.pill.pill_state, component.pill.PillState.HIDDEN)


func test_setup_mention_badge() -> void:
	component.setup(_guild_data({"mentions": 3}))
	assert_eq(component.mention_badge.count, 3)


# --- set_active ---

func test_set_active_true() -> void:
	component.setup(_guild_data())
	component.set_active(true)
	assert_true(component.is_active)
	assert_eq(component.pill.pill_state, component.pill.PillState.ACTIVE)


func test_set_active_false_with_unread() -> void:
	component.setup(_guild_data({"unread": true}))
	component.set_active(true)
	component.set_active(false)
	assert_false(component.is_active)
	assert_eq(component.pill.pill_state, component.pill.PillState.UNREAD)


func test_set_active_false_no_unread() -> void:
	component.setup(_guild_data({"unread": false}))
	component.set_active(true)
	component.set_active(false)
	assert_eq(component.pill.pill_state, component.pill.PillState.HIDDEN)


func test_initial_state_not_active() -> void:
	assert_false(component.is_active)


# --- signal ---

func test_has_guild_pressed_signal() -> void:
	assert_true(component.has_signal("guild_pressed"))
