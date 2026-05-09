extends GutTest

## Unit tests for ClientPlugins — guard logic for join_activity,
## check_active_session, voice join/leave, broadcast presence,
## space session cache, pending banner, and bundle edge cases.
##
## Strategy: create a mock Client node with minimal caches, instantiate
## ClientPlugins directly, and exercise early-return paths without
## network calls.

var client: Node
var plugins: ClientPlugins


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client.current_user = {
		"id": "user_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["user_1"] = client.current_user
	plugins = ClientPlugins.new(client)


func after_each() -> void:
	plugins = null
	client.free()


# ------------------------------------------------------------------
# join_activity guards (early-return paths before any network call)
# ------------------------------------------------------------------

func test_join_activity_noop_when_empty_plugin_id() -> void:
	AppState.pending_activity_plugin_id = ""
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_state = "lobby"
	plugins.join_activity()
	assert_eq(plugins._active_session_id, "")
	# Cleanup
	AppState.pending_activity_session_id = ""
	AppState.pending_activity_state = ""


func test_join_activity_noop_when_empty_session_id() -> void:
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_session_id = ""
	AppState.pending_activity_state = "lobby"
	plugins.join_activity()
	assert_eq(plugins._active_session_id, "")
	# Cleanup
	AppState.pending_activity_plugin_id = ""
	AppState.pending_activity_state = ""


func test_join_activity_noop_when_state_running() -> void:
	# Non-participants cannot join a session that is already running
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_state = "running"
	plugins.join_activity()
	assert_eq(plugins._active_session_id, "")
	# Cleanup
	AppState.pending_activity_plugin_id = ""
	AppState.pending_activity_session_id = ""
	AppState.pending_activity_state = ""


func test_join_activity_noop_when_plugin_not_found() -> void:
	# Plugin not in cache -> conn_idx == -1 -> early return
	AppState.pending_activity_plugin_id = "nonexistent_plugin"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_channel_id = "ch_1"
	AppState.pending_activity_host_user_id = "host_1"
	AppState.pending_activity_state = "lobby"
	plugins.join_activity()
	assert_eq(plugins._active_session_id, "")
	assert_push_error(
		"[ClientPlugins] Plugin not found for join: "
		+ "nonexistent_plugin"
	)
	# Cleanup
	AppState.pending_activity_plugin_id = ""
	AppState.pending_activity_session_id = ""
	AppState.pending_activity_channel_id = ""
	AppState.pending_activity_host_user_id = ""
	AppState.pending_activity_state = ""


# ------------------------------------------------------------------
# check_active_session guards
# ------------------------------------------------------------------

func test_check_active_session_noop_when_empty_channel() -> void:
	plugins.check_active_session("", 0)
	assert_eq(plugins._active_session_id, "")


func test_check_active_session_noop_when_negative_conn() -> void:
	plugins.check_active_session("ch_1", -1)
	assert_eq(plugins._active_session_id, "")


func test_check_active_session_noop_when_conn_out_of_range() -> void:
	# _connections is empty, so conn_index 0 is out of range
	plugins.check_active_session("ch_1", 0)
	assert_eq(plugins._active_session_id, "")


func test_check_active_session_noop_when_already_active() -> void:
	# If there's already an active session, skip discovery
	AppState.active_activity_session_id = "existing_sess"
	plugins.check_active_session("ch_1", 0)
	assert_eq(plugins._active_session_id, "")
	# Cleanup
	AppState.active_activity_session_id = ""


# ------------------------------------------------------------------
# _on_voice_joined guards
# ------------------------------------------------------------------

func test_on_voice_joined_noop_when_unknown_channel() -> void:
	# Channel not in _channel_to_space -> early return
	plugins._on_voice_joined("unknown_channel_xyz")
	assert_eq(plugins._active_session_id, "")


func test_on_voice_joined_noop_when_no_conn_for_space() -> void:
	# Channel maps to a space, but space has no connection
	client._channel_to_space["ch_orphan"] = "space_orphan"
	plugins._on_voice_joined("ch_orphan")
	assert_eq(plugins._active_session_id, "")
	# Cleanup
	client._channel_to_space.erase("ch_orphan")


# ------------------------------------------------------------------
# _on_voice_left — intentional vs unintentional
# ------------------------------------------------------------------

func test_voice_left_preserves_runtime_on_unintentional() -> void:
	# Non-intentional disconnect (network drop) should keep the
	# runtime alive so game state is preserved for reconnection.
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime
	plugins._active_session_id = "sess_1"
	AppState.active_activity_plugin_id = "p1"
	AppState.active_activity_channel_id = "ch_1"

	plugins._on_voice_left("ch_1", false)

	# Runtime should still be alive
	assert_not_null(plugins._active_runtime)
	assert_eq(plugins._active_session_id, "sess_1")
	assert_eq(AppState.active_activity_plugin_id, "p1")

	# Cleanup
	plugins._active_runtime = null
	plugins._active_session_id = ""
	AppState.active_activity_plugin_id = ""
	AppState.active_activity_channel_id = ""
	mock_runtime.free()


func test_voice_left_always_clears_pending() -> void:
	# Pending activity is cleared even on unintentional disconnect
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_channel_id = "ch_1"

	plugins._on_voice_left("ch_1", false)

	assert_eq(AppState.pending_activity_plugin_id, "")
	assert_eq(AppState.pending_activity_session_id, "")


# ------------------------------------------------------------------
# _broadcast_activity_presence guards
# ------------------------------------------------------------------

func test_broadcast_presence_noop_empty_connections() -> void:
	assert_eq(client._connections.size(), 0)
	plugins._broadcast_activity_presence("p1")
	assert_true(true, "no crash with empty connections")


func test_broadcast_presence_skips_null_connections() -> void:
	client._connections = [null]
	plugins._broadcast_activity_presence("p1")
	assert_true(true, "no crash with null connection entries")
	# Cleanup
	client._connections = []


# ------------------------------------------------------------------
# get_space_sessions cache
# ------------------------------------------------------------------

func test_get_space_sessions_empty_by_default() -> void:
	assert_eq(plugins.get_space_sessions("unknown_space"), [])


func test_get_space_sessions_returns_cached() -> void:
	plugins._space_sessions["space_1"] = {
		"sess_1": {
			"id": "sess_1", "plugin_id": "p1", "state": "lobby",
		},
		"sess_2": {
			"id": "sess_2", "plugin_id": "p2", "state": "running",
		},
	}
	var result: Array = plugins.get_space_sessions("space_1")
	assert_eq(result.size(), 2)
	# Cleanup
	plugins._space_sessions.erase("space_1")


# ------------------------------------------------------------------
# on_plugin_session_state — space session cache updates
# ------------------------------------------------------------------

func test_session_state_updates_space_cache() -> void:
	# A session state event for a non-active session should update
	# the space-level session cache.
	plugins._active_session_id = ""
	client._channel_to_space["ch_1"] = "space_1"
	AppState.voice_channel_id = ""

	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_new",
		"state": "lobby",
		"channel_id": "ch_1",
		"host_user_id": "host_1",
		"participants": [],
	}, 0)

	assert_true(plugins._space_sessions.has("space_1"))
	var cache: Dictionary = plugins._space_sessions["space_1"]
	assert_true(cache.has("sess_new"))
	assert_eq(cache["sess_new"]["state"], "lobby")
	assert_eq(cache["sess_new"]["plugin_id"], "p1")

	# Cleanup
	plugins._space_sessions.erase("space_1")
	client._channel_to_space.erase("ch_1")


