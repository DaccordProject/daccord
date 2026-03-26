class_name ClientPlugins
extends RefCounted

## Manages plugin state: caching manifests, launching/stopping activities,
## and handling gateway events for plugins.

const HelpersClass := preload(
	"res://scripts/client/client_plugins_helpers.gd"
)

var _c: Node # Client autoload

# Per-connection plugin cache: conn_index -> { plugin_id -> manifest dict }
var _plugin_cache: Dictionary = {}

# Active activity state
var _active_runtime: Node = null
var _active_session_id: String = ""
var _active_conn_index: int = -1
var _is_host: bool = false
var _host_user_id: String = ""
var _session_participants: Array = []

var _scripted_runtime_class = null  # loaded on demand
var _native_runtime_class = null   # loaded on demand
var _download_manager: PluginDownloadManager = null
var _helpers: HelpersClass = null


func _init(client_node: Node) -> void:
	_c = client_node
	_download_manager = PluginDownloadManager.new(client_node)
	_helpers = HelpersClass.new(client_node)
	AppState.voice_left.connect(_on_voice_left)
	AppState.voice_joined.connect(_on_voice_joined)


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


## Launches an activity: checks for an existing session in the channel first
## and rejoins it if found, otherwise creates a new session on the server.
## Downloads the Lua source (for scripted plugins), starts the runtime, and
## updates AppState.
func launch_activity(plugin_id: String, channel_id: String) -> Dictionary:
	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		push_error("[ClientPlugins] Plugin not found: ", plugin_id)
		return {"error": "Plugin not found"}
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return {"error": "Not connected"}
	var client: AccordClient = conn["client"]

	# Check for an existing session in this channel before creating a new one.
	var existing: Dictionary = await _find_existing_session(
		client, plugin_id, channel_id
	)
	if not existing.is_empty():
		return await _rejoin_session(
			existing, plugin_id, channel_id, conn_idx, client
		)

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

	_clear_pending_activity()
	_active_session_id = session_id
	_active_conn_index = conn_idx
	_is_host = true
	_host_user_id = _c.current_user.get("id", "")
	AppState.active_activity_plugin_id = plugin_id
	AppState.active_activity_channel_id = channel_id
	AppState.active_activity_session_id = session_id
	AppState.active_activity_session_state = state
	AppState.active_activity_role = "player"
	var session_participants: Array = session.get("participants", [])
	_session_participants = session_participants
	AppState.activity_started.emit(plugin_id, channel_id)
	_broadcast_activity_presence(plugin_id)

	# Prepare the appropriate runtime based on plugin type.
	var manifest: Dictionary = get_plugin(plugin_id)
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
	var bundle: Dictionary = HelpersClass.extract_bundle(zip_bytes, manifest)
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
		if not HelpersClass.is_plugin_trusted(server_id, plugin_id):
			var trusted: bool = await _helpers.show_trust_dialog(
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
	context.host_user_id = _host_user_id
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


## Joins a pending activity session: assigns self as player, sets up state,
## and downloads the runtime.
func join_activity() -> void:
	var plugin_id: String = AppState.pending_activity_plugin_id
	var session_id: String = AppState.pending_activity_session_id
	var channel_id: String = AppState.pending_activity_channel_id
	var host_user_id: String = AppState.pending_activity_host_user_id
	var state: String = AppState.pending_activity_state
	if plugin_id.is_empty() or session_id.is_empty():
		return
	# Non-participants cannot join a session that is already running
	if state == "running":
		return

	var conn_idx: int = get_conn_index_for_plugin(plugin_id)
	if conn_idx == -1:
		push_error("[ClientPlugins] Plugin not found for join: ", plugin_id)
		return
	var conn: Dictionary = _c._connections[conn_idx]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]

	# Join by assigning self as player
	var my_id: String = _c.current_user.get("id", "")
	var result: RestResult = await client.plugins.assign_role(
		plugin_id, session_id, my_id, "player"
	)
	if not result.ok:
		var err: String = result.error.message if result.error else "unknown"
		push_error("[ClientPlugins] Failed to join activity: ", err)
		return

	# Clear pending and set active
	_clear_pending_activity()
	_active_session_id = session_id
	_active_conn_index = conn_idx
	_is_host = false
	_host_user_id = host_user_id
	AppState.active_activity_plugin_id = plugin_id
	AppState.active_activity_channel_id = channel_id
	AppState.active_activity_session_id = session_id
	AppState.active_activity_session_state = state
	AppState.active_activity_role = "player"
	var session_data: Dictionary = result.data if result.data is Dictionary else {}
	var participants: Array = session_data.get("participants", [])
	_session_participants = participants
	AppState.activity_started.emit(plugin_id, channel_id)
	_broadcast_activity_presence(plugin_id)

	# Download and prepare runtime
	var manifest: Dictionary = get_plugin(plugin_id)
	var runtime_type: String = manifest.get("runtime", "")
	if runtime_type == "scripted":
		await _download_and_prepare_scripted_runtime(
			plugin_id, manifest, conn_idx, participants,
		)
	elif runtime_type == "native":
		await _download_and_prepare_native_runtime(
			plugin_id, manifest, conn_idx, participants,
		)


