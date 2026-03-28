extends GutTest

## Unit tests for ClientPlugins helper — caching, gateway event handling,
## and voice disconnect cleanup.
##
## Strategy: create a mock Client node with minimal caches, instantiate
## ClientPlugins directly, and exercise pure logic without network calls.

var client: Node
var plugins: ClientPlugins


func before_each() -> void:
	client = load("res://scripts/autoload/client.gd").new()
	client.current_user = {
		"id": "user_1", "display_name": "Me", "is_admin": false,
	}
	client._user_cache["user_1"] = client.current_user
	# ClientPlugins is created inside _ready, but we can instantiate directly
	plugins = ClientPlugins.new(client)


func after_each() -> void:
	plugins = null
	client.free()


# ------------------------------------------------------------------
# Plugin cache
# ------------------------------------------------------------------

func test_get_plugins_empty_by_default() -> void:
	assert_eq(plugins.get_plugins(0), [])


func test_get_plugin_returns_empty_when_not_found() -> void:
	assert_eq(plugins.get_plugin("nonexistent"), {})


func test_get_conn_index_for_plugin_not_found() -> void:
	assert_eq(plugins.get_conn_index_for_plugin("nonexistent"), -1)


# ------------------------------------------------------------------
# Gateway: on_plugin_installed
# ------------------------------------------------------------------

func test_on_plugin_installed_adds_to_cache() -> void:
	var manifest := {
		"id": "plugin_1",
		"name": "Test Plugin",
		"runtime": "scripted",
		"type": "activity",
		"version": "1.0.0",
	}
	plugins.on_plugin_installed({"manifest": manifest}, 0)
	assert_eq(plugins.get_plugins(0).size(), 1)
	var cached: Dictionary = plugins.get_plugin("plugin_1")
	assert_eq(cached.get("name"), "Test Plugin")
	assert_eq(cached.get("runtime"), "scripted")


func test_on_plugin_installed_ignores_empty_id() -> void:
	plugins.on_plugin_installed({"manifest": {"name": "No ID"}}, 0)
	assert_eq(plugins.get_plugins(0).size(), 0)


func test_on_plugin_installed_updates_existing() -> void:
	var v1 := {"id": "p1", "name": "V1", "version": "1.0"}
	var v2 := {"id": "p1", "name": "V2", "version": "2.0"}
	plugins.on_plugin_installed({"manifest": v1}, 0)
	plugins.on_plugin_installed({"manifest": v2}, 0)
	assert_eq(plugins.get_plugins(0).size(), 1)
	assert_eq(plugins.get_plugin("p1").get("name"), "V2")


# ------------------------------------------------------------------
# Gateway: on_plugin_uninstalled
# ------------------------------------------------------------------

func test_on_plugin_uninstalled_removes_from_cache() -> void:
	plugins.on_plugin_installed(
		{"manifest": {"id": "p1", "name": "A"}}, 0
	)
	plugins.on_plugin_installed(
		{"manifest": {"id": "p2", "name": "B"}}, 0
	)
	assert_eq(plugins.get_plugins(0).size(), 2)

	plugins.on_plugin_uninstalled({"plugin_id": "p1"}, 0)
	assert_eq(plugins.get_plugins(0).size(), 1)
	assert_eq(plugins.get_plugin("p1"), {})
	assert_eq(plugins.get_plugin("p2").get("name"), "B")


func test_on_plugin_uninstalled_noop_for_unknown() -> void:
	plugins.on_plugin_uninstalled({"plugin_id": "unknown"}, 0)
	# Should not error


# ------------------------------------------------------------------
# Gateway: on_plugin_role_changed
# ------------------------------------------------------------------

func test_on_plugin_role_changed_updates_local_role() -> void:
	AppState.active_activity_plugin_id = "p1"
	plugins.on_plugin_role_changed({
		"plugin_id": "p1",
		"user_id": "user_1",
		"role": "spectator",
	}, 0)
	assert_eq(AppState.active_activity_role, "spectator")
	# Cleanup
	AppState.active_activity_plugin_id = ""
	AppState.active_activity_role = ""


