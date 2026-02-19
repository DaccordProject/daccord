extends GutTest

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
	var d := {
		"id": "c_1",
		"guild_id": "g_1",
		"name": "general",
		"type": ClientModels.ChannelType.TEXT,
		"unread": false,
		"voice_users": 0,
		"nsfw": false,
	}
	d.merge(overrides, true)
	return d


# --- setup ---

func test_setup_stores_ids() -> void:
	component.setup(_ch_data())
	assert_eq(component.channel_id, "c_1")
	assert_eq(component.guild_id, "g_1")


func test_setup_sets_channel_name() -> void:
	component.setup(_ch_data({"name": "announcements"}))
	assert_eq(component.channel_name.text, "announcements")


func test_setup_text_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.TEXT}))
	assert_eq(component.type_icon.texture, component.TEXT_ICON)


func test_setup_voice_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.VOICE}))
	assert_eq(component.type_icon.texture, component.VOICE_ICON)


func test_setup_announcement_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.ANNOUNCEMENT}))
	assert_eq(component.type_icon.texture, component.ANNOUNCEMENT_ICON)


func test_setup_forum_icon() -> void:
	component.setup(_ch_data({"type": ClientModels.ChannelType.FORUM}))
	assert_eq(component.type_icon.texture, component.FORUM_ICON)


func test_setup_nsfw_red_tint() -> void:
	component.setup(_ch_data({"nsfw": true}))
	# NSFW tints the icon red
	assert_eq(component.type_icon.modulate, Color(0.9, 0.2, 0.2))


func test_setup_non_nsfw_default_tint() -> void:
	component.setup(_ch_data({"nsfw": false}))
	assert_eq(component.type_icon.modulate, Color(0.58, 0.608, 0.643))


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
