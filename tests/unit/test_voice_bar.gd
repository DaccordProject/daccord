extends GutTest

## Unit tests for VoiceBar sidebar component.
##
## Tests cover: initial hidden state, show/hide via voice_joined/voice_left
## signals, button structure, and disconnect button wiring.
## LiveKit session state transitions and Tween animations are excluded.

var component: PanelContainer


func before_each() -> void:
	Client.current_user = {
		"id": "u_test",
		"display_name": "TestUser",
		"username": "testuser",
		"color": Color.WHITE,
		"status": 0,
		"avatar": null,
	}
	component = load("res://scenes/sidebar/voice_bar.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# UI structure
# ---------------------------------------------------------------------------

func test_has_channel_label() -> void:
	assert_not_null(component.channel_label)
	assert_true(component.channel_label is Label)


func test_has_mute_button() -> void:
	assert_not_null(component.mute_btn)
	assert_true(component.mute_btn is Button)


func test_has_deafen_button() -> void:
	assert_not_null(component.deafen_btn)
	assert_true(component.deafen_btn is Button)


func test_has_disconnect_button() -> void:
	assert_not_null(component.disconnect_btn)
	assert_true(component.disconnect_btn is Button)


func test_has_settings_button() -> void:
	assert_not_null(component.settings_btn)
	assert_true(component.settings_btn is Button)


# ---------------------------------------------------------------------------
# Initial state
# ---------------------------------------------------------------------------

func test_initially_hidden() -> void:
	assert_false(component.visible)


# ---------------------------------------------------------------------------
# voice_left → hidden
# ---------------------------------------------------------------------------

func test_voice_left_hides_bar() -> void:
	component.visible = true
	component._on_voice_left("vc_1")
	assert_false(component.visible)


# ---------------------------------------------------------------------------
# Disconnect button wiring
# ---------------------------------------------------------------------------

func test_disconnect_button_is_connected() -> void:
	assert_true(component.disconnect_btn.pressed.get_connections().size() > 0)


func test_mute_button_is_connected() -> void:
	assert_true(component.mute_btn.pressed.get_connections().size() > 0)


func test_deafen_button_is_connected() -> void:
	assert_true(component.deafen_btn.pressed.get_connections().size() > 0)


# ---------------------------------------------------------------------------
# AppState signal connections
# ---------------------------------------------------------------------------

func test_connected_to_voice_joined() -> void:
	assert_true(AppState.voice_joined.is_connected(component._on_voice_joined))


func test_connected_to_voice_left() -> void:
	assert_true(AppState.voice_left.is_connected(component._on_voice_left))