func test_on_plugin_role_changed_ignores_other_users() -> void:
	AppState.active_activity_role = "player"
	plugins.on_plugin_role_changed({
		"plugin_id": "p1",
		"user_id": "other_user",
		"role": "spectator",
	}, 0)
	assert_eq(AppState.active_activity_role, "player")
	AppState.active_activity_role = ""


# ------------------------------------------------------------------
# Gateway: on_plugin_session_state
# ------------------------------------------------------------------

func test_on_plugin_session_state_updates_state() -> void:
	plugins._active_session_id = "sess_1"
	AppState.active_activity_plugin_id = "p1"
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "running",
	}, 0)
	assert_eq(AppState.active_activity_session_state, "running")
	# Cleanup
	plugins._active_session_id = ""
	AppState.active_activity_plugin_id = ""
	AppState.active_activity_session_state = ""


func test_on_plugin_session_state_ended_clears_activity() -> void:
	plugins._active_session_id = "sess_1"
	AppState.active_activity_plugin_id = "p1"
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "ended",
	}, 0)
	assert_eq(AppState.active_activity_plugin_id, "")
	assert_eq(plugins._active_session_id, "")


func test_on_plugin_session_state_running_clears_pending_and_emits() -> void:
	# Simulate the third user who saw the lobby invitation but didn't join.
	# When the session transitions to "running", their pending state must be
	# cleared AND activity_ended must be emitted so the UI removes the banner.
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_channel_id = "ch_1"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_host_user_id = "host_1"
	AppState.pending_activity_state = "lobby"
	plugins._active_session_id = ""  # not a participant

	watch_signals(AppState)
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "running",
		"channel_id": "ch_1",
	}, 0)

	assert_eq(AppState.pending_activity_plugin_id, "")
	assert_eq(AppState.pending_activity_session_id, "")
	assert_signal_emitted(AppState, "activity_ended")


func test_on_plugin_session_state_ended_clears_pending_and_emits() -> void:
	# Same scenario but session ends entirely instead of starting.
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_channel_id = "ch_1"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_host_user_id = "host_1"
	AppState.pending_activity_state = "lobby"
	plugins._active_session_id = ""

	watch_signals(AppState)
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "ended",
		"channel_id": "ch_1",
	}, 0)

	assert_eq(AppState.pending_activity_plugin_id, "")
	assert_eq(AppState.pending_activity_session_id, "")
	assert_signal_emitted(AppState, "activity_ended")


func test_on_plugin_session_state_running_no_emit_when_not_pending() -> void:
	# If the session that transitioned to "running" isn't our pending one,
	# activity_ended should NOT be emitted.
	AppState.pending_activity_session_id = "other_sess"
	plugins._active_session_id = ""

	watch_signals(AppState)
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_1",
		"state": "running",
		"channel_id": "ch_1",
	}, 0)

	assert_signal_not_emitted(AppState, "activity_ended")
	# Cleanup
	AppState.pending_activity_session_id = ""


func test_on_plugin_session_state_ignores_other_sessions() -> void:
	plugins._active_session_id = "sess_1"
	AppState.active_activity_session_state = "lobby"
	plugins.on_plugin_session_state({
		"plugin_id": "p1",
		"session_id": "sess_other",
		"state": "running",
	}, 0)
	assert_eq(AppState.active_activity_session_state, "lobby")
	# Cleanup
	plugins._active_session_id = ""
	AppState.active_activity_session_state = ""


# ------------------------------------------------------------------
# Voice disconnect cleanup
# ------------------------------------------------------------------

func test_voice_left_clears_active_activity() -> void:
	plugins._active_session_id = "sess_1"
	AppState.active_activity_plugin_id = "p1"
	AppState.active_activity_channel_id = "ch_1"

	watch_signals(AppState)
	plugins._on_voice_left("ch_1")

	assert_eq(plugins._active_session_id, "")
	assert_eq(AppState.active_activity_plugin_id, "")
	assert_signal_emitted(AppState, "activity_ended")


func test_voice_left_noop_when_no_activity() -> void:
	# Should not error when no active activity
	plugins._on_voice_left("ch_1")
	assert_eq(plugins._active_session_id, "")


# ------------------------------------------------------------------
# get_conn_index_for_plugin
# ------------------------------------------------------------------

