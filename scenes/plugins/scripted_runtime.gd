class_name ScriptedRuntime
extends Node

## Loads a Lua plugin into a sandboxed LuaState, renders into a SubViewport
## via PluginCanvas, and exposes a bridge API table that Lua code calls directly.

signal runtime_error(message: String)

const MAX_SOUNDS := 16

# Safe Lua libraries bitmask (no io, os, package, debug, ffi)
# LUA_BASE=1 | LUA_COROUTINE=4 | LUA_STRING=8 | LUA_MATH=32 | LUA_TABLE=64
const SAFE_LIBS := 1 | 4 | 8 | 32 | 64

# Session context (set by ClientPlugins before start)
var session_id: String = ""
var participants: Array = []
var local_user_id: String = ""
var local_role: String = "player"

var _viewport: SubViewport
var _canvas: PluginCanvas
var _lua: RefCounted  # LuaState (typed as RefCounted — GDExtension)
var _manifest: Dictionary = {}
var _plugin_id: String = ""
var _running: bool = false

# Cached Lua lifecycle functions
var _fn_ready = null   # LuaFunction
var _fn_draw = null    # LuaFunction
var _fn_input = null   # LuaFunction
var _fn_on_event = null # LuaFunction
var _fn_build_array = null  # LuaFunction — packs varargs into a 1-indexed table

# Timer tracking for set_interval / set_timeout
var _timers: Dictionary = {}  # id -> Timer
var _next_timer_id: int = 1

# Audio tracking
var _sounds: Dictionary = {}  # handle -> AudioStreamPlayer
var _next_sound_handle: int = 1

# Bundled assets (path -> PackedByteArray), set by ClientPlugins before start()
var _assets: Dictionary = {}

# Lua module sources (module_name -> source string), set by ClientPlugins before start()
var _modules: Dictionary = {}

# Reference to ClientPlugins for send_action
var _client_plugins = null  # ClientPlugins


func _ready() -> void:
	set_process(false)


## Starts the scripted runtime with the given Lua source and manifest.
func start(lua_source: String, manifest: Dictionary) -> bool:
	if _running:
		stop()

	_manifest = manifest
	_plugin_id = str(manifest.get("id", ""))

	var canvas_size: Array = manifest.get("canvas_size", [480, 360])
	var cw: int = clampi(
		int(canvas_size[0]) if canvas_size.size() >= 1 else 480,
		64, 1920,
	)
	var ch: int = clampi(
		int(canvas_size[1]) if canvas_size.size() >= 2 else 360,
		64, 1080,
	)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(cw, ch)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.transparent_bg = false
	add_child(_viewport)

	_canvas = PluginCanvas.new()
	_canvas.setup(cw, ch)
	_viewport.add_child(_canvas)

	if not ClassDB.class_exists(&"LuaState"):
		var msg := "lua-gdextension not available"
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	_lua = ClassDB.instantiate(&"LuaState")
	if _lua == null:
		var msg := "Failed to create LuaState instance"
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	# Open only safe libraries (no io, os, package, debug, ffi)
	_lua.open_libraries(SAFE_LIBS)

	# Build and inject the bridge API table
	_inject_bridge_api()

	# Load plugin source
	var result = _lua.do_string(lua_source, "plugin")
	if _is_lua_error(result):
		var msg := "Lua load error: %s" % str(result)
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	# Cache lifecycle functions
	_fn_ready = _lua.globals["_ready"]
	_fn_draw = _lua.globals["_draw"]
	_fn_input = _lua.globals["_input"]
	_fn_on_event = _lua.globals["_on_event"]

	# Call _ready
	_lua_call_safe(_fn_ready)

	_running = true
	set_process(true)
	return true


## Stops the runtime, frees all resources.
func stop() -> void:
	if not _running:
		return
	_running = false
	set_process(false)

	for timer_id in _timers:
		var t: Timer = _timers[timer_id]
		t.stop()
		t.queue_free()
	_timers.clear()

	for handle in _sounds:
		var player: AudioStreamPlayer = _sounds[handle]
		player.stop()
		player.queue_free()
	_sounds.clear()

	_cleanup()


