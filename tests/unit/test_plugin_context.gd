extends GutTest

## Unit tests for PluginContext — get_role, is_host, send_file framing —
## and NativeRuntime._handle_file_data parsing. Verifies that the binary
## framing format is consistent between sender and receiver.


# ------------------------------------------------------------------
# PluginContext.get_role
# ------------------------------------------------------------------

func test_get_role_found() -> void:
	var ctx := PluginContext.new()
	ctx.participants = [
		{"user_id": "u1", "role": "player"},
		{"user_id": "u2", "role": "spectator"},
	]
	assert_eq(ctx.get_role("u2"), "spectator")


func test_get_role_not_found() -> void:
	var ctx := PluginContext.new()
	ctx.participants = [{"user_id": "u1", "role": "player"}]
	assert_eq(ctx.get_role("unknown"), "")


func test_get_role_empty_participants() -> void:
	var ctx := PluginContext.new()
	assert_eq(ctx.get_role("anyone"), "")


# ------------------------------------------------------------------
# PluginContext.is_host
# ------------------------------------------------------------------

func test_is_host_true() -> void:
	var ctx := PluginContext.new()
	ctx.local_user_id = "u1"
	ctx.host_user_id = "u1"
	assert_true(ctx.is_host())


func test_is_host_false() -> void:
	var ctx := PluginContext.new()
	ctx.local_user_id = "u1"
	ctx.host_user_id = "u2"
	assert_false(ctx.is_host())


# ------------------------------------------------------------------
# PluginContext.get_participants
# ------------------------------------------------------------------

func test_get_participants_returns_copy() -> void:
	var ctx := PluginContext.new()
	ctx.participants = [{"user_id": "u1", "role": "player"}]
	var copy: Array = ctx.get_participants()
	copy.clear()
	# Original should be unaffected
	assert_eq(ctx.participants.size(), 1)


# ------------------------------------------------------------------
# send_file framing ↔ _handle_file_data roundtrip
# ------------------------------------------------------------------

func test_file_framing_roundtrip() -> void:
	# Build the payload the same way PluginContext.send_file does
	var filename := "test_file.txt"
	var file_data := "Hello, world!".to_utf8_buffer()
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + file_data

	# Parse it the same way NativeRuntime._handle_file_data does
	assert_true(payload.size() >= 4)
	var name_len: int = payload.decode_u32(0)
	assert_eq(name_len, name_bytes.size())
	assert_true(payload.size() >= 4 + name_len)
	var parsed_name: String = payload.slice(4, 4 + name_len).get_string_from_utf8()
	var parsed_data: PackedByteArray = payload.slice(4 + name_len)
	assert_eq(parsed_name, filename)
	assert_eq(parsed_data, file_data)


func test_file_framing_empty_filename() -> void:
	var filename := ""
	var file_data := "data".to_utf8_buffer()
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + file_data

	var name_len: int = payload.decode_u32(0)
	assert_eq(name_len, 0)
	var parsed_name: String = payload.slice(4, 4 + name_len).get_string_from_utf8()
	var parsed_data: PackedByteArray = payload.slice(4 + name_len)
	assert_eq(parsed_name, "")
	assert_eq(parsed_data, file_data)


func test_file_framing_empty_data() -> void:
	var filename := "empty.bin"
	var file_data := PackedByteArray()
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + file_data

	var name_len: int = payload.decode_u32(0)
	var parsed_name: String = payload.slice(4, 4 + name_len).get_string_from_utf8()
	var parsed_data: PackedByteArray = payload.slice(4 + name_len)
	assert_eq(parsed_name, filename)
	assert_eq(parsed_data.size(), 0)


func test_file_framing_unicode_filename() -> void:
	var filename := "données_日本語.txt"
	var file_data := "content".to_utf8_buffer()
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + file_data

	var name_len: int = payload.decode_u32(0)
	var parsed_name: String = payload.slice(4, 4 + name_len).get_string_from_utf8()
	assert_eq(parsed_name, filename)