func test_get_conn_index_for_plugin_found() -> void:
	plugins.on_plugin_installed(
		{"manifest": {"id": "p1", "name": "A"}}, 2
	)
	assert_eq(plugins.get_conn_index_for_plugin("p1"), 2)


# ------------------------------------------------------------------
# Multiple connections
# ------------------------------------------------------------------

func test_plugins_isolated_per_connection() -> void:
	plugins.on_plugin_installed(
		{"manifest": {"id": "p1", "name": "A"}}, 0
	)
	plugins.on_plugin_installed(
		{"manifest": {"id": "p2", "name": "B"}}, 1
	)
	assert_eq(plugins.get_plugins(0).size(), 1)
	assert_eq(plugins.get_plugins(1).size(), 1)
	assert_eq(plugins.get_plugin("p1").get("name"), "A")
	assert_eq(plugins.get_plugin("p2").get("name"), "B")


# ------------------------------------------------------------------
# _on_livekit_data_received — topic prefix stripping
# ------------------------------------------------------------------

func test_livekit_data_strips_prefix_and_routes() -> void:
	# Set up a mock runtime that records on_data_received calls
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime
	AppState.active_activity_plugin_id = "p1"

	plugins._on_livekit_data_received(
		"sender_1", "plugin:p1:game:move", "payload".to_utf8_buffer()
	)

	assert_eq(mock_runtime.received.size(), 1)
	assert_eq(mock_runtime.received[0]["sender_id"], "sender_1")
	assert_eq(mock_runtime.received[0]["topic"], "game:move")

	# Cleanup
	plugins._active_runtime = null
	AppState.active_activity_plugin_id = ""
	mock_runtime.free()


func test_livekit_data_ignores_wrong_plugin_prefix() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime
	AppState.active_activity_plugin_id = "p1"

	# Different plugin prefix — should be ignored
	plugins._on_livekit_data_received(
		"sender_1", "plugin:other:topic", "data".to_utf8_buffer()
	)

	assert_eq(mock_runtime.received.size(), 0)

	plugins._active_runtime = null
	AppState.active_activity_plugin_id = ""
	mock_runtime.free()


func test_livekit_data_ignores_when_no_runtime() -> void:
	plugins._active_runtime = null
	# Should not crash
	plugins._on_livekit_data_received(
		"sender_1", "plugin:p1:topic", "data".to_utf8_buffer()
	)


func test_livekit_data_ignores_non_plugin_topic() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime
	AppState.active_activity_plugin_id = "p1"

	plugins._on_livekit_data_received(
		"sender_1", "something:else", "data".to_utf8_buffer()
	)

	assert_eq(mock_runtime.received.size(), 0)

	plugins._active_runtime = null
	AppState.active_activity_plugin_id = ""
	mock_runtime.free()


# ------------------------------------------------------------------
# on_plugin_event — forwarding to active runtime
# ------------------------------------------------------------------

func test_on_plugin_event_forwards_to_runtime() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime

	plugins.on_plugin_event({
		"event_type": "game_update",
		"data": {"score": 42},
	}, 0)

	assert_eq(mock_runtime.events.size(), 1)
	assert_eq(mock_runtime.events[0]["type"], "game_update")
	assert_eq(mock_runtime.events[0]["data"].get("score"), 42)

	plugins._active_runtime = null
	mock_runtime.free()


func test_on_plugin_event_noop_when_no_runtime() -> void:
	plugins._active_runtime = null
	# Should not crash
	plugins.on_plugin_event({"event_type": "test", "data": {}}, 0)


# ------------------------------------------------------------------
# _update_scripted_participants
# ------------------------------------------------------------------

func test_update_scripted_participants_updates_existing() -> void:
	var mock_runtime := _MockRuntime.new()
	mock_runtime.participants = [
		{"user_id": "u1", "role": "player"},
		{"user_id": "u2", "role": "player"},
	]
	plugins._active_runtime = mock_runtime

	plugins._update_scripted_participants("u2", "spectator")

	assert_eq(mock_runtime.participants[1]["role"], "spectator")
	assert_eq(mock_runtime.participants.size(), 2)

	plugins._active_runtime = null
	mock_runtime.free()