## Forwards a plugin event from the gateway to sandboxed code.
func on_plugin_event(event_type: String, data: Dictionary) -> void:
	if not _running:
		return
	_lua_call_safe(_fn_on_event, [event_type, _dict_to_lua(data)])


## Returns the SubViewport's texture for display.
func get_viewport_texture() -> ViewportTexture:
	if _viewport != null:
		return _viewport.get_texture()
	return null


func _process(_delta: float) -> void:
	if not _running or _canvas == null:
		return
	_canvas.clear_commands()
	_lua_call_safe(_fn_draw)
	_canvas.flush()


## Forwards input events to the Lua code.
func forward_input(event: InputEvent) -> void:
	if not _running:
		return

	var d := {}
	if event is InputEventMouseButton:
		d = {
			"type": "mouse_button",
			"button_index": event.button_index,
			"pressed": event.pressed,
			"position_x": event.position.x,
			"position_y": event.position.y,
		}
	elif event is InputEventMouseMotion:
		d = {
			"type": "mouse_motion",
			"position_x": event.position.x,
			"position_y": event.position.y,
			"relative_x": event.relative.x,
			"relative_y": event.relative.y,
		}
	elif event is InputEventKey:
		d = {
			"type": "key",
			"keycode": event.keycode,
			"physical_keycode": event.physical_keycode,
			"unicode": event.unicode,
			"pressed": event.pressed,
			"echo": event.echo,
		}
	else:
		return

	_lua_call_safe(_fn_input, [_dict_to_lua(d)])


# --- Safe Lua function call wrapper ---

func _lua_call_safe(fn, args: Array = []) -> Variant:
	if fn == null:
		return null
	var result = fn.invokev(args)
	if _is_lua_error(result):
		var msg := "Lua runtime error: %s" % str(result)
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
	return result


## Converts a GDScript Dictionary to a native Lua table so plugins can index it.
func _dict_to_lua(d: Dictionary):
	var t = _lua.create_table()
	for key in d:
		var val = d[key]
		if val is Dictionary:
			t[key] = _dict_to_lua(val)
		elif val is Array:
			t[key] = _array_to_lua(val)
		else:
			t[key] = val
	return t


## Converts a GDScript Array to a native Lua table (1-indexed).
func _array_to_lua(arr: Array):
	var converted: Array = []
	for val in arr:
		if val is Dictionary:
			converted.append(_dict_to_lua(val))
		elif val is Array:
			converted.append(_array_to_lua(val))
		else:
			converted.append(val)
	return _fn_build_array.invokev(converted)


func _is_lua_error(value) -> bool:
	if value == null:
		return false
	if value is Object and ClassDB.class_exists(&"LuaError"):
		return value.is_class("LuaError")
	return false


# --- Bridge API injection ---

