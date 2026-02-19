extends GutTest

var component: PanelContainer


func before_each() -> void:
	Client.current_user = {
		"id": "test_user_1",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	component = load("res://scenes/sidebar/user_bar.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _user_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "u_1",
		"display_name": "Alice",
		"username": "alice",
		"color": Color(0.345, 0.396, 0.949),
		"status": 0,
		"avatar": null,
	}
	d.merge(overrides, true)
	return d


# --- setup with null avatar ---

func test_setup_with_null_avatar_no_crash() -> void:
	component.setup(_user_data({"avatar": null}))
	assert_true(is_instance_valid(component.avatar))


func test_setup_with_missing_avatar_key_no_crash() -> void:
	var data := _user_data()
	data.erase("avatar")
	component.setup(data)
	assert_true(is_instance_valid(component.avatar))


func test_setup_with_empty_avatar_no_crash() -> void:
	component.setup(_user_data({"avatar": ""}))
	assert_true(is_instance_valid(component.avatar))


# --- setup with valid avatar ---

func test_setup_with_avatar_url() -> void:
	component.setup(_user_data({"avatar": "https://example.com/avatar.png"}))
	assert_true(is_instance_valid(component.avatar))


# --- display name and username ---

func test_display_name_from_dict() -> void:
	component.setup(_user_data())
	assert_eq(component.display_name.text, "Alice")


func test_username_from_dict() -> void:
	component.setup(_user_data())
	assert_eq(component.username.text, "alice")


func test_display_name_default_when_missing() -> void:
	var data := _user_data()
	data.erase("display_name")
	component.setup(data)
	assert_eq(component.display_name.text, "User")


func test_username_default_when_missing() -> void:
	var data := _user_data()
	data.erase("username")
	component.setup(data)
	assert_eq(component.username.text, "user")


# --- avatar letter ---

func test_avatar_letter_set_from_display_name() -> void:
	component.setup(_user_data({"display_name": "Bob"}))
	assert_eq(component.avatar.letter_label.text, "B")


func test_avatar_letter_empty_when_no_display_name() -> void:
	component.setup(_user_data({"display_name": ""}))
	assert_eq(component.avatar.letter_label.text, "")


# --- status ---

func test_status_icon_color_online() -> void:
	component.setup(_user_data({"status": ClientModels.UserStatus.ONLINE}))
	var expected: Color = ClientModels.status_color(ClientModels.UserStatus.ONLINE)
	assert_eq(component.status_icon.color, expected)


func test_status_icon_color_offline() -> void:
	component.setup(_user_data({"status": ClientModels.UserStatus.OFFLINE}))
	var expected: Color = ClientModels.status_color(ClientModels.UserStatus.OFFLINE)
	assert_eq(component.status_icon.color, expected)
