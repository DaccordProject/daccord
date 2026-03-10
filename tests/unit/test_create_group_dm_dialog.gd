extends GutTest

var component: ColorRect


func before_each() -> void:
	Client.current_user = {
		"id": "me_1",
		"display_name": "Me",
		"username": "me",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	# Populate user cache with two non-bot, non-self users
	Client._user_cache = {
		"u_alice": {
			"id": "u_alice",
			"display_name": "Alice",
			"username": "alice",
			"bot": false,
		},
		"u_bob": {
			"id": "u_bob",
			"display_name": "Bob",
			"username": "bob",
			"bot": false,
		},
	}
	component = load(
		"res://scenes/sidebar/direct/create_group_dm_dialog.tscn"
	).instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame
	Client._user_cache = {}


# --- UI elements exist ---

func test_search_input_exists() -> void:
	assert_not_null(component.search_input)


func test_user_list_exists() -> void:
	assert_not_null(component.user_list)


func test_create_button_exists() -> void:
	assert_not_null(component.create_button)


func test_selected_label_exists() -> void:
	assert_not_null(component.selected_label)


func test_close_button_exists() -> void:
	assert_not_null(component.close_button)


# --- initial state ---

func test_create_button_disabled_initially() -> void:
	# 0 selected → disabled (requires ≥ 2)
	assert_true(component.create_button.disabled)


func test_selected_label_shows_zero_initially() -> void:
	assert_eq(component.selected_label.text, "0 users selected")


func test_user_list_populated_from_cache() -> void:
	# Two non-bot, non-self users should produce two checkboxes
	assert_eq(component.user_list.get_child_count(), 2)


# --- _on_user_toggled ---

func test_toggle_on_adds_to_selected_ids() -> void:
	component._on_user_toggled(true, "u_alice")
	assert_true(component._selected_ids.has("u_alice"))


func test_toggle_off_removes_from_selected_ids() -> void:
	component._on_user_toggled(true, "u_alice")
	component._on_user_toggled(false, "u_alice")
	assert_false(component._selected_ids.has("u_alice"))


func test_toggle_on_twice_no_duplicates() -> void:
	component._on_user_toggled(true, "u_alice")
	component._on_user_toggled(true, "u_alice")
	assert_eq(component._selected_ids.size(), 1)


# --- _update_selection_ui ---

func test_one_selected_still_disables_create_button() -> void:
	component._on_user_toggled(true, "u_alice")
	assert_true(component.create_button.disabled)


func test_two_selected_enables_create_button() -> void:
	component._on_user_toggled(true, "u_alice")
	component._on_user_toggled(true, "u_bob")
	assert_false(component.create_button.disabled)


func test_deselect_back_to_one_disables_create_button() -> void:
	component._on_user_toggled(true, "u_alice")
	component._on_user_toggled(true, "u_bob")
	component._on_user_toggled(false, "u_bob")
	assert_true(component.create_button.disabled)


func test_selected_label_singular_for_one_user() -> void:
	component._on_user_toggled(true, "u_alice")
	assert_eq(component.selected_label.text, "1 user selected")


func test_selected_label_plural_for_two_users() -> void:
	component._on_user_toggled(true, "u_alice")
	component._on_user_toggled(true, "u_bob")
	assert_eq(component.selected_label.text, "2 users selected")


# --- bot / self excluded from user list ---

func test_bot_users_not_shown() -> void:
	Client._user_cache["u_bot"] = {
		"id": "u_bot",
		"display_name": "BotUser",
		"username": "botuser",
		"bot": true,
	}
	component._populate_users()
	await get_tree().process_frame
	# Still only 2 (Alice + Bob)
	assert_eq(component.user_list.get_child_count(), 2)


func test_self_not_shown() -> void:
	# "me_1" is current_user — should be excluded
	Client._user_cache["me_1"] = {
		"id": "me_1",
		"display_name": "Me",
		"username": "me",
		"bot": false,
	}
	component._populate_users()
	await get_tree().process_frame
	assert_eq(component.user_list.get_child_count(), 2)
