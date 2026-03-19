class_name ClientTestApi
extends RefCounted

## Local HTTP API for programmatic client control.
## Implements a minimal HTTP/1.1 server over TCPServer + StreamPeerTCP.
## All endpoints accept POST with JSON body and return JSON responses.

const MAX_CONTENT_LENGTH := 1_048_576 # 1 MB
const READ_TIMEOUT_MS := 5000
const MAX_PENDING_CONNECTIONS := 4
const RATE_LIMIT_BURST := 60
const RATE_LIMIT_WINDOW_MS := 1000
const HEADER_BUF_SIZE := 8192
const LOOPBACK_ADDR := "127.0.0.1"
const _STATUS_TEXTS: Dictionary = {
	200: "OK", 400: "Bad Request", 401: "Unauthorized",
	404: "Not Found", 405: "Method Not Allowed",
	408: "Request Timeout", 413: "Payload Too Large",
	429: "Too Many Requests", 500: "Internal Server Error",
}

var _c: Node # Client autoload
var _server: TCPServer
var _port: int = 39100
var _auth_token: String = ""
var _require_auth: bool = false
var _verbose: bool = false
var _navigate: ClientTestApiNavigate
var _state: ClientTestApiState
var _actions: ClientTestApiActions

# Rate limiting (token bucket)
var _request_timestamps: Array = [] # Array of int (msec)

# Pending async response: when an endpoint awaits, we buffer the peer
var _pending_peers: Array = [] # Array of {peer, start_time}
var _endpoints: Dictionary = {}

func _init(client_node: Node) -> void:
	_c = client_node
	_navigate = ClientTestApiNavigate.new(client_node)
	_state = ClientTestApiState.new(client_node)
	_actions = ClientTestApiActions.new(client_node)
	_init_endpoints()

func start(
	port: int = 39100, token: String = "",
	require_auth: bool = false, verbose: bool = false,
) -> bool:
	_port = port
	_auth_token = token
	_require_auth = require_auth
	_verbose = verbose
	_server = TCPServer.new()
	var err: int = _server.listen(_port, LOOPBACK_ADDR)
	if err != OK:
		push_error(
			"ClientTestApi: Failed to listen on port %d: %s"
			% [_port, error_string(err)]
		)
		return false
	# Verify loopback binding
	if not _server.is_listening():
		push_warning(
			"ClientTestApi: Server reports not listening after "
			+ "bind — loopback binding may have failed silently"
		)
		return false
	print("ClientTestApi: Listening on %s:%d" % [LOOPBACK_ADDR, _port])
	return true

func stop() -> void:
	if _server != null:
		_server.stop()
		_server = null
	_pending_peers.clear()

func is_listening() -> bool:
	return _server != null and _server.is_listening()

func poll() -> void:
	if _server == null or not _server.is_listening():
		return
	# Accept new connections (up to limit)
	var accepted: int = 0
	while _server.is_connection_available() and accepted < MAX_PENDING_CONNECTIONS:
		var peer: StreamPeerTCP = _server.take_connection()
		if peer != null:
			peer.set_no_delay(true)
			_handle_connection(peer)
		accepted += 1

# --- HTTP handling ---

func _handle_connection(peer: StreamPeerTCP) -> void:
	var start_ms: int = Time.get_ticks_msec()
	var result: Dictionary = await _process_request(peer)
	var status_code: int = 200
	if result.has("error"):
		status_code = result.get("_status", 400)
		result.erase("_status")
	var endpoint: String = result.get("_endpoint", "unknown")
	result.erase("_endpoint")
	_send_json(peer, status_code, result)
	peer.disconnect_from_host()
	if _verbose:
		var elapsed: int = Time.get_ticks_msec() - start_ms
		print(
			"ClientTestApi: %s -> %d (%dms)"
			% [endpoint, status_code, elapsed]
		)

func _process_request(peer: StreamPeerTCP) -> Dictionary:
	var start_ms: int = Time.get_ticks_msec()
	var raw: String = _read_request(peer, start_ms)
	if raw.is_empty():
		return {"error": "Request timeout or empty", "_status": 408}

	var validated: Dictionary = _validate_request_line(raw)
	if validated.has("error"):
		return validated

	var path: String = validated["path"]
	var lines: PackedStringArray = raw.split("\r\n")
	var headers: Dictionary = _parse_headers(lines)
	var pre_check: Dictionary = _pre_route_checks(headers)
	if not pre_check.is_empty():
		return pre_check

	var content_length: int = headers.get("content-length", "0").to_int()
	if content_length < 0 or content_length > MAX_CONTENT_LENGTH:
		return {"error": "Request body too large", "_status": 413}

	var body: Dictionary = _parse_body(peer, raw, content_length, start_ms)
	if body.has("_parse_error"):
		return body

	var endpoint: String = path.trim_prefix("/api/")
	return await _route(endpoint, body)

