class_name GlitchTipClient
extends Node
## Pure GDScript error reporting client for GlitchTip (Sentry-compatible).
##
## Sends events via HTTP POST to the Sentry store API endpoint.
## Replaces the native Sentry GDExtension to eliminate DLL dependencies
## that can cause silent startup crashes on Windows.

const MAX_BREADCRUMBS := 100
const CLIENT_NAME := "daccord-gdscript/1.0"

var _dsn_host: String
var _dsn_path: String
var _dsn_key: String
var _project_id: String
var _store_url: String
var _initialized := false
var _last_event_id: String
var _tags: Dictionary = {}
var _breadcrumbs: Array[Dictionary] = []
var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.use_threads = true
	add_child(_http)


func init(dsn: String) -> bool:
	if dsn.is_empty():
		return false
	if not _parse_dsn(dsn):
		return false
	_set_default_tags()
	_initialized = true
	return true


func is_initialized() -> bool:
	return _initialized


func add_breadcrumb(
	message: String, category: String,
	type: String = "default",
) -> void:
	var crumb := {
		"type": type,
		"category": category,
		"message": message,
		"timestamp": _iso_timestamp(),
	}
	_breadcrumbs.append(crumb)
	while _breadcrumbs.size() > MAX_BREADCRUMBS:
		_breadcrumbs.pop_front()


func set_tag(key: String, value: String) -> void:
	_tags[key] = value


func capture_message(
	message: String, level: String = "info",
) -> void:
	if not _initialized:
		return
	var event := _build_event(level)
	event["message"] = {"formatted": message}
	_send_event(event)


func capture_error(
	message: String, stack: String = "",
) -> void:
	if not _initialized:
		return
	var event := _build_event("error")
	event["message"] = {"formatted": message}
	if not stack.is_empty():
		event["exception"] = {
			"values": [{
				"type": "GDScriptError",
				"value": message,
				"stacktrace": {
					"frames": _parse_stack(stack),
				},
			}],
		}
	_send_event(event)


func get_last_event_id() -> String:
	return _last_event_id


# ---------------------------------------------------------------------------
# Private
# ---------------------------------------------------------------------------

func _parse_dsn(dsn: String) -> bool:
	# DSN format: https://<key>@<host>/<project_id>
	# e.g. https://abc123@crash.daccord.gg/1
	var stripped := dsn.strip_edges()
	if not stripped.begins_with("https://"):
		if not stripped.begins_with("http://"):
			return false

	var scheme_end := stripped.find("://") + 3
	var rest := stripped.substr(scheme_end)
	var scheme := stripped.substr(0, scheme_end)

	var at_pos := rest.find("@")
	if at_pos < 0:
		return false
	_dsn_key = rest.substr(0, at_pos)

	var host_and_path := rest.substr(at_pos + 1)
	var last_slash := host_and_path.rfind("/")
	if last_slash < 0:
		return false
	_project_id = host_and_path.substr(last_slash + 1)
	var host_part := host_and_path.substr(0, last_slash)

	_dsn_host = scheme + host_part
	_store_url = "%s/api/%s/store/" % [_dsn_host, _project_id]
	return true


func _set_default_tags() -> void:
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	_tags["app_version"] = version
	_tags["godot_version"] = Engine.get_version_info().string
	_tags["os"] = OS.get_name()
	_tags["renderer"] = ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "unknown"
	)


func _build_event(level: String) -> Dictionary:
	var event_id := _generate_event_id()
	_last_event_id = event_id
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	return {
		"event_id": event_id,
		"timestamp": _iso_timestamp(),
		"platform": "other",
		"level": level,
		"release": "daccord@" + version,
		"environment": "production",
		"sdk": {
			"name": CLIENT_NAME,
			"version": "1.0.0",
		},
		"tags": _tags.duplicate(),
		"breadcrumbs": {"values": _breadcrumbs.duplicate()},
	}


func _send_event(event: Dictionary) -> void:
	var json := JSON.stringify(event)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"X-Sentry-Auth: Sentry sentry_version=7, "
		+ "sentry_client=%s, " % CLIENT_NAME
		+ "sentry_key=%s" % _dsn_key,
	])
	_http.request(_store_url, headers, HTTPClient.METHOD_POST, json)


func _generate_event_id() -> String:
	# UUID v4 as 32 hex chars (no dashes)
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() % 256
	# Set version (4) and variant (RFC 4122)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	return bytes.hex_encode()


func _iso_timestamp() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		dt.year, dt.month, dt.day,
		dt.hour, dt.minute, dt.second,
	]


func _parse_stack(stack_text: String) -> Array:
	var frames: Array = []
	for line in stack_text.split("\n"):
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		# Try to parse "res://path/file.gd:123 in function_name"
		var colon := stripped.find(":")
		if colon > 0:
			var filename := stripped.substr(0, colon)
			var rest := stripped.substr(colon + 1)
			var space := rest.find(" ")
			var lineno := rest.substr(
				0, space if space > 0 else rest.length()
			)
			var func_name := ""
			var in_pos := rest.find(" in ")
			if in_pos >= 0:
				func_name = rest.substr(in_pos + 4)
			frames.append({
				"filename": filename,
				"lineno": lineno.to_int() if lineno.is_valid_int() else 0,
				"function": func_name,
			})
		else:
			frames.append({"filename": stripped})
	frames.reverse()
	return frames
