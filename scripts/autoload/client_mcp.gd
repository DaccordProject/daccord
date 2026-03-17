class_name ClientMcp
extends RefCounted

## MCP protocol adapter — wraps ClientTestApi with JSON-RPC 2.0,
## bearer token auth, tool group filtering, and MCP content types.
## Binds to 127.0.0.1 only. Requires Developer Mode + MCP toggle.

const MCP_PROTOCOL_VERSION := "2025-03-26"
const LOOPBACK_ADDR := "127.0.0.1"
const HEADER_BUF_SIZE := 8192
const MAX_CONTENT_LENGTH := 1_048_576
const READ_TIMEOUT_MS := 5000
const MAX_PENDING_CONNECTIONS := 4
const RATE_LIMIT_BURST := 60
const RATE_LIMIT_WINDOW_MS := 1000
const _STATUS_TEXTS: Dictionary = {
	200: "OK", 400: "Bad Request", 401: "Unauthorized",
	404: "Not Found", 405: "Method Not Allowed",
	408: "Request Timeout", 413: "Payload Too Large",
	429: "Too Many Requests", 500: "Internal Server Error",
}

# All valid groups
const ALL_GROUPS: PackedStringArray = [
	"read", "navigate", "screenshot", "message", "moderate", "voice",
]
const MAX_LOG_ENTRIES := 100

var _c: Node # Parent Client reference
var _test_api: ClientTestApi
var _server: TCPServer
var _token: String = ""
var _port: int = 39101
var _allowed_groups: PackedStringArray = [
	"read", "navigate", "screenshot",
]

# Rate limiting (token bucket)
var _request_timestamps: Array = []

# Connection activity log (in-memory ring buffer)
var _activity_log: Array = [] # Array of {tool, time, ok}

# Tool definitions: name → {endpoint, group, description, params}
var _tools: Dictionary = {}
# Reverse lookup: tool name → group
var _tool_to_group: Dictionary = {}
# Reverse lookup: tool name → test API endpoint
var _tool_to_endpoint: Dictionary = {}
# JSON-RPC method dispatch (avoids match with >6 returns)
var _methods: Dictionary = {}


func _init(client_node: Node, test_api: ClientTestApi) -> void:
	_c = client_node
	_test_api = test_api
	_init_tools()
	_init_methods()


func start(
	port: int = 39101, token: String = "",
) -> bool:
	_port = port
	_token = token
	_load_config()
	_server = TCPServer.new()
	var err: int = _server.listen(_port, LOOPBACK_ADDR)
	if err != OK:
		push_error(
			"ClientMcp: Failed to listen on port %d: %s"
			% [_port, error_string(err)]
		)
		return false
	if not _server.is_listening():
		push_warning(
			"ClientMcp: Server reports not listening after "
			+ "bind — loopback binding may have failed silently"
		)
		return false
	print("ClientMcp: Listening on %s:%d" % [LOOPBACK_ADDR, _port])
	return true


func stop() -> void:
	if _server != null:
		_server.stop()
		_server = null


func is_listening() -> bool:
	return _server != null and _server.is_listening()


func poll() -> void:
	if _server == null or not _server.is_listening():
		return
	var accepted: int = 0
	while _server.is_connection_available() \
			and accepted < MAX_PENDING_CONNECTIONS:
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			peer.set_no_delay(true)
			_handle_connection(peer)
		accepted += 1


# --- Config ---

func _load_config() -> void:
	_allowed_groups = Config.developer.get_mcp_allowed_groups()


# --- HTTP handling ---

func _handle_connection(peer: StreamPeerTCP) -> void:
	var start_ms: int = Time.get_ticks_msec()
	var response: Dictionary = await _process_mcp_request(
		peer, start_ms
	)
	_send_json(peer, response.get("_status", 200), response["body"])
	peer.disconnect_from_host()


