class_name ClientPlugins
extends RefCounted

## Manages plugin state: caching manifests, launching/stopping activities,
## and handling gateway events for plugins.

var _c: Node # Client autoload

# Per-connection plugin cache: conn_index -> { plugin_id -> manifest dict }
var _plugin_cache: Dictionary = {}

# Active activity state
var _active_runtime: Node = null
var _active_session_id: String = ""
var _active_conn_index: int = -1

var _scripted_runtime_class = null  # loaded on demand
var _native_runtime_class = null   # loaded on demand
var _download_manager: PluginDownloadManager = null


func _init(client_node: Node) -> void:
	_c = client_node
	_download_manager = PluginDownloadManager.new(client_node)
	AppState.voice_left.connect(_on_voice_left)


## Fetches installed plugins for a space and caches them.
func fetch_plugins(conn_index: int, space_id: String) -> void:
	if conn_index < 0 or conn_index >= _c._connections.size():
		return
	var conn: Dictionary = _c._connections[conn_index]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.plugins.list_plugins(space_id)
	if result.ok and result.data is Array:
		var cache: Dictionary = {}
		for p in result.data:
			if p is AccordPluginManifest:
				cache[p.id] = p.to_dict()
		_plugin_cache[conn_index] = cache
		AppState.plugins_updated.emit()


## Returns cached plugin manifests for a connection as an Array of Dictionaries.
func get_plugins(conn_index: int) -> Array:
	var cache: Dictionary = _plugin_cache.get(conn_index, {})
	return cache.values()


## Returns a single plugin manifest dict by ID (searches all connections).
func get_plugin(plugin_id: String) -> Dictionary:
	for conn_idx in _plugin_cache:
		var cache: Dictionary = _plugin_cache[conn_idx]
		if cache.has(plugin_id):
			return cache[plugin_id]
	return {}


## Returns the connection index that owns a plugin, or -1 if not found.
func get_conn_index_for_plugin(plugin_id: String) -> int:
	for conn_idx in _plugin_cache:
		if _plugin_cache[conn_idx].has(plugin_id):
			return conn_idx
	return -1


## Launches an activity: creates a session on the server, downloads the Lua
## source (for scripted plugins), starts the runtime, and updates AppState.
func launch_activity(plugin_id: String, channel_id: String) -> Dictionary:
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		push_error("[ClientPlugins] Plugin not found: ", plugin_id)
		return {"error": "Plugin not found"}
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return {"error": "Not connected"}
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.plugins.create_session(
		plugin_id, channel_id
	)
	if not result.ok:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[ClientPlugins] Failed to create session: ", err)
		return {"error": err}
	var session: Dictionary = result.data
	var session_id: String = str(session.get("id", ""))
	var state: String = session.get("state", "lobby")

	_active_session_id = session_id
	_active_conn_index = conn_idx
	AppState.active_activity_plugin_id = plugin_id
	AppState.active_activity_channel_id = channel_id
	AppState.active_activity_session_id = session_id
	AppState.active_activity_session_state = state
	AppState.active_activity_role = "player"
	AppState.activity_started.emit(plugin_id, channel_id)

	# Prepare the appropriate runtime based on plugin type.
	var manifest: Dictionary = get_plugin(plugin_id)
	var session_participants: Array = session.get("participants", [])
	var runtime_type: String = manifest.get("runtime", "")
	if runtime_type == "scripted":
		await _download_and_prepare_scripted_runtime(
			plugin_id, manifest, conn_idx, session_participants,
		)
	elif runtime_type == "native":
		await _download_and_prepare_native_runtime(
			plugin_id, manifest, conn_idx, session_participants,
		)

	return session