## Stops the active activity. Host deletes the session; non-host just leaves.
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
	if _is_host:
		await client.plugins.delete_session(plugin_id, _active_session_id)
	else:
		await client.plugins.leave_session(plugin_id, _active_session_id)
	_clear_active_activity()
	_broadcast_activity_presence("")
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


## Returns whether the local user is the host of the active activity.
func is_activity_host() -> bool:
	return _is_host


## Returns the current session participants list.
func get_session_participants() -> Array:
	return _session_participants


## Checks if there's an active session in the given voice channel.
## Called on voice join and reconnect to discover ongoing activities.
## If a session is found the user is automatically rejoined (re-added as
## participant if needed), so they land back in the lobby with their slot.
func check_active_session(
	channel_id: String, conn_index: int,
) -> void:
	if channel_id.is_empty() or conn_index < 0 \
		or conn_index >= _c._connections.size() \
		or not AppState.active_activity_session_id.is_empty():
		return
	var conn: Dictionary = _c._connections[conn_index]
	if conn == null or conn.get("client") == null:
		return
	var client: AccordClient = conn["client"]
	var result: RestResult = await client.plugins.get_channel_sessions(
		channel_id
	)
	if not result.ok or not (result.data is Array):
		return
	var sessions: Array = result.data
	if sessions.is_empty():
		return
	var session: Dictionary = sessions[0]
	var plugin_id: String = str(session.get("plugin_id", ""))
	if plugin_id.is_empty() or str(session.get("id", "")).is_empty():
		return
	# Auto-rejoin: _rejoin_session handles both "still a participant" and
	# "need to re-add" cases, preserving the player's lobby slot.
	await _rejoin_session(session, plugin_id, channel_id, conn_index, client)


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
		_broadcast_activity_presence("")
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
	var channel_id: String = str(data.get("channel_id", ""))

	# Update to an already-active session (host or joined participant)
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
			_broadcast_activity_presence("")
			AppState.activity_ended.emit(plugin_id)
		return

	# New session announcement from another user — show as pending
	if state == "ended":
		# Clear pending if it matches
		if session_id == AppState.pending_activity_session_id:
			_clear_pending_activity()
		return

	# Session transitioned to "running" — non-participants can no longer join
	if state == "running":
		if session_id == AppState.pending_activity_session_id:
			_clear_pending_activity()
		return

	# Only show pending activity if we're in the same voice channel
	if channel_id.is_empty() or channel_id != AppState.voice_channel_id:
		return

	# Don't overwrite an already-active activity
	if not AppState.active_activity_session_id.is_empty():
		return

	var host_user_id: String = str(data.get("host_user_id", ""))
	AppState.pending_activity_plugin_id = plugin_id
	AppState.pending_activity_channel_id = channel_id
	AppState.pending_activity_session_id = session_id
	AppState.pending_activity_host_user_id = host_user_id
	AppState.pending_activity_state = state
	AppState.activity_available.emit(plugin_id, channel_id, session_id)