func _process_mcp_request(
	peer: StreamPeerTCP, start_ms: int,
) -> Dictionary:
	var raw: String = _read_request(peer, start_ms)
	if raw.is_empty():
		return _err_response(408, -32600, "Request timeout")

	var validated: Dictionary = _validate_http(raw)
	if validated.has("http_error"):
		return _err_response(
			validated["_status"], -32600,
			validated["http_error"],
		)

	var lines: PackedStringArray = raw.split("\r\n")
	var headers: Dictionary = _parse_headers(lines)
	var pre: Dictionary = _pre_checks(headers)
	if not pre.is_empty():
		return pre

	var body_result: Dictionary = _read_json_body(
		peer, raw, headers, start_ms
	)
	if body_result.has("_status"):
		return body_result

	var result: Dictionary = await _dispatch(body_result)
	return {"_status": 200, "body": result}


func _pre_checks(headers: Dictionary) -> Dictionary:
	if not _check_auth(headers.get("authorization", "")):
		return _err_response(401, -32600, "Unauthorized")
	if _is_rate_limited():
		return _err_response(429, -32600, "Too many requests")
	return {}


func _read_json_body(
	peer: StreamPeerTCP, raw: String,
	headers: Dictionary, start_ms: int,
) -> Dictionary:
	var content_length: int = headers.get(
		"content-length", "0"
	).to_int()
	if content_length < 0 or content_length > MAX_CONTENT_LENGTH:
		return _err_response(
			413, -32600, "Request body too large"
		)

	var body_str: String = _read_body(
		peer, raw, content_length, start_ms
	)
	if body_str.is_empty() and content_length > 0:
		return _err_response(408, -32600, "Body read timeout")

	var parsed: Variant = JSON.parse_string(body_str)
	if parsed == null or not (parsed is Dictionary):
		return _err_response(400, -32700, "Parse error")
	return parsed


func _err_response(
	status: int, code: int, message: String,
) -> Dictionary:
	return {
		"_status": status,
		"body": _jsonrpc_error(code, message, null),
	}


# --- JSON-RPC dispatch ---

func _init_methods() -> void:
	_methods = {
		"initialize": _method_initialize,
		"notifications/initialized": _method_noop,
		"tools/list": _method_tools_list,
		"tools/call": _method_tools_call,
	}

func _dispatch(request: Dictionary) -> Dictionary:
	var id: Variant = request.get("id")
	var method: String = request.get("method", "")
	if method.is_empty():
		return _jsonrpc_error(-32600, "Missing method", id)
	var handler: Callable = _methods.get(method, Callable())
	if not handler.is_valid():
		return _jsonrpc_error(
			-32601, "Method not found: %s" % method, id,
		)
	return await handler.call(id, request)

func _method_initialize(
	id: Variant, _request: Dictionary,
) -> Dictionary:
	return _handle_initialize(id)

func _method_noop(
	id: Variant, _request: Dictionary,
) -> Dictionary:
	return _jsonrpc_result(id, {}) if id != null else {}

func _method_tools_list(
	id: Variant, _request: Dictionary,
) -> Dictionary:
	return _handle_tools_list(id)

func _method_tools_call(
	id: Variant, request: Dictionary,
) -> Dictionary:
	var params: Dictionary = request.get("params", {})
	return await _handle_tools_call(id, params)


func _handle_initialize(id: Variant) -> Dictionary:
	return _jsonrpc_result(id, {
		"protocolVersion": MCP_PROTOCOL_VERSION,
		"capabilities": {
			"tools": {"listChanged": false},
		},
		"serverInfo": {
			"name": "daccord",
			"version": _get_app_version(),
		},
	})


func _handle_tools_list(id: Variant) -> Dictionary:
	var tools_array: Array = []
	for tool_name in _tools:
		var tool_def: Dictionary = _tools[tool_name]
		var group: String = tool_def.get("group", "")
		if group not in _allowed_groups:
			continue
		tools_array.append({
			"name": tool_name,
			"description": tool_def.get("description", ""),
			"inputSchema": tool_def.get("inputSchema", {
				"type": "object", "properties": {},
			}),
		})
	return _jsonrpc_result(id, {"tools": tools_array})