func test_update_scripted_participants_adds_new() -> void:
	var mock_runtime := _MockRuntime.new()
	mock_runtime.participants = [
		{"user_id": "u1", "role": "player"},
	]
	plugins._active_runtime = mock_runtime

	plugins._update_scripted_participants("u3", "spectator")

	assert_eq(mock_runtime.participants.size(), 2)
	assert_eq(mock_runtime.participants[1]["user_id"], "u3")
	assert_eq(mock_runtime.participants[1]["role"], "spectator")

	plugins._active_runtime = null
	mock_runtime.free()


# ------------------------------------------------------------------
# _update_context_participants
# ------------------------------------------------------------------

func test_update_context_participants_updates_existing() -> void:
	var ctx := PluginContext.new()
	ctx.participants = [
		{"user_id": "u1", "role": "player"},
	]

	plugins._update_context_participants(ctx, "u1", "spectator")
	assert_eq(ctx.participants[0]["role"], "spectator")
	assert_eq(ctx.participants.size(), 1)


func test_update_context_participants_adds_new() -> void:
	var ctx := PluginContext.new()
	ctx.participants = []

	plugins._update_context_participants(ctx, "u1", "player")
	assert_eq(ctx.participants.size(), 1)
	assert_eq(ctx.participants[0]["user_id"], "u1")


# ------------------------------------------------------------------
# on_plugin_uninstalled clears active activity
# ------------------------------------------------------------------

func test_uninstall_active_plugin_clears_activity() -> void:
	plugins.on_plugin_installed(
		{"manifest": {"id": "p1", "name": "A"}}, 0
	)
	AppState.active_activity_plugin_id = "p1"
	plugins._active_session_id = "sess_1"

	watch_signals(AppState)
	plugins.on_plugin_uninstalled({"plugin_id": "p1"}, 0)

	assert_eq(AppState.active_activity_plugin_id, "")
	assert_eq(plugins._active_session_id, "")
	assert_signal_emitted(AppState, "activity_ended")


# ------------------------------------------------------------------
# Mock runtime helper
# ------------------------------------------------------------------

class _MockRuntime:
	extends Node
	var received: Array = []
	var events: Array = []
	var participants: Array = []

	func on_data_received(
		sender_id: String, topic: String, payload: PackedByteArray,
	) -> void:
		received.append({
			"sender_id": sender_id, "topic": topic, "payload": payload,
		})

	func on_plugin_event(event_type: String, data: Dictionary) -> void:
		events.append({"type": event_type, "data": data})

	func get_viewport_texture() -> ViewportTexture:
		return null

	func forward_input(_event: InputEvent) -> void:
		received.append({"type": "input"})

	func stop() -> void:
		pass


# ------------------------------------------------------------------
# _extract_bundle — ZIP construction and extraction
# ------------------------------------------------------------------

func test_extract_bundle_valid_zip() -> void:
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/main.lua", "print('hello')", {}, {}
	)
	var manifest := {"entry_point": "src/main.lua"}
	var result: Dictionary = plugins._extract_bundle(zip_bytes, manifest)

	assert_false(result.is_empty())
	assert_eq(result.get("lua_source"), "print('hello')")
	assert_true(result.has("modules"))
	assert_true(result.has("assets"))


func test_extract_bundle_default_entry_point() -> void:
	# When entry_point is empty, falls back to manifest.entry then "src/main.lua"
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/main.lua", "return 42", {}, {}
	)
	var manifest := {}  # No entry_point specified
	var result: Dictionary = plugins._extract_bundle(zip_bytes, manifest)

	assert_false(result.is_empty())
	assert_eq(result.get("lua_source"), "return 42")


func test_extract_bundle_missing_entry_returns_empty() -> void:
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/other.lua", "print('wrong')", {}, {}
	)
	var manifest := {"entry_point": "src/main.lua"}
	var result: Dictionary = plugins._extract_bundle(zip_bytes, manifest)

	assert_eq(result, {})
	assert_push_error("[ClientPlugins] Entry file not found in bundle: src/main.lua")