func _validate_request_line(raw: String) -> Dictionary:
	var first_line_end: int = raw.find("\r\n")
	var request_line: String = raw.substr(0, first_line_end) if first_line_end > 0 else raw
	var parts: PackedStringArray = request_line.split(" ")
	if parts.size() < 2:
		return {"error": "Malformed request line", "_status": 400}
	if parts[0] != "POST":
		return {"error": "Method not allowed", "_status": 405}
	if not parts[1].begins_with("/api/"):
		return {"error": "Not found", "_status": 404}
	return {"path": parts[1]}

func _pre_route_checks(headers: Dictionary) -> Dictionary:
	if _require_auth and not _auth_token.is_empty():
		var auth_header: String = headers.get("authorization", "")
		if not _check_auth(auth_header):
			return {"error": "Unauthorized", "_status": 401}
	if _is_rate_limited():
		return {"error": "Too many requests", "_status": 429}
	return {}

func _parse_body(
	peer: StreamPeerTCP, raw: String, content_length: int, start_ms: int
) -> Dictionary:
	if content_length == 0:
		return {}
	var body_str: String = _read_body(peer, raw, content_length, start_ms)
	if body_str.is_empty():
		return {"_parse_error": true, "error": "Body read timeout", "_status": 408}
	var parsed: Variant = JSON.parse_string(body_str)
	if parsed == null and not body_str.strip_edges().is_empty():
		return {"_parse_error": true, "error": "Invalid JSON", "_status": 400}
	if parsed is Dictionary:
		return parsed
	return {}

func _read_request(peer: StreamPeerTCP, start_ms: int) -> String:
	var buf: PackedByteArray = PackedByteArray()
	while buf.size() < HEADER_BUF_SIZE:
		if Time.get_ticks_msec() - start_ms > READ_TIMEOUT_MS:
			return ""
		var available: int = peer.get_available_bytes()
		if available <= 0:
			# Brief yield — let Godot process other frames
			OS.delay_msec(1)
			continue
		var chunk: Array = peer.get_partial_data(
			mini(available, HEADER_BUF_SIZE - buf.size())
		)
		if chunk[0] != OK:
			return ""
		buf.append_array(chunk[1])
		# Check for end of headers
		var text: String = buf.get_string_from_utf8()
		if "\r\n\r\n" in text:
			return text
	return buf.get_string_from_utf8()

func _read_body(
	peer: StreamPeerTCP, raw: String, content_length: int, start_ms: int
) -> String:
	# The body may already be partially (or fully) in raw after \r\n\r\n
	var header_end: int = raw.find("\r\n\r\n")
	if header_end == -1:
		return ""
	var body_start: String = raw.substr(header_end + 4)
	if body_start.length() >= content_length:
		return body_start.substr(0, content_length)

	# Need to read more
	var remaining: int = content_length - body_start.length()
	var buf: PackedByteArray = body_start.to_utf8_buffer()
	while buf.size() < content_length:
		if Time.get_ticks_msec() - start_ms > READ_TIMEOUT_MS:
			return ""
		var available: int = peer.get_available_bytes()
		if available <= 0:
			OS.delay_msec(1)
			continue
		var chunk: Array = peer.get_partial_data(
			mini(available, remaining)
		)
		if chunk[0] != OK:
			return ""
		buf.append_array(chunk[1])
		remaining = content_length - buf.size()
	return buf.get_string_from_utf8()

func _parse_headers(lines: PackedStringArray) -> Dictionary:
	var headers: Dictionary = {}
	for i in range(1, lines.size()):
		var line: String = lines[i]
		if line.is_empty():
			break
		var colon: int = line.find(":")
		if colon == -1:
			continue
		var key: String = line.substr(0, colon).strip_edges().to_lower()
		var value: String = line.substr(colon + 1).strip_edges()
		headers[key] = value
	return headers