func _handle_tools_call(
	id: Variant, params: Dictionary,
) -> Dictionary:
	var tool_name: String = params.get("name", "")
	var arguments: Dictionary = params.get("arguments", {})

	if tool_name.is_empty():
		return _jsonrpc_error(-32602, "Missing tool name", id)

	# Check tool exists
	var group: String = _tool_to_group.get(tool_name, "")
	if group.is_empty():
		_log_activity(tool_name, false)
		return _jsonrpc_error(
			-32601, "Unknown tool: %s" % tool_name, id,
		)

	# Check group permission
	if group not in _allowed_groups:
		_log_activity(tool_name, false)
		return _jsonrpc_error(
			-32600,
			"Tool group '%s' is not enabled" % group,
			id,
		)

	# Delegate to test API
	var endpoint: String = _tool_to_endpoint.get(
		tool_name, tool_name
	)
	var result: Dictionary = await _test_api._route(
		endpoint, arguments
	)
	_log_activity(tool_name, not result.has("error"))

	# Wrap in MCP content format
	return _jsonrpc_result(
		id, _wrap_mcp_result(tool_name, result)
	)


# --- MCP content wrapping ---

func _wrap_mcp_result(
	tool_name: String, result: Dictionary,
) -> Dictionary:
	if tool_name == "take_screenshot" and result.has("image_base64"):
		var image_data: String = result["image_base64"]
		result.erase("image_base64")
		return {
			"content": [
				{
					"type": "image",
					"data": image_data,
					"mimeType": "image/png",
				},
				{
					"type": "text",
					"text": JSON.stringify(result),
				},
			],
		}
	return {
		"content": [
			{"type": "text", "text": JSON.stringify(result)},
		],
	}


# --- JSON-RPC helpers ---

func _jsonrpc_result(
	id: Variant, result: Variant,
) -> Dictionary:
	return {"jsonrpc": "2.0", "result": result, "id": id}


func _jsonrpc_error(
	code: int, message: String, id: Variant,
) -> Dictionary:
	return {
		"jsonrpc": "2.0",
		"error": {"code": code, "message": message},
		"id": id,
	}


# --- Activity log ---

func _log_activity(tool_name: String, ok: bool) -> void:
	_activity_log.append({
		"tool": tool_name,
		"time": Time.get_datetime_string_from_system(),
		"ok": ok,
	})
	if _activity_log.size() > MAX_LOG_ENTRIES:
		_activity_log.pop_front()


func get_activity_log() -> Array:
	return _activity_log.duplicate()


# --- Auth ---

func _check_auth(auth_header: String) -> bool:
	if _token.is_empty():
		return true
	if not auth_header.begins_with("Bearer "):
		return false
	var provided: String = auth_header.substr(7)
	return _constant_time_compare(provided, _token)


func _constant_time_compare(a: String, b: String) -> bool:
	var a_bytes: PackedByteArray = a.to_utf8_buffer()
	var b_bytes: PackedByteArray = b.to_utf8_buffer()
	if a_bytes.size() != b_bytes.size():
		var dummy: int = 0
		for i in maxi(a_bytes.size(), b_bytes.size()):
			dummy = dummy ^ (
				a_bytes[i % maxi(a_bytes.size(), 1)]
			)
		return false
	var result: int = 0
	for i in a_bytes.size():
		result = result | (a_bytes[i] ^ b_bytes[i])
	return result == 0


# --- Rate limiting ---

func _is_rate_limited() -> bool:
	var now: int = Time.get_ticks_msec()
	while _request_timestamps.size() > 0 \
			and now - _request_timestamps[0] > RATE_LIMIT_WINDOW_MS:
		_request_timestamps.pop_front()
	if _request_timestamps.size() >= RATE_LIMIT_BURST:
		return true
	_request_timestamps.append(now)
	return false


# --- HTTP helpers ---

func _validate_http(raw: String) -> Dictionary:
	var first_line_end: int = raw.find("\r\n")
	var request_line: String = (
		raw.substr(0, first_line_end)
		if first_line_end > 0 else raw
	)
	var parts: PackedStringArray = request_line.split(" ")
	if parts.size() < 2:
		return {"http_error": "Malformed request", "_status": 400}
	if parts[0] != "POST":
		return {"http_error": "Method not allowed", "_status": 405}
	# Accept /mcp or /mcp/ path
	var path: String = parts[1]
	if path != "/mcp" and path != "/mcp/":
		return {"http_error": "Not found", "_status": 404}
	return {"path": path}


func _parse_headers(lines: PackedStringArray) -> Dictionary:
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.is_empty():
			break
		var colon: int = line.find(":")
		if colon == -1:
			continue
		var key: String = (
			line.substr(0, colon).strip_edges().to_lower()
		)
		var value: String = line.substr(colon + 1).strip_edges()
		headers[key] = value
	return headers


