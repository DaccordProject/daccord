extends RefCounted

## Utility helpers for ClientPlugins: bundle extraction, trust dialogs,
## and participant list updates.

var _c: Node


func _init(client_node: Node) -> void:
	_c = client_node


## Extracts entry Lua source, modules, and assets from a plugin bundle ZIP.
## Returns { "lua_source": String, "modules": Dictionary, "assets": Dictionary }
## or an empty Dictionary on failure.
static func extract_bundle(
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


## Shows a trust confirmation dialog and waits for the user's response.
## Returns true if the user grants trust, false if denied.
func show_trust_dialog(
	plugin_name: String, server_id: String, plugin_id: String,
) -> bool:
	var dialog_scene: PackedScene = load(
		"res://scenes/plugins/plugin_trust_dialog.tscn"
	)
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
static func is_plugin_trusted(
	server_id: String, plugin_id: String,
) -> bool:
	if Config.is_plugin_trust_all(server_id):
		return true
	return Config.get_plugin_trust(server_id, plugin_id)


## Updates the participants array on a ScriptedRuntime.
static func update_scripted_participants(
	runtime: Node, user_id: String, role: String,
) -> void:
	var parts: Array = runtime.participants
	for i in parts.size():
		if parts[i] is Dictionary \
				and str(parts[i].get("user_id", "")) == user_id:
			parts[i]["role"] = role
			return
	# New participant
	parts.append({"user_id": user_id, "role": role})


## Updates the participants array on a PluginContext.
static func update_context_participants(
	ctx: PluginContext, user_id: String, role: String,
) -> void:
	var parts: Array = ctx.participants
	for i in parts.size():
		if parts[i] is Dictionary \
				and str(parts[i].get("user_id", "")) == user_id:
			parts[i]["role"] = role
			return
	parts.append({"user_id": user_id, "role": role})
