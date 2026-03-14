class_name ScriptedRuntime
extends Node

## Loads a scripted plugin's ELF binary into a godot-sandbox Sandbox
## node, renders into a SubViewport via PluginCanvas, and exposes a
## Plugin.* bridge API that the sandboxed code can call.

signal runtime_error(message: String)

# Sandbox memory/execution limits
const MAX_MEMORY := 16 * 1024 * 1024  # 16 MB
const EXECUTION_TIMEOUT := 8000        # ms per vmcall
const MAX_SOUNDS := 16

# Session context (set by ClientPlugins before start)
var session_id: String = ""
var participants: Array = []
var local_user_id: String = ""
var local_role: String = "player"

var _viewport: SubViewport
var _canvas: PluginCanvas
var _sandbox: Node  # Sandbox (typed as Node — GDExtension)
var _manifest: Dictionary = {}
var _plugin_id: String = ""
var _running: bool = false

# Timer tracking for set_interval / set_timeout
var _timers: Dictionary = {}  # id -> Timer
var _next_timer_id: int = 1

# Audio tracking
var _sounds: Dictionary = {}  # handle -> AudioStreamPlayer
var _next_sound_handle: int = 1

# Reference to ClientPlugins for send_action
var _client_plugins = null  # ClientPlugins


func _ready() -> void:
	set_process(false)


## Starts the scripted runtime with the given ELF binary and manifest.
func start(
	elf_data: PackedByteArray, manifest: Dictionary,
) -> bool:
	if _running:
		stop()

	_manifest = manifest
	_plugin_id = str(manifest.get("id", ""))

	var canvas_size: Array = manifest.get(
		"canvas_size", [480, 360]
	)
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
	_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS
	)
	_viewport.transparent_bg = false
	add_child(_viewport)

	_canvas = PluginCanvas.new()
	_canvas.setup(cw, ch)
	_viewport.add_child(_canvas)

	if not ClassDB.class_exists(&"Sandbox"):
		var msg := "godot-sandbox GDExtension not available"
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	_sandbox = ClassDB.instantiate(&"Sandbox")
	if _sandbox == null:
		var msg := "Failed to create Sandbox instance"
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	add_child(_sandbox)

	if "max_memory" in _sandbox:
		_sandbox.max_memory = MAX_MEMORY
	if "execution_timeout" in _sandbox:
		_sandbox.execution_timeout = EXECUTION_TIMEOUT

	if _sandbox.has_method("load_buffer"):
		_sandbox.load_buffer(elf_data)
	else:
		var msg := "Sandbox missing load_buffer()"
		push_error("[ScriptedRuntime] " + msg)
		runtime_error.emit(msg)
		_cleanup()
		return false

	_register_bridge_api()
	_vmcall_safe("_ready")

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
func on_plugin_event(
	event_type: String, data: Dictionary,
) -> void:
	if not _running:
		return
	_vmcall_safe("_on_event", event_type, data)


## Returns the SubViewport's texture for display.
func get_viewport_texture() -> ViewportTexture:
	if _viewport != null:
		return _viewport.get_texture()
	return null


func _process(_delta: float) -> void:
	if not _running or _canvas == null:
		return
	_canvas.clear_commands()
	_vmcall_safe("_draw")
	_canvas.flush()


## Forwards input events to the sandboxed code.
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

	_vmcall_safe("_input", d)


# --- Bridge API registration ---

func _register_bridge_api() -> void:
	# Only push the API dict if the guest ELF exposes _set_api in its
	# public API.  Older / minimal plugins may not define it.
	if _sandbox != null and _sandbox.has_method("has_function") \
			and not _sandbox.has_function("_set_api"):
		push_warning(
			"[ScriptedRuntime] ELF has no _set_api — bridge API "
			+ "not injected. Plugin may have limited functionality."
		)
		return
	var api := _build_bridge_api()
	_vmcall_safe("_set_api", api)


func _build_bridge_api() -> Dictionary:
	return {
		# Canvas info
		"canvas_width": func() -> int:
			return _canvas.canvas_width,
		"canvas_height": func() -> int:
			return _canvas.canvas_height,

		# Drawing
		"clear": func() -> void:
			_canvas.clear_commands(),
		"draw_rect": _bridge_draw_rect,
		"draw_circle": _bridge_draw_circle,
		"draw_line": _bridge_draw_line,
		"draw_text": _bridge_draw_text,
		"draw_pixel": _bridge_draw_pixel,

		# Images
		"load_image": func(data: PackedByteArray) -> int:
			return _canvas.load_image(data),
		"draw_image": _bridge_draw_image,
		"draw_image_region": _bridge_draw_image_region,
		"draw_image_scaled": _bridge_draw_image_scaled,

		# Buffers
		"create_buffer": func(w: int, h: int) -> int:
			return _canvas.create_buffer(w, h),
		"set_buffer_pixel": _bridge_set_buffer_pixel,
		"set_buffer_data": _bridge_set_buffer_data,
		"draw_buffer": _bridge_draw_buffer,
		"draw_buffer_scaled": _bridge_draw_buffer_scaled,

		# State / networking
		"send_action": func(data: Dictionary) -> void:
			_bridge_send_action(data),
		"get_state": func() -> Dictionary:
			return _manifest,
		"get_participants": func() -> Array:
			return participants.duplicate(),
		"get_role": func() -> String:
			return local_role,
		"get_user_id": func() -> String:
			return local_user_id,

		# Timers
		"set_interval": _bridge_set_interval,
		"set_timeout": _bridge_set_timeout,
		"clear_timer": func(tid: int) -> void:
			_bridge_clear_timer(tid),

		# Audio
		"load_sound": func(data: PackedByteArray) -> int:
			return _bridge_load_sound(data),
		"play_sound": func(h: int) -> void:
			_bridge_play_sound(h),
		"stop_sound": func(h: int) -> void:
			_bridge_stop_sound(h),
	}