# ------------------------------------------------------------------
# NativeRuntime._handle_file_data edge cases
# ------------------------------------------------------------------

func test_handle_file_data_too_short_ignored() -> void:
	# Payload under 4 bytes should be silently ignored
	var runtime := NativeRuntime.new()
	var ctx := PluginContext.new()
	runtime._context = ctx
	runtime._running = true

	var received_files: Array = []
	ctx.file_received.connect(
		func(s: String, f: String, d: PackedByteArray):
			received_files.append(f)
	)

	# Only 3 bytes — shorter than the 4-byte header
	runtime._handle_file_data("sender", PackedByteArray([1, 2, 3]))
	assert_eq(received_files.size(), 0)

	runtime.free()


func test_handle_file_data_truncated_name_ignored() -> void:
	var runtime := NativeRuntime.new()
	var ctx := PluginContext.new()
	runtime._context = ctx
	runtime._running = true

	var received_files: Array = []
	ctx.file_received.connect(
		func(s: String, f: String, d: PackedByteArray):
			received_files.append(f)
	)

	# Header says name is 100 bytes, but payload is only 8 bytes total
	var payload := PackedByteArray()
	payload.resize(8)
	payload.encode_u32(0, 100)
	runtime._handle_file_data("sender", payload)
	assert_eq(received_files.size(), 0)

	runtime.free()


func test_handle_file_data_valid_emits_signal() -> void:
	var runtime := NativeRuntime.new()
	var ctx := PluginContext.new()
	runtime._context = ctx
	runtime._running = true

	var received: Array = []
	ctx.file_received.connect(
		func(sender_id: String, fname: String, data: PackedByteArray):
			received.append({"sender": sender_id, "name": fname, "data": data})
	)

	var filename := "test.bin"
	var file_data := PackedByteArray([0xDE, 0xAD, 0xBE, 0xEF])
	var name_bytes: PackedByteArray = filename.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + file_data

	runtime._handle_file_data("sender_1", payload)
	assert_eq(received.size(), 1)
	assert_eq(received[0]["sender"], "sender_1")
	assert_eq(received[0]["name"], "test.bin")
	assert_eq(received[0]["data"], file_data)

	runtime.free()


func test_handle_file_data_null_context_ignored() -> void:
	var runtime := NativeRuntime.new()
	runtime._context = null
	runtime._running = true
	# Should not crash
	var payload := PackedByteArray()
	payload.resize(8)
	payload.encode_u32(0, 0)
	runtime._handle_file_data("sender", payload)
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime.on_data_received routing
# ------------------------------------------------------------------

func test_on_data_received_routes_non_file_to_context() -> void:
	var runtime := NativeRuntime.new()
	var ctx := PluginContext.new()
	runtime._context = ctx
	runtime._running = true

	var received: Array = []
	ctx.data_received.connect(
		func(sender_id: String, topic: String, data: PackedByteArray):
			received.append({"sender": sender_id, "topic": topic})
	)

	var payload := "hello".to_utf8_buffer()
	runtime.on_data_received("u1", "game:state", payload)
	assert_eq(received.size(), 1)
	assert_eq(received[0]["topic"], "game:state")

	runtime.free()


func test_on_data_received_routes_file_to_handler() -> void:
	var runtime := NativeRuntime.new()
	var ctx := PluginContext.new()
	runtime._context = ctx
	runtime._running = true

	var data_received: Array = []
	var files_received: Array = []
	ctx.data_received.connect(
		func(s: String, t: String, d: PackedByteArray):
			data_received.append(t)
	)
	ctx.file_received.connect(
		func(s: String, f: String, d: PackedByteArray):
			files_received.append(f)
	)

	# Build a valid file payload
	var fname := "pic.png"
	var name_bytes: PackedByteArray = fname.to_utf8_buffer()
	var header := PackedByteArray()
	header.resize(4)
	header.encode_u32(0, name_bytes.size())
	var payload: PackedByteArray = header + name_bytes + PackedByteArray([1, 2])

	runtime.on_data_received("u1", "file:pic.png", payload)
	# Should go to file handler, not data handler
	assert_eq(data_received.size(), 0)
	assert_eq(files_received.size(), 1)
	assert_eq(files_received[0], "pic.png")

	runtime.free()


