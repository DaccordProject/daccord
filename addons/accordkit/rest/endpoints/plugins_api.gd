class_name PluginsApi
extends EndpointBase

## REST endpoint helpers for server plugin management:
## listing, installing, deleting plugins, downloading binaries/bundles,
## session management, role assignment, and action dispatch.


## Lists installed plugins for a space. Optionally filter by type (e.g. "activity").
func list_plugins(space_id: String, type: String = "") -> RestResult:
	var query := {}
	if not type.is_empty():
		query["type"] = type
	var result := await _rest.make_request("GET", "/spaces/" + space_id + "/plugins", null, query)
	return result.deserialize_array(AccordPluginManifest.from_dict)


## Installs a plugin by uploading a manifest and optional bundle (admin only).
## manifest_dict should contain the plugin metadata (name, runtime, type, etc.).
## bundle_data is the optional ZIP bundle (required for native plugins, optional for scripted).
func install_plugin(space_id: String, manifest_dict: Dictionary, bundle_data: PackedByteArray = PackedByteArray(), filename: String = "plugin.daccord-plugin") -> RestResult:
	var form := MultipartForm.new()
	form.add_json("manifest", manifest_dict)
	if not bundle_data.is_empty():
		form.add_file("bundle", filename, bundle_data, "application/zip")
	var result := await _rest.make_multipart_request("POST", "/spaces/" + space_id + "/plugins", form)
	return result.deserialize(AccordPluginManifest.from_dict)


## Uninstalls a plugin from a space (admin only).
func delete_plugin(space_id: String, plugin_id: String) -> RestResult:
	var result := await _rest.make_request("DELETE", "/spaces/" + space_id + "/plugins/" + plugin_id)
	return result


## Downloads the Lua source for a scripted plugin.
## On success, result.data is a PackedByteArray containing the Lua source.
func get_source(plugin_id: String) -> RestResult:
	var result := await _rest.make_raw_request("/plugins/" + plugin_id + "/source")
	return result


## Downloads the full plugin bundle ZIP for a native plugin.
## On success, result.data is a PackedByteArray containing the ZIP bundle.
func get_bundle(plugin_id: String) -> RestResult:
	var result := await _rest.make_raw_request("/plugins/" + plugin_id + "/bundle")
	return result


## Returns active (non-ended) sessions for a channel.
func get_channel_sessions(channel_id: String) -> RestResult:
	var result := await _rest.make_request(
		"GET", "/channels/" + channel_id + "/sessions/active"
	)
	return result


## Creates an activity session in a voice channel.
## Returns: { session_id, state, participants }
func create_session(plugin_id: String, channel_id: String) -> RestResult:
	var result := await _rest.make_request(
		"POST", "/plugins/" + plugin_id + "/sessions",
		{"channel_id": channel_id}
	)
	return result


## Ends an activity session.
func delete_session(plugin_id: String, session_id: String) -> RestResult:
	var result := await _rest.make_request(
		"DELETE", "/plugins/" + plugin_id + "/sessions/" + session_id
	)
	return result


## Transitions session state (host only). state should be "running" or "ended".
func update_session_state(plugin_id: String, session_id: String, state: String) -> RestResult:
	var result := await _rest.make_request(
		"PATCH", "/plugins/" + plugin_id + "/sessions/" + session_id,
		{"state": state}
	)
	return result


## Assigns a participant role within a session.
## role should be "player" or "spectator".
func assign_role(plugin_id: String, session_id: String, user_id: String, role: String) -> RestResult:
	var result := await _rest.make_request(
		"POST", "/plugins/" + plugin_id + "/sessions/" + session_id + "/roles",
		{"user_id": user_id, "role": role}
	)
	return result


## Sends a plugin action (e.g. game move) for scripted plugins.
func send_action(plugin_id: String, session_id: String, data: Dictionary) -> RestResult:
	var result := await _rest.make_request(
		"POST", "/plugins/" + plugin_id + "/sessions/" + session_id + "/actions",
		data
	)
	return result