func _check_auth(auth_header: String) -> bool:
	if _auth_token.is_empty():
		return true
	if not auth_header.begins_with("Bearer "):
		return false
	var provided: String = auth_header.substr(7)
	# Constant-time comparison
	return _constant_time_compare(provided, _auth_token)

func _constant_time_compare(a: String, b: String) -> bool:
	var a_bytes: PackedByteArray = a.to_utf8_buffer()
	var b_bytes: PackedByteArray = b.to_utf8_buffer()
	if a_bytes.size() != b_bytes.size():
		# Still do work to avoid length-based timing leak
		var dummy: int = 0
		for i in maxi(a_bytes.size(), b_bytes.size()):
			dummy = dummy ^ (a_bytes[i % maxi(a_bytes.size(), 1)])
		return false
	var result: int = 0
	for i in a_bytes.size():
		result = result | (a_bytes[i] ^ b_bytes[i])
	return result == 0

func _is_rate_limited() -> bool:
	var now: int = Time.get_ticks_msec()
	# Prune old timestamps
	while _request_timestamps.size() > 0 \
			and now - _request_timestamps[0] > RATE_LIMIT_WINDOW_MS:
		_request_timestamps.pop_front()
	if _request_timestamps.size() >= RATE_LIMIT_BURST:
		return true
	_request_timestamps.append(now)
	return false

func _send_json(peer: StreamPeerTCP, status: int, data: Dictionary) -> void:
	var body: String = JSON.stringify(data)
	var status_text: String = _status_text(status)
	var response: String = (
		"HTTP/1.1 %d %s\r\n" % [status, status_text]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body.length()
		+ "Connection: close\r\n"
		+ "\r\n"
		+ body
	)
	peer.put_data(response.to_utf8_buffer())

func _send_error(peer: StreamPeerTCP, status: int, message: String) -> void:
	_send_json(peer, status, {"error": message})

func _status_text(code: int) -> String:
	return _STATUS_TEXTS.get(code, "Unknown")

# --- Endpoint routing ---

func _init_endpoints() -> void:
	_endpoints = {
		# State (delegated to _state)
		"get_state": _state.endpoint_get_state,
		"list_spaces": _state.endpoint_list_spaces,
		"get_space": _state.endpoint_get_space,
		"list_channels": _state.endpoint_list_channels,
		"list_members": _state.endpoint_list_members,
		"list_messages": _state.endpoint_list_messages,
		"search_messages": _state.endpoint_search_messages,
		"get_user": _state.endpoint_get_user,
		# Navigation
		"select_space": _endpoint_select_space,
		"select_channel": _endpoint_select_channel,
		"open_dm": _endpoint_open_dm,
		"open_settings": _endpoint_open_settings,
		"open_discovery": _endpoint_open_discovery,
		"open_thread": _endpoint_open_thread,
		"open_voice_view": _endpoint_open_voice_view,
		"toggle_member_list": _endpoint_toggle_member_list,
		"toggle_search": _endpoint_toggle_search,
		"set_viewport_size": _endpoint_set_viewport_size,
		"navigate_to_surface": _endpoint_navigate_to_surface,
		"open_dialog": _endpoint_open_dialog,
		# Screenshot & design tokens (delegated to _state)
		"screenshot": _state.endpoint_screenshot,
		"list_surfaces": _endpoint_list_surfaces,
		"get_surface_info": _endpoint_get_surface_info,
		"get_design_tokens": _state.endpoint_get_design_tokens,
		# Theme (delegated to _state)
		"set_theme": _state.endpoint_set_theme,
		# Actions (delegated to _actions)
		"send_message": _actions.endpoint_send_message,
		"edit_message": _actions.endpoint_edit_message,
		"delete_message": _actions.endpoint_delete_message,
		"add_reaction": _actions.endpoint_add_reaction,
		# Moderation (delegated to _actions)
		"kick_member": _actions.endpoint_kick_member,
		"ban_user": _actions.endpoint_ban_user,
		"unban_user": _actions.endpoint_unban_user,
		"timeout_member": _actions.endpoint_timeout_member,
		# Voice (delegated to _actions)
		"join_voice": _actions.endpoint_join_voice,
		"leave_voice": _actions.endpoint_leave_voice,
		"toggle_mute": _actions.endpoint_toggle_mute,
		"toggle_deafen": _actions.endpoint_toggle_deafen,
		# Lifecycle (delegated to _actions)
		"wait_frames": _actions.endpoint_wait_frames,
		"quit": _actions.endpoint_quit,
	}