func _inject_bridge_api() -> void:
	var api = _lua.create_table()

	# Canvas info
	api["canvas_width"] = _canvas.canvas_width
	api["canvas_height"] = _canvas.canvas_height

	# Drawing
	api["clear"] = func(): _canvas.clear_commands()

	api["draw_rect"] = func(
		x: float, y: float, w: float, h: float, color, filled: bool,
	):
		_canvas.push_command({
			"type": "rect", "x": x, "y": y,
			"w": w, "h": h, "color": color, "filled": filled,
		})

	api["draw_circle"] = func(x: float, y: float, r: float, color):
		_canvas.push_command({
			"type": "circle", "x": x, "y": y, "r": r, "color": color,
		})

	api["draw_line"] = func(
		x1: float, y1: float, x2: float, y2: float, color, width: float,
	):
		_canvas.push_command({
			"type": "line",
			"x1": x1, "y1": y1, "x2": x2, "y2": y2,
			"color": color, "width": width,
		})

	api["draw_text"] = func(
		x: float, y: float, text: String, color, font_size: int,
	):
		_canvas.push_command({
			"type": "text", "x": x, "y": y,
			"text": text, "color": color, "font_size": font_size,
		})

	api["draw_pixel"] = func(x: float, y: float, color):
		_canvas.push_command({
			"type": "pixel", "x": x, "y": y, "color": color,
		})

	# Images
	api["load_image"] = func(data: PackedByteArray) -> int:
		return _canvas.load_image(data)

	api["draw_image"] = func(handle: int, x: float, y: float):
		_canvas.push_command({
			"type": "image", "handle": handle, "x": x, "y": y,
		})

	api["draw_image_region"] = func(
		handle: int, x: float, y: float,
		sx: float, sy: float, sw: float, sh: float,
	):
		_canvas.push_command({
			"type": "image_region", "handle": handle,
			"x": x, "y": y, "sx": sx, "sy": sy, "sw": sw, "sh": sh,
		})

	api["draw_image_scaled"] = func(
		handle: int, x: float, y: float, w: float, h: float,
	):
		_canvas.push_command({
			"type": "image_scaled", "handle": handle,
			"x": x, "y": y, "w": w, "h": h,
		})

	# Buffers
	api["create_buffer"] = func(w: int, h: int) -> int:
		return _canvas.create_buffer(w, h)

	api["set_buffer_pixel"] = func(handle: int, x: int, y: int, color):
		_canvas.set_buffer_pixel(handle, x, y, _canvas._parse_color(color))

	api["set_buffer_data"] = func(handle: int, data: PackedByteArray):
		_canvas.set_buffer_data(handle, data)

	api["draw_buffer"] = func(handle: int, x: float, y: float):
		_canvas.update_buffer_texture(handle)
		_canvas.push_command({
			"type": "buffer", "handle": handle, "x": x, "y": y,
		})

	api["draw_buffer_scaled"] = func(
		handle: int, x: float, y: float, w: float, h: float,
	):
		_canvas.update_buffer_texture(handle)
		_canvas.push_command({
			"type": "buffer_scaled", "handle": handle,
			"x": x, "y": y, "w": w, "h": h,
		})

	# State / networking
	api["send_action"] = func(data: Dictionary): _bridge_send_action(data)
	api["get_state"] = func() -> Dictionary: return _manifest
	api["get_participants"] = func() -> Array: return participants.duplicate()
	api["get_participant_count"] = func() -> int: return participants.size()
	api["get_participant"] = func(index: int) -> Dictionary:
		if index >= 0 and index < participants.size():
			return participants[index]
		return {}
	api["get_role"] = func() -> String: return local_role
	api["get_user_id"] = func() -> String: return local_user_id

	# Timers
	api["set_interval"] = func(callback_name: String, interval_ms: int) -> int:
		return _bridge_set_interval(callback_name, interval_ms)
	api["set_timeout"] = func(callback_name: String, delay_ms: int) -> int:
		return _bridge_set_timeout(callback_name, delay_ms)
	api["clear_timer"] = func(tid: int): _bridge_clear_timer(tid)

	# Assets
	api["read_asset"] = func(path: String) -> PackedByteArray:
		if _assets.has(path):
			return _assets[path]
		push_warning("[ScriptedRuntime] Asset not found: %s" % path)
		return PackedByteArray()

	# Audio
	api["load_sound"] = func(data: PackedByteArray) -> int:
		return _bridge_load_sound(data)
	api["play_sound"] = func(h: int): _bridge_play_sound(h)
	api["stop_sound"] = func(h: int): _bridge_stop_sound(h)

	# Helpers for constructing Godot Dictionaries/Arrays from Lua tables.
	api["_new_dict"] = func() -> Dictionary: return {}
	api["_new_array"] = func() -> Array: return []
	api["_dict_set"] = func(d: Dictionary, key: String, value) -> Dictionary:
		d[key] = value
		return d
	api["_array_append"] = func(a: Array, value) -> Array:
		a.append(value)
		return a

	_lua.globals["api"] = api

	# Module sources for require()
	api["_has_module"] = func(name: String) -> bool: return _modules.has(name)
	api["_get_module"] = func(name: String) -> String:
		return _modules.get(name, "")

	# Override Lua's built-in print(), provide Dictionary/Array constructors,
	# and implement a sandboxed require() that loads modules from the bundle.
	_lua.do_string("""
		local _api = api
		function print(...)
			local parts = {}
			for i = 1, select('#', ...) do
				parts[#parts + 1] = tostring(select(i, ...))
			end
			_api._gd_print(table.concat(parts, '\t'))
		end
		function Dictionary(t)
			local d = _api._new_dict()
			if t == nil then return d end
			for k, v in pairs(t) do
				if type(v) == "table" then
					d = _api._dict_set(d, tostring(k), Dictionary(v))
				else
					d = _api._dict_set(d, tostring(k), v)
				end
			end
			return d
		end
		function Array(t)
			local a = _api._new_array()
			if t == nil then return a end
			for i = 1, #t do
				local v = t[i]
				if type(v) == "table" then
					a = _api._array_append(a, Dictionary(v))
				else
					a = _api._array_append(a, v)
				end
			end
			return a
		end
		local _loaded = {}
		function require(name)
			if _loaded[name] ~= nil then
				return _loaded[name]
			end
			if not _api._has_module(name) then
				error("module '" .. name .. "' not found", 2)
			end
			local src = _api._get_module(name)
			local fn, err = load(src, name)
			if fn == nil then
				error("error loading module '" .. name .. "': " .. tostring(err), 2)
			end
			local result = fn()
			if result == nil then result = true end
			_loaded[name] = result
			return result
		end
	""", "print_override")
	api["_gd_print"] = func(msg: String):
		print("[%s] %s" % [_plugin_id, msg])

	# Helper for _array_to_lua: packs varargs into a 1-indexed Lua table
	_lua.do_string(
		"function _gd_build_array(...) return {...} end", "_gd_build_array"
	)
	_fn_build_array = _lua.globals["_gd_build_array"]


