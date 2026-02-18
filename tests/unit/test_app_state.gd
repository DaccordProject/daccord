extends GutTest

var app_state: Node


func before_each() -> void:
	app_state = load("res://scripts/autoload/app_state.gd").new()
	add_child(app_state)
	watch_signals(app_state)


func after_each() -> void:
	remove_child(app_state)
	app_state.free()


# --- select_guild ---

func test_select_guild_sets_current_guild_id() -> void:
	app_state.select_guild("guild_1")
	assert_eq(app_state.current_guild_id, "guild_1")


func test_select_guild_clears_dm_mode() -> void:
	app_state.is_dm_mode = true
	app_state.select_guild("guild_1")
	assert_false(app_state.is_dm_mode, "DM mode should be cleared after selecting a guild")


func test_select_guild_emits_signal() -> void:
	app_state.select_guild("guild_1")
	assert_signal_emitted(app_state, "guild_selected")
	assert_signal_emitted_with_parameters(app_state, "guild_selected", ["guild_1"])


# --- select_channel ---

func test_select_channel_sets_current_channel_id() -> void:
	app_state.select_channel("chan_3")
	assert_eq(app_state.current_channel_id, "chan_3")


func test_select_channel_emits_signal() -> void:
	app_state.select_channel("chan_3")
	assert_signal_emitted(app_state, "channel_selected")
	assert_signal_emitted_with_parameters(app_state, "channel_selected", ["chan_3"])


# --- enter_dm_mode ---

func test_enter_dm_mode_sets_flag() -> void:
	app_state.enter_dm_mode()
	assert_true(app_state.is_dm_mode)


func test_enter_dm_mode_clears_guild_id() -> void:
	app_state.current_guild_id = "guild_1"
	app_state.enter_dm_mode()
	assert_eq(app_state.current_guild_id, "")


func test_enter_dm_mode_emits_signal() -> void:
	app_state.enter_dm_mode()
	assert_signal_emitted(app_state, "dm_mode_entered")


# --- send_message ---

func test_send_message_emits_signal() -> void:
	app_state.send_message("Hello world")
	assert_signal_emitted(app_state, "message_sent")
	assert_signal_emitted_with_parameters(app_state, "message_sent", ["Hello world"])


# --- initiate_reply ---

func test_initiate_reply_sets_replying_id() -> void:
	app_state.initiate_reply("msg_1")
	assert_eq(app_state.replying_to_message_id, "msg_1")


func test_initiate_reply_clears_editing_id() -> void:
	app_state.editing_message_id = "msg_5"
	app_state.initiate_reply("msg_1")
	assert_eq(app_state.editing_message_id, "")


func test_initiate_reply_emits_signal() -> void:
	app_state.initiate_reply("msg_1")
	assert_signal_emitted(app_state, "reply_initiated")
	assert_signal_emitted_with_parameters(app_state, "reply_initiated", ["msg_1"])


# --- cancel_reply ---

func test_cancel_reply_clears_replying_id() -> void:
	app_state.replying_to_message_id = "msg_1"
	app_state.cancel_reply()
	assert_eq(app_state.replying_to_message_id, "")


func test_cancel_reply_emits_signal() -> void:
	app_state.cancel_reply()
	assert_signal_emitted(app_state, "reply_cancelled")


# --- start_editing ---

func test_start_editing_sets_editing_id() -> void:
	app_state.start_editing("msg_3")
	assert_eq(app_state.editing_message_id, "msg_3")


func test_start_editing_clears_replying_id() -> void:
	app_state.replying_to_message_id = "msg_1"
	app_state.start_editing("msg_3")
	assert_eq(app_state.replying_to_message_id, "")


# --- edit_message ---

func test_edit_message_clears_editing_id() -> void:
	app_state.editing_message_id = "msg_3"
	app_state.edit_message("msg_3", "new content")
	assert_eq(app_state.editing_message_id, "")


func test_edit_message_emits_signal() -> void:
	app_state.edit_message("msg_3", "new content")
	assert_signal_emitted(app_state, "message_edited")
	assert_signal_emitted_with_parameters(app_state, "message_edited", ["msg_3", "new content"])


# --- delete_message ---

