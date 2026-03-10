extends GutTest

const TestDataFactory := preload("res://tests/helpers/test_data_factory.gd")

var component: Button


func before_each() -> void:
	# Ensure Client has minimal state for permission checks
	Client.current_user = {
		"id": "test_user_1", "display_name": "TestUser",
		"username": "testuser", "color": Color.WHITE,
		"status": 0, "avatar": null, "is_admin": false,
	}
	component = load("res://scenes/sidebar/channels/channel_item.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _ch_data(overrides: Dictionary = {}) -> Dictionary:
	return TestDataFactory.channel_data(overrides)


# --- setup ---

func test_setup_stores_ids() -> void:
	component.setup(_ch_data())
	assert_eq(component.channel_id, "c_1")
	assert_eq(component.space_id, "g_1")


func test_setup_sets_channel_name() -> void:
	component.setup(_ch_data({"name": "announcements"}))
	assert_eq(component.channel_name.text, "announcements")


func test_setup_text_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.TEXT}))
	assert_eq(component.type_icon.texture, IconEmoji.get_texture("text_channel"))


func test_setup_voice_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.VOICE}))
	assert_eq(component.type_icon.texture, IconEmoji.get_texture("voice_channel"))


func test_setup_announcement_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.ANNOUNCEMENT}))
	assert_eq(component.type_icon.texture, IconEmoji.get_texture("announcement_channel"))


func test_setup_forum_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.FORUM}))
	assert_eq(component.type_icon.texture, IconEmoji.get_texture("forum_channel"))


func test_setup_nsfw_dimmed() -> void:
	component.setup(_ch_data({"nsfw": true}))
	# NSFW dims the icon
	assert_almost_eq(component.type_icon.modulate.a, 0.6, 0.01)


func test_setup_non_nsfw_full_alpha() -> void:
	component.setup(_ch_data({"nsfw": false}))
	assert_almost_eq(component.type_icon.modulate.a, 1.0, 0.01)


func test_setup_unread_dot_visible() -> void:
	component.setup(_ch_data({"unread": true}))
	assert_true(component.unread_dot.visible)


func test_setup_unread_dot_hidden() -> void:
	component.setup(_ch_data({"unread": false}))
	assert_false(component.unread_dot.visible)


func test_setup_unread_white_font() -> void:
	component.setup(_ch_data({"unread": true}))
	var color: Color = component.channel_name.get_theme_color("font_color")
	assert_eq(color, Color(1, 1, 1))


# --- set_active ---

func test_set_active_adds_style() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	var style = component.get_theme_stylebox("normal")
	assert_not_null(style)


func test_set_active_false_removes_style() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	component.set_active(false)
	# After removing, getting the style should return theme default
	# (not the custom StyleBoxFlat we added)
	var has_override: bool = component.has_theme_stylebox_override("normal")
	assert_false(has_override)


# --- signal ---

func test_has_channel_pressed_signal() -> void:
	assert_true(component.has_signal("channel_pressed"))


func test_stores_channel_data() -> void:
	var data := _ch_data()
	component.setup(data)
	assert_eq(component._channel_data["id"], "c_1")
	assert_eq(component._channel_data["name"], "general")


# --- locked state (imposter mode) ---

func test_locked_shows_lock_icon() -> void:
	component.setup(_ch_data({"locked": true}))
	assert_eq(component.type_icon.texture, IconEmoji.get_texture("lock"))


func test_locked_is_disabled() -> void:
	component.setup(_ch_data({"locked": true}))
	assert_true(component.disabled)


func test_locked_is_dimmed() -> void:
	component.setup(_ch_data({"locked": true}))
	assert_almost_eq(component.modulate.a, 0.4, 0.01)


func test_unlocked_is_not_disabled() -> void:
	component.setup(_ch_data({"locked": false}))
	assert_false(component.disabled)


func test_locked_flag_defaults_false() -> void:
	component.setup(_ch_data())
	assert_false(component._is_locked)


func test_locked_sets_is_locked_true() -> void:
	component.setup(_ch_data({"locked": true}))
	assert_true(component._is_locked)