## Downloads the plugin bundle ZIP and creates a ScriptedRuntime.
func _download_and_prepare_scripted_runtime(
	plugin_id: String, manifest: Dictionary, conn_idx: int,
	session_participants: Array = [],
) -> void:
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]

	AppState.activity_download_progress.emit(plugin_id, 0.0)
	var src_result: RestResult = await client.plugins.get_source(plugin_id)
	AppState.activity_download_progress.emit(plugin_id, 1.0)

	if not src_result.ok or not (src_result.data is PackedByteArray):
		var err: String = "Failed to download plugin bundle"
		if src_result.error:
			err = src_result.error.message
		push_error("[ClientPlugins] ", err)
		return

	var zip_bytes: PackedByteArray = src_result.data
	if zip_bytes.is_empty():
		push_error("[ClientPlugins] Plugin bundle is empty")
		return

	# Extract entry source, modules, and assets from the bundle ZIP
	var bundle: Dictionary = _extract_bundle(zip_bytes, manifest)
	if bundle.is_empty():
		push_error("[ClientPlugins] Failed to extract plugin bundle")
		return

	if _scripted_runtime_class == null:
		_scripted_runtime_class = load(
			"res://scripts/plugins/scripted_runtime.gd"
		)
	var runtime: Node = _scripted_runtime_class.new()
	runtime.session_id = _active_session_id
	runtime.local_user_id = _c.current_user.get("id", "")
	runtime.local_role = AppState.active_activity_role
	runtime.participants = session_participants
	runtime._client_plugins = self
	runtime._modules = bundle.get("modules", {})
	runtime._assets = bundle.get("assets", {})
	_c.add_child(runtime)

	var ok: bool = runtime.start(bundle["lua_source"], manifest)
	if not ok:
		push_error("[ClientPlugins] ScriptedRuntime failed to start")
		runtime.queue_free()
		return

	_active_runtime = runtime


## Extracts entry Lua source, modules, and assets from a plugin bundle ZIP.
## Returns { "lua_source": String, "modules": Dictionary, "assets": Dictionary }
## or an empty Dictionary on failure.
func _extract_bundle(
	zip_bytes: PackedByteArray, manifest: Dictionary,
) -> Dictionary:
	var tmp_path: String = "user://tmp_plugin_bundle.zip"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_buffer(zip_bytes)
	f.close()

	var reader := ZIPReader.new()
	var err: Error = reader.open(tmp_path)
	if err != OK:
		DirAccess.remove_absolute(tmp_path)
		return {}

	var entry: String = str(manifest.get("entry_point", ""))
	if entry.is_empty():
		entry = str(manifest.get("entry", "src/main.lua"))

	var files: PackedStringArray = reader.get_files()

	# Read entry file
	var entry_bytes: PackedByteArray = reader.read_file(entry)
	if entry_bytes.is_empty():
		reader.close()
		DirAccess.remove_absolute(tmp_path)
		push_error("[ClientPlugins] Entry file not found in bundle: ", entry)
		return {}

	var lua_source: String = entry_bytes.get_string_from_utf8()
	var modules: Dictionary = {}
	var assets: Dictionary = {}

	for file_path in files:
		if file_path.ends_with(".lua") and file_path != entry:
			var module_name: String = file_path.get_file().get_basename()
			var src: PackedByteArray = reader.read_file(file_path)
			modules[module_name] = src.get_string_from_utf8()
		elif file_path.begins_with("assets/") and not file_path.ends_with("/"):
			assets[file_path] = reader.read_file(file_path)

	reader.close()
	DirAccess.remove_absolute(tmp_path)

	return {"lua_source": lua_source, "modules": modules, "assets": assets}


## Downloads the native plugin bundle, extracts it, creates a NativeRuntime,
## and wires up data channel routing via LiveKitAdapter.
func _download_and_prepare_native_runtime(
	plugin_id: String, manifest: Dictionary, conn_idx: int,
	session_participants: Array = [],
) -> void:
	var bundle_dir: String = await _download_manager.download_bundle(
		conn_idx, plugin_id, manifest,
	)
	if bundle_dir.is_empty():
		push_error("[ClientPlugins] Failed to download native plugin bundle")
		return

	# Check trust before executing native code
	var is_signed: bool = manifest.get("signed", false)
	if not is_signed:
		var server_id: String = _download_manager._server_id_for_conn(
			_c._connections[conn_idx]
		)
		if not _is_plugin_trusted(server_id, plugin_id):
			var trusted: bool = await _show_trust_dialog(
				manifest.get("name", plugin_id), server_id, plugin_id,
			)
			if not trusted:
				push_warning("[ClientPlugins] User denied trust for: ", plugin_id)
				AppState.activity_download_progress.emit(plugin_id, -1.0)
				return

	if _native_runtime_class == null:
		_native_runtime_class = load("res://scripts/plugins/native_runtime.gd")

	var context := PluginContext.new()
	context.plugin_id = plugin_id
	context.session_id = _active_session_id
	context.conn_index = conn_idx
	context.local_user_id = _c.current_user.get("id", "")
	context.host_user_id = _c.current_user.get("id", "")
	context.session_state = AppState.active_activity_session_state
	context.participants = session_participants
	context._client_plugins = self
	# Wire LiveKit data channels if available
	if _c.has_node("LiveKitAdapter"):
		var adapter: Node = _c.get_node("LiveKitAdapter")
		context._livekit_adapter = adapter
		if not adapter.plugin_data_received.is_connected(_on_livekit_data_received):
			adapter.plugin_data_received.connect(_on_livekit_data_received)

	var runtime: Node = _native_runtime_class.new()
	_c.add_child(runtime)

	var entry_point: String = manifest.get("entry_point", "scenes/main.tscn")
	var ok: bool = runtime.start(bundle_dir, entry_point, context)
	if not ok:
		push_error("[ClientPlugins] NativeRuntime failed to start")
		runtime.queue_free()
		return

	_active_runtime = runtime