func test_extract_bundle_extracts_modules() -> void:
	var modules := {"src/utils.lua": "return {}", "src/lib/math.lua": "return 1"}
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/main.lua", "require('utils')", modules, {}
	)
	var manifest := {"entry_point": "src/main.lua"}
	var result: Dictionary = plugins._extract_bundle(zip_bytes, manifest)

	assert_false(result.is_empty())
	var mods: Dictionary = result.get("modules", {})
	# Module name is filename without extension
	assert_true(mods.has("utils"))
	assert_eq(mods["utils"], "return {}")
	assert_true(mods.has("math"))
	assert_eq(mods["math"], "return 1")


func test_extract_bundle_extracts_assets() -> void:
	var asset_data: PackedByteArray = "PNG_DATA".to_utf8_buffer()
	var assets := {"assets/sprite.png": asset_data}
	var zip_bytes: PackedByteArray = _build_test_zip(
		"src/main.lua", "-- main", {}, assets
	)
	var manifest := {"entry_point": "src/main.lua"}
	var result: Dictionary = plugins._extract_bundle(zip_bytes, manifest)

	assert_false(result.is_empty())
	var result_assets: Dictionary = result.get("assets", {})
	assert_true(result_assets.has("assets/sprite.png"))
	assert_eq(
		result_assets["assets/sprite.png"],
		"PNG_DATA".to_utf8_buffer()
	)


func test_extract_bundle_invalid_zip_returns_empty() -> void:
	var bad_bytes: PackedByteArray = "not a zip".to_utf8_buffer()
	var manifest := {"entry_point": "src/main.lua"}
	var result: Dictionary = plugins._extract_bundle(bad_bytes, manifest)

	assert_eq(result, {})


# Helper: builds a ZIP file as PackedByteArray using ZIPPacker
func _build_test_zip(
	entry_path: String, entry_source: String,
	extra_lua: Dictionary, assets: Dictionary,
) -> PackedByteArray:
	var tmp_path := "user://test_build_zip.zip"
	var packer := ZIPPacker.new()
	packer.open(tmp_path)
	# Entry file
	packer.start_file(entry_path)
	packer.write_file(entry_source.to_utf8_buffer())
	packer.close_file()
	# Extra Lua modules
	for path in extra_lua:
		packer.start_file(path)
		packer.write_file(extra_lua[path].to_utf8_buffer())
		packer.close_file()
	# Assets (binary)
	for path in assets:
		packer.start_file(path)
		packer.write_file(assets[path])
		packer.close_file()
	packer.close()
	var f := FileAccess.open(tmp_path, FileAccess.READ)
	var bytes: PackedByteArray = f.get_buffer(f.get_length())
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp_path))
	return bytes


# ------------------------------------------------------------------
# _is_plugin_trusted
# ------------------------------------------------------------------

func test_is_plugin_trusted_default_false() -> void:
	# Unknown server/plugin should not be trusted
	var result: bool = plugins._is_plugin_trusted(
		"unknown_server_xyz", "unknown_plugin_xyz"
	)
	assert_false(result)


func test_is_plugin_trusted_trust_all() -> void:
	var server_id := "test_trust_all_server"
	Config.set_plugin_trust_all(server_id, true)

	assert_true(plugins._is_plugin_trusted(server_id, "any_plugin"))

	# Cleanup
	Config.set_plugin_trust_all(server_id, false)


func test_is_plugin_trusted_specific_plugin() -> void:
	var server_id := "test_trust_specific_server"
	var plugin_id := "test_trust_specific_plugin"
	Config.set_plugin_trust(server_id, plugin_id, true)

	assert_true(plugins._is_plugin_trusted(server_id, plugin_id))
	# A different plugin on the same server should not be trusted
	assert_false(plugins._is_plugin_trusted(server_id, "other_plugin"))

	# Cleanup
	Config.set_plugin_trust(server_id, plugin_id, false)


# ------------------------------------------------------------------
# _clear_pending_activity
# ------------------------------------------------------------------

func test_clear_pending_activity_resets_state() -> void:
	AppState.pending_activity_plugin_id = "p1"
	AppState.pending_activity_channel_id = "ch_1"
	AppState.pending_activity_session_id = "sess_1"
	AppState.pending_activity_host_user_id = "host_1"
	AppState.pending_activity_state = "lobby"

	plugins._clear_pending_activity()

	assert_eq(AppState.pending_activity_plugin_id, "")
	assert_eq(AppState.pending_activity_channel_id, "")
	assert_eq(AppState.pending_activity_session_id, "")
	assert_eq(AppState.pending_activity_host_user_id, "")
	assert_eq(AppState.pending_activity_state, "")


