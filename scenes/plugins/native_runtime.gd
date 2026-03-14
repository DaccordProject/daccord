class_name NativeRuntime
extends Node

## Loads a native plugin's entry scene from a downloaded bundle directory,
## instantiates it, and passes a PluginContext for communication.

signal runtime_error(message: String)

var _scene_instance: Node = null
var _context: PluginContext = null
var _running: bool = false


## Starts the native runtime by loading the entry scene and calling
## setup(context) on it.
## bundle_dir: absolute path to the extracted plugin bundle directory
##   (e.g. "user://plugins/<server_id>/<plugin_id>/")
## entry_point: relative path to the entry scene within the bundle
##   (from manifest, e.g. "scenes/main.tscn")
## context: PluginContext with identity, session info, and communication methods
func start(bundle_dir: String, entry_point: String, context: PluginContext) -> bool:
	if _running:
		stop()

	_context = context

	var scene_path: String = bundle_dir.path_join(entry_point)
	if not ResourceLoader.exists(scene_path):
		var msg := "Entry scene not found: " + scene_path
		push_error("[NativeRuntime] " + msg)
		runtime_error.emit(msg)
		return false

	var scene: PackedScene = load(scene_path)
	if scene == null:
		var msg := "Failed to load entry scene: " + scene_path
		push_error("[NativeRuntime] " + msg)
		runtime_error.emit(msg)
		return false

	_scene_instance = scene.instantiate()
	if _scene_instance == null:
		var msg := "Failed to instantiate entry scene"
		push_error("[NativeRuntime] " + msg)
		runtime_error.emit(msg)
		return false

	add_child(_scene_instance)

	# Call setup(context) if the plugin scene has it
	if _scene_instance.has_method("setup"):
		_scene_instance.setup(context)

	_running = true
	return true


## Stops the native runtime and frees all resources.
func stop() -> void:
	if not _running:
		return
	_running = false

	if _scene_instance != null:
		# Give plugin a chance to clean up
		if _scene_instance.has_method("teardown"):
			_scene_instance.teardown()
		_scene_instance.queue_free()
		_scene_instance = null

	_context = null


## Forwards a plugin event from the gateway to the native scene.
func on_plugin_event(event_type: String, data: Dictionary) -> void:
	if not _running or _scene_instance == null:
		return
	if _scene_instance.has_method("on_plugin_event"):
		_scene_instance.on_plugin_event(event_type, data)


## Forwards data channel data to the native scene via PluginContext.
func on_data_received(
	sender_id: String, topic: String, payload: PackedByteArray,
) -> void:
	if _context == null:
		return
	# Check if this is a file transfer
	if topic.begins_with("file:"):
		_handle_file_data(sender_id, payload)
	else:
		_context.data_received.emit(sender_id, topic, payload)


## Returns the scene instance's SubViewport texture if it provides one.
func get_viewport_texture() -> ViewportTexture:
	if _scene_instance != null and _scene_instance.has_method("get_viewport_texture"):
		return _scene_instance.get_viewport_texture()
	return null


## Forwards input events to the native scene.
func forward_input(event: InputEvent) -> void:
	if _scene_instance != null and _scene_instance.has_method("forward_input"):
		_scene_instance.forward_input(event)


func _handle_file_data(
	sender_id: String, payload: PackedByteArray,
) -> void:
	if _context == null or payload.size() < 4:
		return
	var name_len: int = payload.decode_u32(0)
	if payload.size() < 4 + name_len:
		return
	var filename: String = payload.slice(4, 4 + name_len).get_string_from_utf8()
	var file_data: PackedByteArray = payload.slice(4 + name_len)
	_context.file_received.emit(sender_id, filename, file_data)
