extends GutTest

var component: VBoxContainer


func before_each() -> void:
	# Ensure Client has minimal state
	Client.current_user = {
		"id": "test_user_1", "display_name": "TestUser",
		"username": "testuser", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	Client._connections = []
	Client._guild_to_conn = {}
	component = load("res://scenes/sidebar/guild_bar/guild_folder.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _guilds_data() -> Array:
	return [
		{"id": "g_1", "name": "Guild One", "icon_color": Color.RED, "icon": null, "unread": false, "mentions": 0},
		{"id": "g_2", "name": "Guild Two", "icon_color": Color.BLUE, "icon": null, "unread": false, "mentions": 0},
	]


func _guilds_data_with_unread() -> Array:
	return [
		{"id": "g_1", "name": "Guild One", "icon_color": Color.RED, "icon": null, "unread": true, "mentions": 3},
		{"id": "g_2", "name": "Guild Two", "icon_color": Color.BLUE, "icon": null, "unread": false, "mentions": 2},
	]


# --- setup ---

func test_setup_stores_folder_name() -> void:
	component.setup("MyFolder", _guilds_data())
	assert_eq(component.folder_name, "MyFolder")


func test_setup_tooltip() -> void:
	component.setup("MyFolder", _guilds_data())
	assert_eq(component.folder_button.tooltip_text, "MyFolder")


func test_setup_mini_grid_creates_swatches() -> void:
	component.setup("MyFolder", _guilds_data())
	# Should have 2 swatches (one per guild, up to 4)
	await get_tree().process_frame
	var swatch_count := 0
	for child in component.mini_grid.get_children():
		if child is ColorRect and not child.is_queued_for_deletion():
			swatch_count += 1
	assert_eq(swatch_count, 2)


func test_setup_creates_guild_icons() -> void:
	component.setup("MyFolder", _guilds_data())
	assert_eq(component.guild_icons.size(), 2)


# --- expand/collapse ---

func test_folder_initially_collapsed() -> void:
	assert_false(component.is_expanded)


func test_toggle_expanded() -> void:
	component.setup("MyFolder", _guilds_data())
	component._toggle_expanded()
	assert_true(component.is_expanded)
	assert_true(component.guild_list.visible)
	assert_false(component.mini_grid.visible)


func test_toggle_expanded_twice_collapses() -> void:
	component.setup("MyFolder", _guilds_data())
	component._toggle_expanded()
	component._toggle_expanded()
	assert_false(component.is_expanded)
	assert_true(component.mini_grid.visible)


# --- signal ---

func test_has_guild_pressed_signal() -> void:
	assert_true(component.has_signal("guild_pressed"))


func test_has_folder_changed_signal() -> void:
	assert_true(component.has_signal("folder_changed"))


# --- set_active ---

func test_has_set_active_method() -> void:
	assert_true(component.has_method("set_active"))


func test_has_set_active_guild_method() -> void:
	assert_true(component.has_method("set_active_guild"))


func test_set_active_true() -> void:
	component.setup("MyFolder", _guilds_data())
	component.set_active(true)
	assert_true(component.is_active)
	assert_eq(component.pill.pill_state, component.pill.PillState.ACTIVE)


func test_set_active_false() -> void:
	component.setup("MyFolder", _guilds_data())
	component.set_active(true)
	component.set_active(false)
	assert_false(component.is_active)
	assert_eq(component.pill.pill_state, component.pill.PillState.HIDDEN)


func test_set_active_false_restores_unread() -> void:
	component.setup("MyFolder", _guilds_data_with_unread())
	component.set_active(true)
	component.set_active(false)
	assert_false(component.is_active)
	# Should restore to UNREAD since there are unread guilds
	assert_eq(component.pill.pill_state, component.pill.PillState.UNREAD)


func test_set_active_guild() -> void:
	component.setup("MyFolder", _guilds_data())
	component.set_active_guild("g_1")
	assert_true(component.is_active)
	assert_eq(component.pill.pill_state, component.pill.PillState.ACTIVE)
	# Check that the correct child icon is active
	assert_true(component.guild_icons[0].is_active)
	assert_false(component.guild_icons[1].is_active)


func test_set_active_guild_switches() -> void:
	component.setup("MyFolder", _guilds_data())
	component.set_active_guild("g_1")
	component.set_active_guild("g_2")
	assert_false(component.guild_icons[0].is_active)
	assert_true(component.guild_icons[1].is_active)


func test_set_active_false_deactivates_children() -> void:
	component.setup("MyFolder", _guilds_data())
	component.set_active_guild("g_1")
	component.set_active(false)
	assert_false(component.guild_icons[0].is_active)
	assert_false(component.guild_icons[1].is_active)


# --- notifications ---

func test_no_mentions_badge_hidden() -> void:
	component.setup("MyFolder", _guilds_data())
	assert_false(component.mention_badge.visible)


func test_mentions_aggregated() -> void:
	component.setup("MyFolder", _guilds_data_with_unread())
	# 3 + 2 = 5 total mentions
	assert_eq(component.mention_badge.count, 5)
	assert_true(component.mention_badge.visible)


func test_unread_shows_pill() -> void:
	component.setup("MyFolder", _guilds_data_with_unread())
	# Not active, but has unread -> UNREAD pill
	assert_eq(component.pill.pill_state, component.pill.PillState.UNREAD)


func test_no_unread_pill_hidden() -> void:
	component.setup("MyFolder", _guilds_data())
	assert_eq(component.pill.pill_state, component.pill.PillState.HIDDEN)


func test_active_overrides_unread_pill() -> void:
	component.setup("MyFolder", _guilds_data_with_unread())
	component.set_active(true)
	# Active overrides unread
	assert_eq(component.pill.pill_state, component.pill.PillState.ACTIVE)


# --- context menu ---

func test_has_context_menu() -> void:
	assert_not_null(component._context_menu)


func test_context_menu_items() -> void:
	component.setup("MyFolder", _guilds_data())
	component._show_context_menu(Vector2i(100, 100))
	# Should have: Rename Folder, Change Color, separator, Delete Folder
	assert_eq(component._context_menu.item_count, 4)
	assert_eq(component._context_menu.get_item_text(0), "Rename Folder")
	assert_eq(component._context_menu.get_item_text(1), "Change Color")
	assert_eq(component._context_menu.get_item_text(3), "Delete Folder")