# ------------------------------------------------------------------
# _clear_active_activity
# ------------------------------------------------------------------

func test_clear_active_activity_resets_state() -> void:
	plugins._active_session_id = "sess_1"
	plugins._active_conn_index = 2
	plugins._is_host = true
	plugins._host_user_id = "host_1"
	plugins._session_participants = [{"user_id": "u1"}]
	AppState.active_activity_plugin_id = "p1"
	AppState.active_activity_channel_id = "ch_1"
	AppState.active_activity_session_id = "sess_1"
	AppState.active_activity_session_state = "running"
	AppState.active_activity_role = "player"

	plugins._clear_active_activity()

	assert_eq(plugins._active_session_id, "")
	assert_eq(plugins._active_conn_index, -1)
	assert_false(plugins._is_host)
	assert_eq(plugins._host_user_id, "")
	assert_eq(plugins._session_participants, [])
	assert_eq(AppState.active_activity_plugin_id, "")
	assert_eq(AppState.active_activity_channel_id, "")
	assert_eq(AppState.active_activity_session_id, "")
	assert_eq(AppState.active_activity_session_state, "")
	assert_eq(AppState.active_activity_role, "")


func test_clear_active_activity_stops_runtime() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime

	plugins._clear_active_activity()

	assert_null(plugins._active_runtime)
	# MockRuntime is a Node, queue_free was called
	mock_runtime.free()


# ------------------------------------------------------------------
# get_activity_viewport_texture
# ------------------------------------------------------------------

func test_get_activity_viewport_texture_null_when_no_runtime() -> void:
	plugins._active_runtime = null
	assert_null(plugins.get_activity_viewport_texture())


func test_get_activity_viewport_texture_delegates_to_runtime() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime

	# MockRuntime.get_viewport_texture returns null, but the delegation works
	var result: ViewportTexture = plugins.get_activity_viewport_texture()
	assert_null(result)

	plugins._active_runtime = null
	mock_runtime.free()


# ------------------------------------------------------------------
# forward_activity_input
# ------------------------------------------------------------------

func test_forward_activity_input_noop_when_no_runtime() -> void:
	plugins._active_runtime = null
	# Should not crash
	var event := InputEventKey.new()
	plugins.forward_activity_input(event)


func test_forward_activity_input_delegates_to_runtime() -> void:
	var mock_runtime := _MockRuntime.new()
	plugins._active_runtime = mock_runtime

	var event := InputEventKey.new()
	plugins.forward_activity_input(event)

	assert_eq(mock_runtime.received.size(), 1)
	assert_eq(mock_runtime.received[0]["type"], "input")

	plugins._active_runtime = null
	mock_runtime.free()


# ------------------------------------------------------------------
# is_activity_host / get_session_participants
# ------------------------------------------------------------------

func test_is_activity_host_false_by_default() -> void:
	assert_false(plugins.is_activity_host())


func test_is_activity_host_true_when_set() -> void:
	plugins._is_host = true
	assert_true(plugins.is_activity_host())
	plugins._is_host = false


func test_get_session_participants_returns_list() -> void:
	plugins._session_participants = [
		{"user_id": "u1", "role": "player"},
		{"user_id": "u2", "role": "spectator"},
	]
	var result: Array = plugins.get_session_participants()
	assert_eq(result.size(), 2)
	assert_eq(result[0]["user_id"], "u1")
	plugins._session_participants = []


# ------------------------------------------------------------------
# Early-return guards (no active session)
# ------------------------------------------------------------------

func test_stop_activity_noop_when_no_session() -> void:
	plugins._active_session_id = ""
	# Should return early without error
	plugins.stop_activity("p1")


func test_start_session_noop_when_no_session() -> void:
	plugins._active_session_id = ""
	plugins.start_session()


func test_assign_role_noop_when_no_session() -> void:
	plugins._active_session_id = ""
	plugins.assign_role("user_1", "spectator")


func test_send_action_noop_when_no_session() -> void:
	plugins._active_session_id = ""
	plugins.send_action("p1", {"move": "a1"})