## Shows a trust confirmation dialog and waits for the user's response.
## Returns true if the user grants trust, false if denied.
func _show_trust_dialog(
	plugin_name: String, server_id: String, plugin_id: String,
) -> bool:
	var dialog_scene: PackedScene = load("res://scenes/plugins/plugin_trust_dialog.tscn")
	var dialog: ModalBase = dialog_scene.instantiate()
	dialog.setup(plugin_name, server_id)
	_c.get_tree().root.add_child(dialog)
	# Wait for user response
	var result: Array = await _await_trust_signal(dialog)
	var granted: bool = result[0]
	var remember: bool = result[1]
	if granted:
		if remember:
			Config.set_plugin_trust_all(server_id, true)
		else:
			Config.set_plugin_trust(server_id, plugin_id, true)
	return granted


func _await_trust_signal(dialog) -> Array:
	# Returns [granted: bool, remember: bool]
	var granted := false
	var remember := false
	var done := false
	dialog.trust_granted.connect(func(rem: bool):
		granted = true
		remember = rem
		done = true
	)
	dialog.trust_denied.connect(func():
		done = true
	)
	dialog.closed.connect(func():
		done = true
	)
	while not done:
		await _c.get_tree().process_frame
	return [granted, remember]


## Checks if a native plugin has been trusted for a given server.
func _is_plugin_trusted(server_id: String, plugin_id: String) -> bool:
	if Config.is_plugin_trust_all(server_id):
		return true
	return Config.get_plugin_trust(server_id, plugin_id)


## Handles incoming data from LiveKit data channels and routes to the
## active native runtime.
func _on_livekit_data_received(
	sender_id: String, topic: String, payload: PackedByteArray,
) -> void:
	if _active_runtime == null:
		return
	if not _active_runtime.has_method("on_data_received"):
		return
	# Strip the "plugin:<id>:" prefix to get the plugin-local topic
	var prefix: String = "plugin:%s:" % AppState.active_activity_plugin_id
	if not topic.begins_with(prefix):
		return
	var local_topic: String = topic.substr(prefix.length())
	_active_runtime.on_data_received(sender_id, local_topic, payload)


## Stops the active activity: deletes the session on the server.
func stop_activity(plugin_id: String) -> void:
	if _active_session_id.is_empty():
		return
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		return
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	await client.plugins.delete_session(plugin_id, _active_session_id)
	_clear_active_activity()
	AppState.activity_ended.emit(plugin_id)


## Transitions the active session to "running" (host only).
func start_session() -> void:
	if _active_session_id.is_empty():
		return
	var plugin_id: String = AppState.active_activity_plugin_id
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		return
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.plugins.update_session_state(
		plugin_id, _active_session_id, "running"
	)
	if result.ok:
		AppState.active_activity_session_state = "running"
		AppState.activity_session_state_changed.emit(plugin_id, "running")


## Assigns a role to a user in the active session.
func assign_role(user_id: String, role: String) -> void:
	if _active_session_id.is_empty():
		return
	var plugin_id: String = AppState.active_activity_plugin_id
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		return
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	await client.plugins.assign_role(
		plugin_id, _active_session_id, user_id, role
	)


## Sends a game action for the active session.
func send_action(plugin_id: String, data: Dictionary) -> void:
	if _active_session_id.is_empty():
		return
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		return
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	await client.plugins.send_action(
		plugin_id, _active_session_id, data
	)


## Returns the active runtime's viewport texture for display, or null.
func get_activity_viewport_texture() -> ViewportTexture:
	if _active_runtime != null and _active_runtime.has_method("get_viewport_texture"):
		return _active_runtime.get_viewport_texture()
	return null


## Forwards an input event to the active runtime (scripted or native).
func forward_activity_input(event: InputEvent) -> void:
	if _active_runtime != null and _active_runtime.has_method("forward_input"):
		_active_runtime.forward_input(event)


# --- Gateway event handlers ---