func _read_request(
	peer: StreamPeerTCP, start_ms: int,
) -> String:
	var buf: PackedByteArray = PackedByteArray()
	while buf.size() < HEADER_BUF_SIZE:
		if Time.get_ticks_msec() - start_ms > READ_TIMEOUT_MS:
			return ""
		var available: int = peer.get_available_bytes()
		if available <= 0:
			OS.delay_msec(1)
			continue
		var chunk: Array = peer.get_partial_data(
			mini(available, HEADER_BUF_SIZE - buf.size())
		)
		if chunk[0] != OK:
			return ""
		buf.append_array(chunk[1])
		var text: String = buf.get_string_from_utf8()
		if "\r\n\r\n" in text:
			return text
	return buf.get_string_from_utf8()


func _read_body(
	peer: StreamPeerTCP, raw: String,
	content_length: int, start_ms: int,
) -> String:
	if content_length == 0:
		return ""
	var header_end: int = raw.find("\r\n\r\n")
	if header_end == -1:
		return ""
	var body_start: String = raw.substr(header_end + 4)
	if body_start.length() >= content_length:
		return body_start.substr(0, content_length)
	var buf: PackedByteArray = body_start.to_utf8_buffer()
	while buf.size() < content_length:
		if Time.get_ticks_msec() - start_ms > READ_TIMEOUT_MS:
			return ""
		var available: int = peer.get_available_bytes()
		if available <= 0:
			OS.delay_msec(1)
			continue
		var remaining: int = content_length - buf.size()
		var chunk: Array = peer.get_partial_data(
			mini(available, remaining)
		)
		if chunk[0] != OK:
			return ""
		buf.append_array(chunk[1])
	return buf.get_string_from_utf8()


func _send_json(
	peer: StreamPeerTCP, status: int, data: Dictionary,
) -> void:
	var body: String = JSON.stringify(data)
	var status_text: String = _STATUS_TEXTS.get(status, "Unknown")
	var response: String = (
		"HTTP/1.1 %d %s\r\n" % [status, status_text]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body.length()
		+ "Connection: close\r\n"
		+ "\r\n"
		+ body
	)
	peer.put_data(response.to_utf8_buffer())


# --- Tool definitions ---

