extends GutTest

## Unit tests for ScriptedRuntime — pure-logic methods that don't require
## the lua-gdextension GDExtension to be present.

var runtime: ScriptedRuntime


func before_each() -> void:
	runtime = ScriptedRuntime.new()
	add_child(runtime)


func after_each() -> void:
	runtime.queue_free()
	runtime = null


# ------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------

func test_safe_libs_bitmask() -> void:
	# LUA_BASE=1 | LUA_COROUTINE=4 | LUA_STRING=8 | LUA_MATH=32 | LUA_TABLE=64
	assert_eq(ScriptedRuntime.SAFE_LIBS, 1 | 4 | 8 | 32 | 64)
	# Ensure dangerous libs are NOT included:
	# LUA_IO=2, LUA_OS=16, LUA_PACKAGE=128, LUA_DEBUG=256
	assert_eq(ScriptedRuntime.SAFE_LIBS & 2, 0, "io should be blocked")
	assert_eq(ScriptedRuntime.SAFE_LIBS & 16, 0, "os should be blocked")
	assert_eq(ScriptedRuntime.SAFE_LIBS & 128, 0, "package should be blocked")
	assert_eq(ScriptedRuntime.SAFE_LIBS & 256, 0, "debug should be blocked")


func test_max_sounds_constant() -> void:
	assert_eq(ScriptedRuntime.MAX_SOUNDS, 16)


# ------------------------------------------------------------------
# _is_lua_error — works without LuaState
# ------------------------------------------------------------------

func test_is_lua_error_null_returns_false() -> void:
	assert_false(runtime._is_lua_error(null))


func test_is_lua_error_string_returns_false() -> void:
	assert_false(runtime._is_lua_error("some error"))


func test_is_lua_error_int_returns_false() -> void:
	assert_false(runtime._is_lua_error(42))


func test_is_lua_error_dict_returns_false() -> void:
	assert_false(runtime._is_lua_error({"error": "msg"}))


func test_is_lua_error_node_returns_false() -> void:
	var n := Node.new()
	assert_false(runtime._is_lua_error(n))
	n.free()


# ------------------------------------------------------------------
# Initial state
# ------------------------------------------------------------------

func test_not_running_by_default() -> void:
	assert_false(runtime._running)


func test_process_disabled_by_default() -> void:
	# _ready() calls set_process(false)
	assert_false(runtime.is_processing())


# ------------------------------------------------------------------
# get_viewport_texture — null when no viewport
# ------------------------------------------------------------------

func test_get_viewport_texture_null_when_no_viewport() -> void:
	assert_null(runtime.get_viewport_texture())


# ------------------------------------------------------------------
# on_plugin_event — no-op when not running
# ------------------------------------------------------------------

func test_on_plugin_event_noop_when_not_running() -> void:
	runtime._running = false
	# Should not crash
	runtime.on_plugin_event("test_event", {"key": "value"})


# ------------------------------------------------------------------
# forward_input — no-op when not running
# ------------------------------------------------------------------

func test_forward_input_noop_when_not_running() -> void:
	runtime._running = false
	var event := InputEventKey.new()
	# Should not crash
	runtime.forward_input(event)


# ------------------------------------------------------------------
# _lua_call_safe — null function returns null
# ------------------------------------------------------------------

func test_lua_call_safe_null_fn_returns_null() -> void:
	assert_null(runtime._lua_call_safe(null))


func test_lua_call_safe_null_fn_with_args_returns_null() -> void:
	assert_null(runtime._lua_call_safe(null, ["arg1", "arg2"]))


# ------------------------------------------------------------------
# stop — safe when not running
# ------------------------------------------------------------------

func test_stop_noop_when_not_running() -> void:
	runtime._running = false
	# Should not crash
	runtime.stop()
	assert_false(runtime._running)


# ------------------------------------------------------------------
# _cleanup — nulls all references
# ------------------------------------------------------------------

func test_cleanup_nulls_references() -> void:
	runtime._fn_ready = "placeholder"
	runtime._fn_draw = "placeholder"
	runtime._fn_input = "placeholder"
	runtime._fn_on_event = "placeholder"
	runtime._fn_build_array = "placeholder"

	runtime._cleanup()

	assert_null(runtime._fn_ready)
	assert_null(runtime._fn_draw)
	assert_null(runtime._fn_input)
	assert_null(runtime._fn_on_event)
	assert_null(runtime._fn_build_array)
	assert_null(runtime._lua)


# ------------------------------------------------------------------
# Session context defaults
# ------------------------------------------------------------------

func test_session_context_defaults() -> void:
	assert_eq(runtime.session_id, "")
	assert_eq(runtime.participants, [])
	assert_eq(runtime.local_user_id, "")
	assert_eq(runtime.local_role, "player")


# ------------------------------------------------------------------
# _bridge_send_action — delegation
# ------------------------------------------------------------------

func test_bridge_send_action_noop_when_no_client_plugins() -> void:
	runtime._client_plugins = null
	# Should not crash
	runtime._bridge_send_action({"move": "e4"})


# ------------------------------------------------------------------
# _bridge_clear_timer — no-op for unknown ID
# ------------------------------------------------------------------

func test_bridge_clear_timer_noop_for_unknown() -> void:
	# Should not crash
	runtime._bridge_clear_timer(999)
	assert_false(runtime._timers.has(999))


# ------------------------------------------------------------------
# _bridge_play_sound / _bridge_stop_sound — no-op for unknown handle
# ------------------------------------------------------------------

func test_bridge_play_sound_noop_for_unknown() -> void:
	# Should not crash
	runtime._bridge_play_sound(999)


func test_bridge_stop_sound_noop_for_unknown() -> void:
	# Should not crash
	runtime._bridge_stop_sound(999)