# --- Bridge send action ---

func _bridge_send_action(data: Dictionary) -> void:
	if _client_plugins != null and _client_plugins.has_method("send_action"):
		_client_plugins.send_action(_plugin_id, data)


# --- Timer/Sound implementations ---

func _bridge_set_interval(callback_name: String, interval_ms: int) -> int:
	var t := Timer.new()
	t.wait_time = maxf(float(interval_ms) / 1000.0, 0.016)
	t.one_shot = false
	var tid: int = _next_timer_id
	_next_timer_id = _next_timer_id + 1
	t.timeout.connect(func():
		var fn = _lua.globals[callback_name]
		_lua_call_safe(fn)
	)
	add_child(t)
	t.start()
	_timers[tid] = t
	return tid


func _bridge_set_timeout(callback_name: String, delay_ms: int) -> int:
	var t := Timer.new()
	t.wait_time = maxf(float(delay_ms) / 1000.0, 0.016)
	t.one_shot = true
	var tid: int = _next_timer_id
	_next_timer_id = _next_timer_id + 1
	t.timeout.connect(func():
		var fn = _lua.globals[callback_name]
		_lua_call_safe(fn)
		_timers.erase(tid)
		t.queue_free()
	)
	add_child(t)
	t.start()
	_timers[tid] = t
	return tid


func _bridge_clear_timer(timer_id: int) -> void:
	if _timers.has(timer_id):
		var t: Timer = _timers[timer_id]
		t.stop()
		t.queue_free()
		_timers.erase(timer_id)


func _bridge_load_sound(data: PackedByteArray) -> int:
	if _sounds.size() >= MAX_SOUNDS:
		push_warning("[ScriptedRuntime] Sound limit (%d)" % MAX_SOUNDS)
		return -1
	var stream: AudioStream = AudioStreamOggVorbis.load_from_buffer(data)
	if stream == null:
		push_warning("[ScriptedRuntime] Failed to load sound")
		return -1
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	var handle: int = _next_sound_handle
	_next_sound_handle = _next_sound_handle + 1
	_sounds[handle] = player
	return handle


func _bridge_play_sound(handle: int) -> void:
	var player: AudioStreamPlayer = _sounds.get(handle)
	if player != null:
		player.play()


func _bridge_stop_sound(handle: int) -> void:
	var player: AudioStreamPlayer = _sounds.get(handle)
	if player != null:
		player.stop()


# --- Cleanup ---

func _cleanup() -> void:
	_fn_ready = null
	_fn_draw = null
	_fn_input = null
	_fn_on_event = null
	_fn_build_array = null
	_lua = null
	if _canvas != null:
		_canvas.free_resources()
		_canvas = null
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