func test_on_data_received_null_context_ignored() -> void:
	var runtime := NativeRuntime.new()
	runtime._context = null
	runtime._running = true
	# Should not crash
	runtime.on_data_received("u1", "test", PackedByteArray())
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime.stop — lifecycle cleanup
# ------------------------------------------------------------------

func test_native_stop_noop_when_not_running() -> void:
	var runtime := NativeRuntime.new()
	runtime._running = false
	# Should not crash
	runtime.stop()
	assert_false(runtime._running)
	runtime.free()


func test_native_stop_clears_state() -> void:
	var runtime := NativeRuntime.new()
	runtime._running = true
	runtime._context = PluginContext.new()
	# No scene instance — stop should still work
	runtime.stop()

	assert_false(runtime._running)
	assert_null(runtime._context)
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime.on_plugin_event — delegation
# ------------------------------------------------------------------

func test_native_on_plugin_event_noop_when_not_running() -> void:
	var runtime := NativeRuntime.new()
	runtime._running = false
	# Should not crash
	runtime.on_plugin_event("test", {"key": "value"})
	runtime.free()


func test_native_on_plugin_event_noop_when_no_scene() -> void:
	var runtime := NativeRuntime.new()
	runtime._running = true
	runtime._scene_instance = null
	# Should not crash
	runtime.on_plugin_event("test", {})
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime.get_viewport_texture — no scene
# ------------------------------------------------------------------

func test_native_get_viewport_texture_null_when_no_scene() -> void:
	var runtime := NativeRuntime.new()
	assert_null(runtime.get_viewport_texture())
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime.forward_input — no scene
# ------------------------------------------------------------------

func test_native_forward_input_noop_when_no_scene() -> void:
	var runtime := NativeRuntime.new()
	runtime._scene_instance = null
	var event := InputEventKey.new()
	# Should not crash
	runtime.forward_input(event)
	runtime.free()


# ------------------------------------------------------------------
# NativeRuntime — initial state
# ------------------------------------------------------------------

func test_native_runtime_initial_state() -> void:
	var runtime := NativeRuntime.new()
	assert_false(runtime._running)
	assert_null(runtime._scene_instance)
	assert_null(runtime._context)
	runtime.free()


# ------------------------------------------------------------------
# PluginContext — send_action delegation
# ------------------------------------------------------------------

func test_context_send_action_noop_when_no_client_plugins() -> void:
	var ctx := PluginContext.new()
	ctx._client_plugins = null
	# Should not crash
	ctx.send_action({"move": "e4"})


# ------------------------------------------------------------------
# PluginContext — send_data noop when no adapter
# ------------------------------------------------------------------

func test_context_send_data_noop_when_no_adapter() -> void:
	var ctx := PluginContext.new()
	ctx._livekit_adapter = null
	# Should not crash
	ctx.send_data("topic", "data".to_utf8_buffer())


# ------------------------------------------------------------------
# PluginContext — session state defaults
# ------------------------------------------------------------------

func test_context_session_state_defaults() -> void:
	var ctx := PluginContext.new()
	assert_eq(ctx.plugin_id, "")
	assert_eq(ctx.session_id, "")
	assert_eq(ctx.conn_index, -1)
	assert_eq(ctx.local_user_id, "")
	assert_eq(ctx.session_state, "lobby")
	assert_eq(ctx.participants, [])
	assert_eq(ctx.host_user_id, "")