func _init_tools() -> void:
	# Read group
	_register("get_current_state", "get_state", "read",
		"Get current client state (space, channel, layout)",
		{})
	_register("list_spaces", "list_spaces", "read",
		"List all spaces the user is in",
		{})
	_register("list_channels", "list_channels", "read",
		"List channels in a space",
		_schema({"space_id": "string"}, ["space_id"]))
	_register("list_members", "list_members", "read",
		"List members of a space",
		_schema({"space_id": "string"}, ["space_id"]))
	_register("list_messages", "list_messages", "read",
		"List recent messages in a channel",
		_schema({
			"channel_id": "string", "limit": "integer",
		}, ["channel_id"]))
	_register("search_messages", "search_messages", "read",
		"Search messages in a space",
		_schema({
			"query": "string", "space_id": "string",
		}, ["query"]))
	_register("get_user", "get_user", "read",
		"Get user details by ID",
		_schema({"user_id": "string"}, ["user_id"]))
	_register("get_space", "get_space", "read",
		"Get space details by ID",
		_schema({"space_id": "string"}, ["space_id"]))

	# Navigate group
	_register("select_space", "select_space", "navigate",
		"Switch to a space",
		_schema({"space_id": "string"}, ["space_id"]))
	_register("select_channel", "select_channel", "navigate",
		"Switch to a channel",
		_schema({"channel_id": "string"}, ["channel_id"]))
	_register("open_dm", "open_dm", "navigate",
		"Enter DM mode", {})
	_register("open_settings", "open_settings", "navigate",
		"Open app settings",
		_schema({"page": "string"}, []))
	_register("open_discovery", "open_discovery", "navigate",
		"Open server discovery panel", {})
	_register("open_thread", "open_thread", "navigate",
		"Open a message thread",
		_schema({"message_id": "string"}, ["message_id"]))
	_register("open_voice_view", "open_voice_view", "navigate",
		"Open voice/video view", {})
	_register(
		"toggle_member_list", "toggle_member_list", "navigate",
		"Toggle member list visibility", {},
	)
	_register("toggle_search", "toggle_search", "navigate",
		"Toggle search panel", {})
	_register(
		"navigate_to_surface", "navigate_to_surface", "navigate",
		"Navigate to a UI audit surface by ID",
		_schema({
			"surface_id": "string", "state": "string",
		}, ["surface_id"]),
	)
	_register("open_dialog", "open_dialog", "navigate",
		"Open a named dialog",
		_schema({"dialog_name": "string"}, ["dialog_name"]))
	_register(
		"set_viewport_size", "set_viewport_size", "navigate",
		"Resize viewport (preset or width/height)",
		_schema({
			"preset": "string",
			"width": "integer",
			"height": "integer",
		}, []),
	)

	# Screenshot group
	_register("take_screenshot", "screenshot", "screenshot",
		"Capture a viewport screenshot as base64 PNG",
		_schema({"save_path": "string"}, []))
	_register("list_surfaces", "list_surfaces", "screenshot",
		"List UI audit surface sections",
		_schema({"section": "string"}, []))
	_register(
		"get_surface_info", "get_surface_info", "screenshot",
		"Get info about a UI surface",
		_schema({"surface_id": "string"}, ["surface_id"]),
	)

	# Message group
	_register("send_message", "send_message", "message",
		"Send a message to a channel",
		_schema({
			"channel_id": "string", "content": "string",
			"reply_to": "string",
		}, ["channel_id", "content"]))
	_register("edit_message", "edit_message", "message",
		"Edit a message",
		_schema({
			"message_id": "string", "content": "string",
		}, ["message_id", "content"]))
	_register("delete_message", "delete_message", "message",
		"Delete a message",
		_schema({"message_id": "string"}, ["message_id"]))
	_register("add_reaction", "add_reaction", "message",
		"Add a reaction to a message",
		_schema({
			"channel_id": "string",
			"message_id": "string",
			"emoji": "string",
		}, ["channel_id", "message_id", "emoji"]))

	# Moderate group
	_register("kick_member", "kick_member", "moderate",
		"Kick a member from a space",
		_schema({
			"space_id": "string", "user_id": "string",
		}, ["space_id", "user_id"]))
	_register("ban_user", "ban_user", "moderate",
		"Ban a user from a space",
		_schema({
			"space_id": "string",
			"user_id": "string",
			"reason": "string",
		}, ["space_id", "user_id"]))
	_register("unban_user", "unban_user", "moderate",
		"Unban a user from a space",
		_schema({
			"space_id": "string", "user_id": "string",
		}, ["space_id", "user_id"]))
	_register("timeout_member", "timeout_member", "moderate",
		"Timeout a member in a space",
		_schema({
			"space_id": "string",
			"user_id": "string",
			"duration": "integer",
		}, ["space_id", "user_id", "duration"]))

	# Voice group
	_register("join_voice_channel", "join_voice", "voice",
		"Join a voice channel",
		_schema({"channel_id": "string"}, ["channel_id"]))
	_register("leave_voice", "leave_voice", "voice",
		"Leave the current voice channel", {})
	_register("toggle_mute", "toggle_mute", "voice",
		"Toggle microphone mute", {})
	_register("toggle_deafen", "toggle_deafen", "voice",
		"Toggle audio deafen", {})


func _register(
	tool_name: String, endpoint: String, group: String,
	description: String, input_schema: Dictionary,
) -> void:
	if input_schema.is_empty():
		input_schema = {"type": "object", "properties": {}}
	_tools[tool_name] = {
		"endpoint": endpoint,
		"group": group,
		"description": description,
		"inputSchema": input_schema,
	}
	_tool_to_group[tool_name] = group
	_tool_to_endpoint[tool_name] = endpoint


func _schema(
	props: Dictionary, required: Array,
) -> Dictionary:
	var properties: Dictionary = {}
	for key in props:
		properties[key] = {"type": props[key]}
	var s: Dictionary = {
		"type": "object", "properties": properties,
	}
	if not required.is_empty():
		s["required"] = required
	return s


func _get_app_version() -> String:
	return ProjectSettings.get_setting(
		"application/config/version", "0.0.0"
	)