func on_plugin_role_changed(data: Dictionary, _conn_index: int) -> void:
	var plugin_id: String = str(data.get("plugin_id", ""))
	var session_id: String = str(data.get("session_id", ""))
	var user_id: String = str(data.get("user_id", ""))
	var role: String = str(data.get("role", ""))
	var participants: Array = data.get("participants", [])
	if user_id == _c.current_user.get("id", ""):
		AppState.active_activity_role = role
		if _active_runtime != null and _active_runtime is ScriptedRuntime:
			_active_runtime.local_role = role
	# Update participants list on the active runtime
	if _active_runtime != null:
		if _active_runtime is ScriptedRuntime:
			HelpersClass.update_scripted_participants(
				_active_runtime, user_id, role,
			)
		elif _active_runtime is NativeRuntime:
			var ctx: PluginContext = _active_runtime._context
			if ctx != null:
				HelpersClass.update_context_participants(
					ctx, user_id, role,
				)
				ctx.role_changed.emit(user_id, role)
	AppState.activity_role_changed.emit(plugin_id, user_id, role)
	if not participants.is_empty():
		_session_participants = participants
		AppState.activity_participants_updated.emit(
			session_id, participants
		)


# --- Voice join/leave ---

func _on_voice_joined(channel_id: String) -> void:
	# Discover any active session in the channel we just joined
	var space_id: String = _c._channel_to_space.get(channel_id, "")
	if space_id.is_empty():
		return
	var conn_idx: int = _c._space_to_conn.get(space_id, -1)
	if conn_idx >= 0:
		check_active_session(channel_id, conn_idx)


func _on_voice_left(_channel_id: String, intentional: bool = true) -> void:
	_clear_pending_activity()
	if _active_session_id.is_empty():
		return
	var plugin_id: String = AppState.active_activity_plugin_id
	# Non-intentional disconnect (network drop, server kick): keep the
	# runtime alive so game state is preserved.  When voice reconnects
	# the session resumes seamlessly — check_active_session sees the
	# active session and skips re-creation.
	if not intentional:
		return
	# Intentional leave: remove ourselves from the session and tear down.
	if not _is_host and not _active_session_id.is_empty():
		var conn_idx: int = get_conn_index_for_plugin(plugin_id)
		if conn_idx >= 0 and conn_idx < _c._connections.size():
			var conn: Dictionary = _c._connections[conn_idx]
			if conn != null and conn.get("client") != null:
				var client: AccordClient = conn["client"]
				client.plugins.leave_session(plugin_id, _active_session_id)
	_clear_active_activity()
	if not plugin_id.is_empty():
		_broadcast_activity_presence("")
		AppState.activity_ended.emit(plugin_id)


# --- Internal ---

## Queries active sessions in a channel and returns the first one matching
## the given plugin_id. Returns an empty Dictionary if none found.
func _find_existing_session(
	client: AccordClient, plugin_id: String, channel_id: String,
) -> Dictionary:
	var result: RestResult = await client.plugins.get_channel_sessions(
		channel_id
	)
	if not result.ok or not (result.data is Array):
		return {}
	for session in result.data:
		if str(session.get("plugin_id", "")) == plugin_id:
			return session
	return {}


