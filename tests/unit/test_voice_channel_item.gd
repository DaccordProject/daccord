extends GutTest

## Unit tests for VoiceChannelItem sidebar component.
##
## Tests cover: setup (channel_id, space_id, name), set_active behaviour,
## and signal existence. Participant list population is skipped here as it
## requires Client.get_voice_users() (live server data).

var component: VBoxContainer


func before_each() -> void:
	Client.current_user = {
		"id": "u_test",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	component = load(
		"res://scenes/sidebar/channels/voice_channel_item.tscn"
	).instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


func _ch_data(overrides: Dictionary = {}) -> Dictionary:
	var d := {
		"id": "vc_1",
		"space_id": "g_1",
		"name": "General Voice",
		"type": ClientModels.ChannelType.VOICE,
		"unread": false,
		"voice_users": 0,
	}
	d.merge(overrides, true)
	return d


# ---------------------------------------------------------------------------
# Signal existence
# ---------------------------------------------------------------------------

func test_has_channel_pressed_signal() -> void:
	assert_true(component.has_signal("channel_pressed"))


# ---------------------------------------------------------------------------
# setup()
# ---------------------------------------------------------------------------

func test_setup_stores_channel_id() -> void:
	component.setup(_ch_data())
	assert_eq(component.channel_id, "vc_1")


func test_setup_stores_space_id() -> void:
	component.setup(_ch_data())
	assert_eq(component.space_id, "g_1")


func test_setup_sets_channel_name_label() -> void:
	component.setup(_ch_data({"name": "Main Stage"}))
	assert_eq(component.channel_name.text, "Main Stage")


func test_setup_sets_type_icon() -> void:
	component.setup(_ch_data())
	assert_not_null(component.type_icon.texture)


func test_setup_stores_channel_data_dict() -> void:
	var data := _ch_data()
	component.setup(data)
	assert_eq(component._channel_data["id"], "vc_1")


# ---------------------------------------------------------------------------
# set_active()
# ---------------------------------------------------------------------------

func test_set_active_true_shows_active_bg() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	assert_true(component.active_bg.visible)


func test_set_active_true_shows_active_pill() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	assert_true(component.active_pill.visible)


func test_set_active_false_hides_active_bg() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	component.set_active(false)
	assert_false(component.active_bg.visible)


func test_set_active_false_hides_active_pill() -> void:
	component.setup(_ch_data())
	component.set_active(true)
	component.set_active(false)
	assert_false(component.active_pill.visible)


# ---------------------------------------------------------------------------
# channel_pressed emits on button press
# ---------------------------------------------------------------------------

func test_channel_button_pressed_emits_signal() -> void:
	component.setup(_ch_data())
	watch_signals(component)
	component.channel_button.pressed.emit()
	assert_signal_emitted_with_parameters(
		component, "channel_pressed", ["vc_1"]
	)
