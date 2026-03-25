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


# ------------------------------------------------------------------
# Bulk bridge constants
# ------------------------------------------------------------------

func test_max_action_payload_bytes_constant() -> void:
	assert_eq(ScriptedRuntime.MAX_ACTION_PAYLOAD_BYTES, 8192)


func test_max_collection_elements_constant() -> void:
	assert_eq(ScriptedRuntime.MAX_COLLECTION_ELEMENTS, 200)


# ------------------------------------------------------------------
# parse_flat_array — bulk Array conversion
# ------------------------------------------------------------------

func test_parse_flat_array_integers() -> void:
	var result := ScriptedRuntime.parse_flat_array("n0\u001en1\u001en2\u001en3")
	assert_eq(result, [0, 1, 2, 3])
	assert_typeof(result[0], TYPE_INT)


func test_parse_flat_array_floats() -> void:
	var result := ScriptedRuntime.parse_flat_array("n1.5\u001en2.7")
	assert_eq(result, [1.5, 2.7])
	assert_typeof(result[0], TYPE_FLOAT)


func test_parse_flat_array_booleans() -> void:
	var result := ScriptedRuntime.parse_flat_array("btrue\u001ebfalse")
	assert_eq(result, [true, false])
	assert_typeof(result[0], TYPE_BOOL)


func test_parse_flat_array_strings() -> void:
	var result := ScriptedRuntime.parse_flat_array("shello\u001esworld")
	assert_eq(result, ["hello", "world"])


func test_parse_flat_array_mixed_types() -> void:
	var result := ScriptedRuntime.parse_flat_array(
		"n42\u001en3.14\u001ebtrue\u001estext"
	)
	assert_eq(result.size(), 4)
	assert_eq(result[0], 42)
	assert_typeof(result[0], TYPE_INT)
	assert_eq(result[1], 3.14)
	assert_typeof(result[1], TYPE_FLOAT)
	assert_eq(result[2], true)
	assert_eq(result[3], "text")


func test_parse_flat_array_single_element() -> void:
	var result := ScriptedRuntime.parse_flat_array("n99")
	assert_eq(result, [99])


func test_parse_flat_array_string_that_looks_like_int() -> void:
	# Snowflake IDs must stay as strings, not become ints
	var result := ScriptedRuntime.parse_flat_array("s189012345678901234")
	assert_eq(result, ["189012345678901234"])
	assert_typeof(result[0], TYPE_STRING)


func test_parse_flat_array_board_serialization() -> void:
	# Simulates a 10x10 battleships board (100 cells, values 0-1)
	var cells := PackedStringArray()
	cells.resize(100)
	for i in 100:
		cells[i] = "n0"
	# Place some ships
	cells[0] = "n1"
	cells[1] = "n1"
	cells[2] = "n1"
	var packed := "\u001e".join(cells)
	var result := ScriptedRuntime.parse_flat_array(packed)
	assert_eq(result.size(), 100)
	assert_eq(result[0], 1)
	assert_eq(result[1], 1)
	assert_eq(result[2], 1)
	assert_eq(result[3], 0)
	assert_eq(result[99], 0)


# ------------------------------------------------------------------
# parse_flat_dict — bulk Dictionary conversion
# ------------------------------------------------------------------

func test_parse_flat_dict_simple() -> void:
	var result := ScriptedRuntime.parse_flat_dict(
		"action\u001fsfire\u001erow\u001fn3\u001ecol\u001fn7"
	)
	assert_eq(result["action"], "fire")
	assert_eq(result["row"], 3)
	assert_eq(result["col"], 7)


func test_parse_flat_dict_with_booleans() -> void:
	var result := ScriptedRuntime.parse_flat_dict(
		"ready\u001fbtrue\u001edone\u001fbfalse"
	)
	assert_eq(result["ready"], true)
	assert_eq(result["done"], false)


func test_parse_flat_dict_empty_string() -> void:
	var result := ScriptedRuntime.parse_flat_dict("")
	assert_eq(result, {})


func test_parse_flat_dict_single_pair() -> void:
	var result := ScriptedRuntime.parse_flat_dict("key\u001fsvalue")
	assert_eq(result, {"key": "value"})


func test_parse_flat_dict_preserves_string_user_id() -> void:
	# User IDs that look like numbers must stay as strings
	var result := ScriptedRuntime.parse_flat_dict(
		"action\u001fsjoin\u001euser_id\u001fs189012345678901234"
	)
	assert_eq(result["action"], "join")
	assert_typeof(result["action"], TYPE_STRING)
	assert_eq(result["user_id"], "189012345678901234")
	assert_typeof(result["user_id"], TYPE_STRING)


# ------------------------------------------------------------------
# _parse_typed_value — type-prefixed decoding
# ------------------------------------------------------------------

func test_parse_typed_value_negative_int() -> void:
	var result = ScriptedRuntime._parse_typed_value("n-5")
	assert_eq(result, -5)
	assert_typeof(result, TYPE_INT)


func test_parse_typed_value_zero() -> void:
	var result = ScriptedRuntime._parse_typed_value("n0")
	assert_eq(result, 0)
	assert_typeof(result, TYPE_INT)


func test_parse_typed_value_negative_float() -> void:
	var result = ScriptedRuntime._parse_typed_value("n-1.5")
	assert_eq(result, -1.5)
	assert_typeof(result, TYPE_FLOAT)


func test_parse_typed_value_plain_string() -> void:
	var result = ScriptedRuntime._parse_typed_value("shello")
	assert_eq(result, "hello")
	assert_typeof(result, TYPE_STRING)


func test_parse_typed_value_numeric_string_stays_string() -> void:
	var result = ScriptedRuntime._parse_typed_value("s12345")
	assert_eq(result, "12345")
	assert_typeof(result, TYPE_STRING)


# ------------------------------------------------------------------
# _bridge_send_action — payload size limit
# ------------------------------------------------------------------

func test_bridge_send_action_rejects_oversized_payload() -> void:
	runtime._client_plugins = null
	var big := {}
	# Build a payload that exceeds 8KB when serialized with var_to_bytes
	for i in 500:
		big["key_%d" % i] = "x".repeat(100)
	var captured := []
	runtime.runtime_error.connect(
		func(msg: String) -> void: captured.append(msg)
	)
	runtime._bridge_send_action(big)
	assert_eq(captured.size(), 1, "Should emit exactly one runtime_error")
	if captured.size() > 0:
		assert_string_contains(captured[0], "payload too large")