func _route(endpoint: String, args: Dictionary) -> Dictionary:
	var handler: Callable = _endpoints.get(endpoint, Callable())
	if not handler.is_valid():
		return {
			"error": "Unknown endpoint: %s" % endpoint,
			"code": "NOT_FOUND",
			"_endpoint": endpoint,
		}
	var result: Dictionary = await handler.call(args)
	if _verbose:
		result["_endpoint"] = endpoint
	return result

# --- Navigation endpoints ---

func _endpoint_select_space(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if not _c._space_cache.has(space_id):
		return {"error": "Space not found: %s" % space_id}
	AppState.select_space(space_id)
	await _c.get_tree().process_frame
	return {"ok": true, "space_id": space_id}

func _endpoint_select_channel(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	var space_id: String = _c._channel_to_space.get(channel_id, "")
	if space_id.is_empty():
		return {"error": "Channel not found: %s" % channel_id}
	AppState.select_channel(channel_id)
	await _c.get_tree().process_frame
	return {"ok": true, "channel_id": channel_id, "space_id": space_id}

func _endpoint_open_dm(_args: Dictionary) -> Dictionary:
	AppState.enter_dm_mode()
	await _c.get_tree().process_frame
	return {"ok": true, "is_dm_mode": true}

func _endpoint_open_settings(args: Dictionary) -> Dictionary:
	# Settings is opened by instantiating the scene — emit signal
	# that main_window listens for. For now, we just note it.
	var page: String = args.get("page", "")
	AppState.settings_opened.emit(page)
	await _c.get_tree().process_frame
	return {"ok": true, "page": page}

func _endpoint_open_discovery(_args: Dictionary) -> Dictionary:
	AppState.open_discovery()
	await _c.get_tree().process_frame
	return {"ok": true, "discovery_open": true}

func _endpoint_open_thread(args: Dictionary) -> Dictionary:
	var message_id: String = args.get("message_id", "")
	if message_id.is_empty():
		return {"error": "message_id is required"}
	AppState.open_thread(message_id)
	await _c.get_tree().process_frame
	return {"ok": true, "thread_id": message_id}

func _endpoint_open_voice_view(_args: Dictionary) -> Dictionary:
	AppState.open_voice_view()
	await _c.get_tree().process_frame
	return {"ok": true, "voice_view_open": AppState.is_voice_view_open}

func _endpoint_toggle_member_list(_args: Dictionary) -> Dictionary:
	AppState.toggle_member_list()
	await _c.get_tree().process_frame
	return {"ok": true, "member_list_visible": AppState.member_list_visible}

func _endpoint_toggle_search(_args: Dictionary) -> Dictionary:
	AppState.toggle_search()
	await _c.get_tree().process_frame
	return {"ok": true, "search_open": AppState.search_open}

func _endpoint_set_viewport_size(args: Dictionary) -> Dictionary:
	var width: int = args.get("width", 0)
	var height: int = args.get("height", 0)
	var preset: String = args.get("preset", "")
	if not preset.is_empty():
		match preset:
			"compact": width = 480; height = 800
			"medium": width = 700; height = 600
			"full": width = 1280; height = 720
			"mobile": width = 360; height = 640
			_: return {"error": "Unknown preset: %s" % preset}
	if width <= 0:
		return {"error": "width is required (or use preset)"}
	if height <= 0:
		height = 720
	DisplayServer.window_set_size(Vector2i(width, height))
	return {"ok": true, "width": width, "height": height}

func _endpoint_navigate_to_surface(args: Dictionary) -> Dictionary:
	var surface_id: String = args.get("surface_id", "")
	var state: String = args.get("state", "default")
	return await _navigate.navigate_to_surface(surface_id, state)

func _endpoint_open_dialog(args: Dictionary) -> Dictionary:
	var dialog_name: String = args.get("dialog_name", "")
	return await _navigate.open_dialog(dialog_name, args)

func _endpoint_list_surfaces(args: Dictionary) -> Dictionary:
	var section: String = args.get("section", "")
	return _navigate.list_surfaces(section)

func _endpoint_get_surface_info(args: Dictionary) -> Dictionary:
	var surface_id: String = args.get("surface_id", "")
	return _navigate.get_surface_info(surface_id)