func test_delete_message_emits_signal() -> void:
	app_state.delete_message("msg_1")
	assert_signal_emitted(app_state, "message_deleted")
	assert_signal_emitted_with_parameters(app_state, "message_deleted", ["msg_1"])


# --- State transitions ---

func test_select_guild_then_dm_mode_clears_guild() -> void:
	app_state.select_guild("guild_2")
	assert_eq(app_state.current_guild_id, "guild_2")
	app_state.enter_dm_mode()
	assert_eq(app_state.current_guild_id, "")
	assert_true(app_state.is_dm_mode)


func test_initiate_reply_then_start_editing_clears_reply() -> void:
	app_state.initiate_reply("msg_1")
	assert_eq(app_state.replying_to_message_id, "msg_1")
	app_state.start_editing("msg_5")
	assert_eq(app_state.replying_to_message_id, "")
	assert_eq(app_state.editing_message_id, "msg_5")


# --- update_layout_mode ---

func test_update_layout_mode_compact() -> void:
	app_state.update_layout_mode(400.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.COMPACT)


func test_update_layout_mode_medium() -> void:
	app_state.update_layout_mode(600.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.MEDIUM)


func test_update_layout_mode_full() -> void:
	app_state.update_layout_mode(1024.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.FULL)


func test_update_layout_mode_emits_signal_on_change() -> void:
	app_state.update_layout_mode(400.0)
	assert_signal_emitted(app_state, "layout_mode_changed")
	assert_signal_emitted_with_parameters(app_state, "layout_mode_changed", [app_state.LayoutMode.COMPACT])


func test_update_layout_mode_no_signal_when_unchanged() -> void:
	app_state.update_layout_mode(1024.0)
	# Default is FULL, so calling with >768 should not emit
	assert_signal_not_emitted(app_state, "layout_mode_changed")


func test_update_layout_mode_boundary_500_is_medium() -> void:
	app_state.update_layout_mode(500.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.MEDIUM)


func test_update_layout_mode_boundary_768_is_full() -> void:
	app_state.update_layout_mode(768.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.FULL)


func test_update_layout_mode_boundary_499_is_compact() -> void:
	app_state.update_layout_mode(499.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.COMPACT)


# --- toggle_sidebar_drawer ---

func test_toggle_sidebar_drawer_opens() -> void:
	app_state.toggle_sidebar_drawer()
	assert_true(app_state.sidebar_drawer_open)


func test_toggle_sidebar_drawer_closes() -> void:
	app_state.sidebar_drawer_open = true
	app_state.toggle_sidebar_drawer()
	assert_false(app_state.sidebar_drawer_open)


func test_toggle_sidebar_drawer_emits_signal_open() -> void:
	app_state.toggle_sidebar_drawer()
	assert_signal_emitted(app_state, "sidebar_drawer_toggled")
	assert_signal_emitted_with_parameters(app_state, "sidebar_drawer_toggled", [true])


func test_toggle_sidebar_drawer_emits_signal_close() -> void:
	app_state.sidebar_drawer_open = true
	app_state.toggle_sidebar_drawer()
	assert_signal_emitted(app_state, "sidebar_drawer_toggled")
	assert_signal_emitted_with_parameters(app_state, "sidebar_drawer_toggled", [false])


# --- close_sidebar_drawer ---

func test_close_sidebar_drawer_when_open() -> void:
	app_state.sidebar_drawer_open = true
	app_state.close_sidebar_drawer()
	assert_false(app_state.sidebar_drawer_open)


func test_close_sidebar_drawer_emits_signal_when_open() -> void:
	app_state.sidebar_drawer_open = true
	app_state.close_sidebar_drawer()
	assert_signal_emitted(app_state, "sidebar_drawer_toggled")
	assert_signal_emitted_with_parameters(app_state, "sidebar_drawer_toggled", [false])


func test_close_sidebar_drawer_no_signal_when_already_closed() -> void:
	app_state.close_sidebar_drawer()
	assert_signal_not_emitted(app_state, "sidebar_drawer_toggled")


# --- Layout + drawer transitions ---

func test_layout_mode_transition_compact_to_full() -> void:
	app_state.update_layout_mode(400.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.COMPACT)
	app_state.update_layout_mode(1024.0)
	assert_eq(app_state.current_layout_mode, app_state.LayoutMode.FULL)
	assert_signal_emit_count(app_state, "layout_mode_changed", 2)