func test_session_state_ended_removes_from_space_cache() -> void:
	plugins._active_session_id = ""
	client._channel_to_space["ch_1"] = "space_1"
	plugins._space_sessions["space_1"] = {
		"sess_1": {
			"id": "sess_1", "plugin_id": "p1", "state": "lobby",
		},
	}

	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "ended",
		"channel_id": "ch_1",
	}, 0)

	assert_false(
		plugins._space_sessions["space_1"].has("sess_1")
	)

	# Cleanup
	plugins._space_sessions.erase("space_1")
	client._channel_to_space.erase("ch_1")


func test_session_state_sets_pending_when_in_voice() -> void:
	# New lobby session in our voice channel -> pending activity
	plugins._active_session_id = ""
	AppState.active_activity_session_id = ""
	AppState.voice_channel_id = "ch_1"
	client._channel_to_space["ch_1"] = "space_1"

	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "lobby",
		"channel_id": "ch_1",
		"host_user_id": "host_user",
	}, 0)

	assert_eq(AppState.pending_activity_plugin_id, "p1")
	assert_eq(AppState.pending_activity_session_id, "sess_1")
	assert_eq(AppState.pending_activity_channel_id, "ch_1")
	assert_eq(
		AppState.pending_activity_host_user_id, "host_user"
	)
	assert_eq(AppState.pending_activity_state, "lobby")

	# Cleanup
	plugins._clear_pending_activity()
	AppState.voice_channel_id = ""
	client._channel_to_space.erase("ch_1")
	plugins._space_sessions.erase("space_1")