func on_plugin_installed(data: Dictionary, conn_index: int) -> void:
	var raw: Dictionary = data.get("manifest", data)
	var parsed := AccordPluginManifest.from_dict(raw)
	if parsed.id.is_empty():
		return
	if not _plugin_cache.has(conn_index):
		_plugin_cache[conn_index] = {}
	_plugin_cache[conn_index][parsed.id] = parsed.to_dict()
	AppState.plugins_updated.emit()


func on_plugin_uninstalled(data: Dictionary, conn_index: int) -> void:
	var pid: String = str(data.get("plugin_id", data.get("id", "")))
	if pid.is_empty():
		return
	if _plugin_cache.has(conn_index):
		_plugin_cache[conn_index].erase(pid)
	# If the uninstalled plugin is the active activity, clean up
	if pid == AppState.active_activity_plugin_id:
		_clear_active_activity()
		AppState.activity_ended.emit(pid)
	AppState.plugins_updated.emit()


func on_plugin_event(data: Dictionary, _conn_index: int) -> void:
	var event_type: String = str(data.get("event_type", data.get("type", "")))
	var event_data: Dictionary = data.get("data", {})
	if _active_runtime != null and _active_runtime.has_method("on_plugin_event"):
		_active_runtime.on_plugin_event(event_type, event_data)


func on_plugin_session_state(data: Dictionary, _conn_index: int) -> void:
	var plugin_id: String = str(data.get("plugin_id", ""))
	var session_id: String = str(data.get("session_id", ""))
	var state: String = str(data.get("state", ""))
	if session_id == _active_session_id:
		AppState.active_activity_session_state = state
		# Notify native runtime context of state change
		if _active_runtime != null and _active_runtime is NativeRuntime:
			var ctx: PluginContext = _active_runtime._context
			if ctx != null:
				ctx.session_state = state
				ctx.session_state_changed.emit(state)
		AppState.activity_session_state_changed.emit(plugin_id, state)
		if state == "ended":
			_clear_active_activity()
			AppState.activity_ended.emit(plugin_id)


func on_plugin_role_changed(data: Dictionary, _conn_index: int) -> void:
	var plugin_id: String = str(data.get("plugin_id", ""))
	var user_id: String = str(data.get("user_id", ""))
	var role: String = str(data.get("role", ""))
	if user_id == _c.current_user.get("id", ""):
		AppState.active_activity_role = role
		if _active_runtime != null and _active_runtime is ScriptedRuntime:
			_active_runtime.local_role = role
	# Update participants list on the active runtime
	if _active_runtime != null:
		if _active_runtime is ScriptedRuntime:
			_update_scripted_participants(user_id, role)
		elif _active_runtime is NativeRuntime:
			var ctx: PluginContext = _active_runtime._context
			if ctx != null:
				_update_context_participants(ctx, user_id, role)
				ctx.role_changed.emit(user_id, role)
	AppState.activity_role_changed.emit(plugin_id, user_id, role)


func _update_scripted_participants(user_id: String, role: String) -> void:
	var parts: Array = _active_runtime.participants
	for i in parts.size():
		if parts[i] is Dictionary and str(parts[i].get("user_id", "")) == user_id:
			parts[i]["role"] = role
			return
	# New participant
	parts.append({"user_id": user_id, "role": role})


func _update_context_participants(
	ctx: PluginContext, user_id: String, role: String,
) -> void:
	var parts: Array = ctx.participants
	for i in parts.size():
		if parts[i] is Dictionary and str(parts[i].get("user_id", "")) == user_id:
			parts[i]["role"] = role
			return
	parts.append({"user_id": user_id, "role": role})


# --- Voice disconnect cleanup ---

func _on_voice_left(_channel_id: String) -> void:
	if _active_session_id.is_empty():
		return
	var plugin_id: String = AppState.active_activity_plugin_id
	_clear_active_activity()
	if not plugin_id.is_empty():
		AppState.activity_ended.emit(plugin_id)


# --- Internal ---

func _clear_active_activity() -> void:
	_active_session_id = ""
	_active_conn_index = -1
	# Disconnect LiveKit data channel routing
	if _c.has_node("LiveKitAdapter"):
		var adapter: Node = _c.get_node("LiveKitAdapter")
		if adapter.plugin_data_received.is_connected(_on_livekit_data_received):
			adapter.plugin_data_received.disconnect(_on_livekit_data_received)
	if _active_runtime != null:
		if _active_runtime.has_method("stop"):
			_active_runtime.stop()
		if _active_runtime is Node:
			_active_runtime.queue_free()
		_active_runtime = null
	AppState.active_activity_plugin_id = ""
	AppState.active_activity_channel_id = ""
	AppState.active_activity_session_id = ""
	AppState.active_activity_session_state = ""
	AppState.active_activity_role = ""
