extends GutTest

## Unit tests for VoiceTextPanel messages component.
##
## Tests cover: UI element existence, visibility lifecycle via
## voice_text_opened/voice_text_closed signals, header text, and
## composer availability. Message rendering requires live server data
## and is excluded.

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
	# Stub Client._channel_cache so channel name lookup works.
	# Client.channels is a computed property (getter only), so we must
	# populate the backing dictionary directly.
	Client._channel_cache = {"vc_1": {"id": "vc_1", "name": "Voice Chat"}}
	component = load("res://scenes/messages/voice_text_panel.tscn").instantiate()
	add_child(component)
	await get_tree().process_frame
	await get_tree().process_frame


func after_each() -> void:
	Client._channel_cache = {}
	if is_instance_valid(component):
		component.queue_free()
		await get_tree().process_frame


# ---------------------------------------------------------------------------
# UI structure
# ---------------------------------------------------------------------------

func test_has_header_label() -> void:
	assert_not_null(component.header_label)
	assert_true(component.header_label is Label)


func test_has_close_button() -> void:
	assert_not_null(component.close_button)
	assert_true(component.close_button is Button)


func test_has_text_input() -> void:
	assert_not_null(component.text_input)
	assert_true(component.text_input is TextEdit)


func test_has_send_button() -> void:
	assert_not_null(component.send_button)
	assert_true(component.send_button is Button)


func test_has_message_list() -> void:
	assert_not_null(component.message_list)
	assert_true(component.message_list is VBoxContainer)


func test_has_scroll_container() -> void:
	assert_not_null(component.scroll_container)
	assert_true(component.scroll_container is ScrollContainer)


# ---------------------------------------------------------------------------
# Voice text opened → visible with correct header
# ---------------------------------------------------------------------------

func test_voice_text_opened_makes_panel_visible() -> void:
	component.visible = false
	component._on_voice_text_opened("vc_1")
	assert_true(component.visible)


func test_voice_text_opened_sets_header_from_channel_name() -> void:
	component._on_voice_text_opened("vc_1")
	assert_eq(component.header_label.text, "Voice Chat")


func test_voice_text_opened_stores_channel_id() -> void:
	component._on_voice_text_opened("vc_1")
	assert_eq(component._channel_id, "vc_1")


func test_voice_text_opened_uses_channel_id_as_fallback_name() -> void:
	# Channel not in Client.channels → falls back to channel_id
	component._on_voice_text_opened("vc_unknown")
	assert_eq(component.header_label.text, "vc_unknown")


# ---------------------------------------------------------------------------
# Voice text closed → hidden
# ---------------------------------------------------------------------------

func test_voice_text_closed_hides_panel() -> void:
	component._on_voice_text_opened("vc_1")
	component._on_voice_text_closed()
	assert_false(component.visible)


func test_voice_text_closed_clears_channel_id() -> void:
	component._on_voice_text_opened("vc_1")
	component._on_voice_text_closed()
	assert_eq(component._channel_id, "")


# ---------------------------------------------------------------------------
# AppState signal connections
# ---------------------------------------------------------------------------

func test_connected_to_voice_text_opened() -> void:
	assert_true(AppState.voice_text_opened.is_connected(component._on_voice_text_opened))


func test_connected_to_voice_text_closed() -> void:
	assert_true(AppState.voice_text_closed.is_connected(component._on_voice_text_closed))


func test_connected_to_messages_updated() -> void:
	assert_true(AppState.messages_updated.is_connected(component._on_messages_updated))


# ---------------------------------------------------------------------------
# Close button wiring
# ---------------------------------------------------------------------------

func test_close_button_is_connected() -> void:
	assert_true(component.close_button.pressed.get_connections().size() > 0)


# ---------------------------------------------------------------------------
# Send button wiring
# ---------------------------------------------------------------------------

func test_send_button_is_connected() -> void:
	assert_true(component.send_button.pressed.get_connections().size() > 0)
