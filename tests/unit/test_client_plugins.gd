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