# --- Bridge draw helpers ---

func _bridge_draw_rect(
	x: float, y: float, w: float, h: float,
	color, filled: bool,
) -> void:
	_canvas.push_command({
		"type": "rect", "x": x, "y": y,
		"w": w, "h": h, "color": color, "filled": filled,
	})

func _bridge_draw_circle(
	x: float, y: float, r: float, color,
) -> void:
	_canvas.push_command({
		"type": "circle", "x": x, "y": y,
		"r": r, "color": color,
	})

func _bridge_draw_line(
	x1: float, y1: float, x2: float, y2: float,
	color, width: float,
) -> void:
	_canvas.push_command({
		"type": "line",
		"x1": x1, "y1": y1, "x2": x2, "y2": y2,
		"color": color, "width": width,
	})

func _bridge_draw_text(
	x: float, y: float, text: String,
	color, font_size: int,
) -> void:
	_canvas.push_command({
		"type": "text", "x": x, "y": y,
		"text": text, "color": color,
		"font_size": font_size,
	})

func _bridge_draw_pixel(
	x: float, y: float, color,
) -> void:
	_canvas.push_command({
		"type": "pixel", "x": x, "y": y, "color": color,
	})

func _bridge_draw_image(
	handle: int, x: float, y: float,
) -> void:
	_canvas.push_command({
		"type": "image", "handle": handle,
		"x": x, "y": y,
	})

func _bridge_draw_image_region(
	handle: int, x: float, y: float,
	sx: float, sy: float, sw: float, sh: float,
) -> void:
	_canvas.push_command({
		"type": "image_region", "handle": handle,
		"x": x, "y": y, "sx": sx, "sy": sy,
		"sw": sw, "sh": sh,
	})

func _bridge_draw_image_scaled(
	handle: int, x: float, y: float,
	w: float, h: float,
) -> void:
	_canvas.push_command({
		"type": "image_scaled", "handle": handle,
		"x": x, "y": y, "w": w, "h": h,
	})

func _bridge_set_buffer_pixel(
	handle: int, x: int, y: int, color,
) -> void:
	_canvas.set_buffer_pixel(
		handle, x, y, _canvas._parse_color(color),
	)

func _bridge_set_buffer_data(
	handle: int, data: PackedByteArray,
) -> void:
	_canvas.set_buffer_data(handle, data)

func _bridge_draw_buffer(
	handle: int, x: float, y: float,
) -> void:
	_canvas.update_buffer_texture(handle)
	_canvas.push_command({
		"type": "buffer", "handle": handle,
		"x": x, "y": y,
	})

func _bridge_draw_buffer_scaled(
	handle: int, x: float, y: float,
	w: float, h: float,
) -> void:
	_canvas.update_buffer_texture(handle)
	_canvas.push_command({
		"type": "buffer_scaled", "handle": handle,
		"x": x, "y": y, "w": w, "h": h,
	})


# --- Bridge implementations ---

func _bridge_send_action(data: Dictionary) -> void:
	if _client_plugins != null \
			and _client_plugins.has_method("send_action"):
		_client_plugins.send_action(_plugin_id, data)


func _bridge_set_interval(
	callback_name: String, interval_ms: int,
) -> int:
	var t := Timer.new()
	t.wait_time = maxf(float(interval_ms) / 1000.0, 0.016)
	t.one_shot = false
	var tid: int = _next_timer_id
	_next_timer_id += 1
	t.timeout.connect(func(): _vmcall_safe(callback_name))
	add_child(t)
	t.start()
	_timers[tid] = t
	return tid


func _bridge_set_timeout(
	callback_name: String, delay_ms: int,
) -> int:
	var t := Timer.new()
	t.wait_time = maxf(float(delay_ms) / 1000.0, 0.016)
	t.one_shot = true
	var tid: int = _next_timer_id
	_next_timer_id += 1
	t.timeout.connect(func():
		_vmcall_safe(callback_name)
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
		push_warning(
			"[ScriptedRuntime] Sound limit (%d)" % MAX_SOUNDS
		)
		return -1
	var stream: AudioStream = null
	# Try OGG Vorbis first (most common for plugins)
	stream = AudioStreamOggVorbis.load_from_buffer(data)
	if stream == null:
		push_warning("[ScriptedRuntime] Failed to load sound")
		return -1
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	var handle: int = _next_sound_handle
	_next_sound_handle += 1
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


# --- Safe vmcall wrapper ---

func _vmcall_safe(
	fn: String,
	arg1 = null, arg2 = null, arg3 = null,
) -> Variant:
	if _sandbox == null or not _sandbox.has_method("vmcall"):
		return null
	if arg3 != null:
		return _sandbox.vmcall(fn, arg1, arg2, arg3)
	if arg2 != null:
		return _sandbox.vmcall(fn, arg1, arg2)
	if arg1 != null:
		return _sandbox.vmcall(fn, arg1)
	return _sandbox.vmcall(fn)


# --- Cleanup ---

func _cleanup() -> void:
	if _sandbox != null:
		_sandbox.queue_free()
		_sandbox = null
	if _canvas != null:
		_canvas.free_resources()
		_canvas = null
	if _viewport != null:
		_viewport.queue_free()
		_viewport = null