## Rejoins an existing session: assigns self as player if not already a
## participant, then sets up state and starts the runtime.
func _rejoin_session(
	session: Dictionary, plugin_id: String, channel_id: String,
	conn_idx: int, client: AccordClient,
) -> Dictionary:
	var session_id: String = str(session.get("id", ""))
	var state: String = str(session.get("state", ""))
	var host_user_id: String = str(session.get("host_user_id", ""))
	var my_id: String = _c.current_user.get("id", "")
	var participants: Array = session.get("participants", [])

	# Check if we're already a participant
	var is_participant := false
	for p in participants:
		if str(p.get("user_id", "")) == my_id:
			is_participant = true
			break

	# Non-participants cannot join a session that is already running
	if not is_participant and state == "running":
		return {"error": "Session already running"}

	# If not a participant, join by assigning self as player
	if not is_participant:
		var role_result: RestResult = await client.plugins.assign_role(
			plugin_id, session_id, my_id, "player"
		)
		if not role_result.ok:
			var err: String = (
				role_result.error.message if role_result.error else "unknown"
			)
			push_error("[ClientPlugins] Failed to rejoin session: ", err)
			return {"error": err}
		if role_result.data is Dictionary:
			participants = role_result.data.get("participants", participants)

	_clear_pending_activity()
	# Stop any previously active runtime before setting up the new one.
	# Without this the old runtime leaks and on web/WASM Lua errors from
	# the stale state can trigger an unrecoverable abort.
	if _active_runtime != null:
		if _active_runtime.has_method("stop"):
			_active_runtime.stop()
		if _active_runtime is Node:
			_active_runtime.queue_free()
		_active_runtime = null
	_active_session_id = session_id
	_active_conn_index = conn_idx
	_is_host = host_user_id == my_id
	_host_user_id = host_user_id
	_session_participants = participants
	AppState.active_activity_plugin_id = plugin_id
	AppState.active_activity_channel_id = channel_id
	AppState.active_activity_session_id = session_id
	AppState.active_activity_session_state = state
	AppState.active_activity_role = "player"

	# Prepare the runtime BEFORE emitting activity_started so that the
	# viewport texture is available when the video grid rebuilds.  This
	# matters when the session state is "running" (rejoin mid-game).
	var manifest: Dictionary = get_plugin(plugin_id)
	var runtime_type: String = manifest.get("runtime", "")
	if runtime_type == "scripted":
		await _download_and_prepare_scripted_runtime(
			plugin_id, manifest, conn_idx, participants,
		)
	elif runtime_type == "native":
		await _download_and_prepare_native_runtime(
			plugin_id, manifest, conn_idx, participants,
		)

	AppState.activity_started.emit(plugin_id, channel_id)
	_broadcast_activity_presence(plugin_id)

	# Request the current game state from the host so the rejoining player
	# can resume where they left off.  Not gated on server session state
	# because games manage phase transitions inside Lua without updating
	# the server session state.
	_request_state_sync(plugin_id, my_id)

	return session


## Notifies the session that a player has rejoined and needs the current
## game state.  Sends a "state_request" action through the server so the
## host's Lua runtime receives it via _on_event and can respond with a
## full state snapshot.
func _request_state_sync(plugin_id: String, user_id: String) -> void:
	# Ask the host to push current game state via the server.
	# NOTE: We intentionally do NOT fire a local "rejoin" event on the
	# runtime here — the runtime was just created fresh during rejoin, so
	# its Lua code hasn't accumulated any state to reset.  Sending a
	# "rejoin" event to uninitialised Lua state triggers a type error
	# that crashes web/WASM builds (luaD_throw → ___cxa_throw → abort).
	send_action(
		plugin_id, {"action": "state_request", "user_id": user_id}
	)


## Sends a presence update with the current activity to all connected servers.
## Pass an empty plugin_id to clear the activity from presence.
func _broadcast_activity_presence(plugin_id: String) -> void:
	var activity: Dictionary = {}
	if not plugin_id.is_empty():
		var manifest: Dictionary = get_plugin(plugin_id)
		activity = {"name": manifest.get("name", plugin_id), "type": "playing"}
	var status: int = _c.current_user.get("status", 0)
	var s: String = ClientModels._status_enum_to_string(status)
	for conn in _c._connections:
		if conn != null \
				and conn["status"] == "connected" \
				and conn["client"] != null:
			conn["client"].update_presence(s, activity)


func _clear_pending_activity() -> void:
	AppState.pending_activity_plugin_id = ""
	AppState.pending_activity_channel_id = ""
	AppState.pending_activity_session_id = ""
	AppState.pending_activity_host_user_id = ""
	AppState.pending_activity_state = ""


func _clear_active_activity() -> void:
	_active_session_id = ""
	_active_conn_index = -1
	_is_host = false
	_host_user_id = ""
	_session_participants = []
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