func test_session_state_ignores_when_not_in_voice() -> void:
	# Lobby session in a different voice channel -> no pending
	plugins._active_session_id = ""
	AppState.active_activity_session_id = ""
	AppState.voice_channel_id = "ch_other"
	client._channel_to_space["ch_1"] = "space_1"

	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "lobby",
		"channel_id": "ch_1",
		"host_user_id": "host_user",
	}, 0)

	assert_eq(AppState.pending_activity_plugin_id, "")

	# Cleanup
	AppState.voice_channel_id = ""
	client._channel_to_space.erase("ch_1")
	plugins._space_sessions.erase("space_1")


func test_session_state_no_pending_when_already_active() -> void:
	# Don't overwrite an already-active activity.
	plugins._active_session_id = ""
	AppState.active_activity_session_id = "existing_sess"
	AppState.voice_channel_id = "ch_1"
	client._channel_to_space["ch_1"] = "space_1"

	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_new",
		"state": "lobby",
		"channel_id": "ch_1",
		"host_user_id": "host_user",
	}, 0)

	assert_eq(AppState.pending_activity_plugin_id, "")

	# Cleanup
	AppState.active_activity_session_id = ""
	AppState.voice_channel_id = ""
	client._channel_to_space.erase("ch_1")
	plugins._space_sessions.erase("space_1")


# ------------------------------------------------------------------
# on_plugin_role_changed — participants list update
# ------------------------------------------------------------------

func test_role_changed_updates_participants_array() -> void:
	# When the event includes participants, _session_participants
	# should be updated.
	var new_participants := [
		{"user_id": "u1", "role": "player"},
		{"user_id": "u2", "role": "spectator"},
	]
	plugins.on_plugin_role_changed({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"user_id": "u2",
		"role": "spectator",
		"participants": new_participants,
	}, 0)

	assert_eq(plugins._session_participants.size(), 2)
	assert_eq(
		plugins._session_participants[1]["role"], "spectator"
	)

	# Cleanup
	plugins._session_participants = []


# ------------------------------------------------------------------
# _extract_bundle — module name collision
# ------------------------------------------------------------------

func test_extract_bundle_module_name_collision() -> void:
	# Two .lua files with the same basename at different paths:
	# get_file().get_basename() produces the same module name.
	var modules := {
		"src/utils.lua": "return 'first'",
		"lib/utils.lua": "return 'second'",
	}
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/main.lua", "require('utils')", modules, {}
	)
	var manifest := {"entry_point": "src/main.lua"}
	var helpers_class = ClientPlugins.HelpersClass
	var result: Dictionary = helpers_class.extract_bundle(
		zip_bytes, manifest
	)

	assert_false(result.is_empty())
	var mods: Dictionary = result.get("modules", {})
	# Both files produce module name "utils" — one overwrites
	assert_true(mods.has("utils"))
	assert_true(
		mods["utils"] == "return 'first'"
		or mods["utils"] == "return 'second'"
	)


# ------------------------------------------------------------------
# fetch_plugins guards
# ------------------------------------------------------------------

func test_fetch_plugins_noop_when_negative_conn_index() -> void:
	plugins.fetch_plugins(-1, "space_1")
	assert_eq(plugins.get_plugins(-1), [])


func test_fetch_plugins_noop_when_conn_out_of_range() -> void:
	plugins.fetch_plugins(99, "space_1")
	assert_eq(plugins.get_plugins(99), [])


# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

class _MockRuntime:
	extends Node
	var received: Array = []
	var participants: Array = []

	func on_data_received(
		sender_id: String, topic: String,
		payload: PackedByteArray,
	) -> void:
		received.append({
			"sender_id": sender_id,
			"topic": topic,
			"payload": payload,
		})

	func on_plugin_event(
		event_type: String, data: Dictionary,
	) -> void:
		received.append({"type": event_type, "data": data})

	func get_viewport_texture() -> ViewportTexture:
		return null

	func forward_input(_event: InputEvent) -> void:
		received.append({"type": "input"})

	func stop() -> void:
		pass


func _build_test_zip(
	entry_path: String, entry_source: String,
	extra_lua: Dictionary, assets: Dictionary,
) -> PackedByteArray:
	var tmp_path := "user://test_build_zip_guards.zip"
	var packer := ZIPPacker.new()
	packer.open(tmp_path)
	packer.start_file(entry_path)
	packer.write_file(entry_source.to_utf8_buffer())
	packer.close_file()
	for path in extra_lua:
		packer.start_file(path)
		packer.write_file(extra_lua[path].to_utf8_buffer())
		packer.close_file()
	for path in assets:
		packer.start_file(path)
		packer.write_file(assets[path])
		packer.close_file()
	packer.close()
	var f := FileAccess.open(tmp_path, FileAccess.READ)
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	DirAccess.remove_absolute(
		ProjectSettings.globalize_path(tmp_path)
	)
	return bytes
