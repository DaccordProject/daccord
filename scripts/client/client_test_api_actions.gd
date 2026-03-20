class_name ClientTestApiActions
extends RefCounted

## Mutation, moderation, voice, and lifecycle endpoint handlers
## for ClientTestApi.

const _KEY_MAP: Dictionary = {
	"enter": KEY_ENTER, "return": KEY_ENTER,
	"escape": KEY_ESCAPE, "esc": KEY_ESCAPE,
	"tab": KEY_TAB, "backspace": KEY_BACKSPACE,
	"delete": KEY_DELETE, "space": KEY_SPACE,
	"up": KEY_UP, "down": KEY_DOWN,
	"left": KEY_LEFT, "right": KEY_RIGHT,
	"home": KEY_HOME, "end": KEY_END,
	"pageup": KEY_PAGEUP, "pagedown": KEY_PAGEDOWN,
	"f1": KEY_F1, "f2": KEY_F2, "f3": KEY_F3,
	"f4": KEY_F4, "f5": KEY_F5, "f6": KEY_F6,
	"f7": KEY_F7, "f8": KEY_F8, "f9": KEY_F9,
	"f10": KEY_F10, "f11": KEY_F11, "f12": KEY_F12,
}

var _c: Node


func _init(client_node: Node) -> void:
	_c = client_node


# --- Action endpoints ---

func endpoint_send_message(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	var content: String = args.get("content", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	if content.is_empty():
		return {"error": "content is required"}
	var reply_to: String = args.get("reply_to", "")
	var ok: bool = await _c.send_message_to_channel(
		channel_id, content, reply_to
	)
	return {"ok": ok}


func endpoint_edit_message(args: Dictionary) -> Dictionary:
	var message_id: String = args.get("message_id", "")
	var content: String = args.get("content", "")
	if message_id.is_empty():
		return {"error": "message_id is required"}
	if content.is_empty():
		return {"error": "content is required"}
	var ok: bool = await _c.update_message_content(
		message_id, content
	)
	return {"ok": ok}


func endpoint_delete_message(args: Dictionary) -> Dictionary:
	var message_id: String = args.get("message_id", "")
	if message_id.is_empty():
		return {"error": "message_id is required"}
	var ok: bool = await _c.remove_message(message_id)
	return {"ok": ok}


func endpoint_add_reaction(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	var message_id: String = args.get("message_id", "")
	var emoji_name: String = args.get("emoji", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	if message_id.is_empty():
		return {"error": "message_id is required"}
	if emoji_name.is_empty():
		return {"error": "emoji is required"}
	await _c.add_reaction(channel_id, message_id, emoji_name)
	return {"ok": true}


# --- Moderation endpoints ---

func endpoint_kick_member(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.kick_member(
		space_id, user_id
	)
	if result == null:
		return {"error": "Kick failed"}
	return {"ok": result.ok if result else false}


func endpoint_ban_user(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	var reason: String = args.get("reason", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.ban_user(
		space_id, user_id, reason
	)
	if result == null:
		return {"error": "Ban failed"}
	return {"ok": result.ok if result else false}


func endpoint_unban_user(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	var result: Variant = await _c.admin.unban_user(
		space_id, user_id
	)
	if result == null:
		return {"error": "Unban failed"}
	return {"ok": result.ok if result else false}


func endpoint_timeout_member(args: Dictionary) -> Dictionary:
	var space_id: String = args.get("space_id", "")
	var user_id: String = args.get("user_id", "")
	var duration: int = args.get("duration", 0)
	if space_id.is_empty():
		return {"error": "space_id is required"}
	if user_id.is_empty():
		return {"error": "user_id is required"}
	if duration <= 0:
		return {"error": "duration is required (seconds)"}
	var result: Variant = await _c.admin.timeout_member(
		space_id, user_id, duration
	)
	if result == null:
		return {"error": "Timeout failed"}
	return {"ok": result.ok if result else false}


# --- Voice endpoints ---

func endpoint_join_voice(args: Dictionary) -> Dictionary:
	var channel_id: String = args.get("channel_id", "")
	if channel_id.is_empty():
		return {"error": "channel_id is required"}
	var ok: bool = await _c.join_voice_channel(channel_id)
	return {"ok": ok}


func endpoint_leave_voice(_args: Dictionary) -> Dictionary:
	var ok: bool = await _c.leave_voice_channel()
	return {"ok": ok}


func endpoint_toggle_mute(_args: Dictionary) -> Dictionary:
	var new_state: bool = not AppState.is_voice_muted
	_c.set_voice_muted(new_state)
	return {"ok": true, "muted": new_state}


func endpoint_toggle_deafen(
	_args: Dictionary,
) -> Dictionary:
	var new_state: bool = not AppState.is_voice_deafened
	_c.set_voice_deafened(new_state)
	return {"ok": true, "deafened": new_state}


# --- Login / connection endpoints ---

func endpoint_login(args: Dictionary) -> Dictionary:
	var base_url: String = args.get("base_url", "")
	var token: String = args.get("token", "")
	if base_url.is_empty():
		return {"error": "base_url is required"}

	# Resolve token: either passed directly or via credentials
	var user_id_str := ""
	if token.is_empty():
		var auth_result: Dictionary = await _authenticate(
			base_url, args
		)
		if auth_result.has("error"):
			return auth_result
		token = auth_result.get("token", "")
		user_id_str = auth_result.get("user_id", "")

	# Connect to server and select the space
	return await _connect_with_token(
		base_url, token, user_id_str,
		args.get("username", ""),
	)


func _authenticate(
	base_url: String, args: Dictionary,
) -> Dictionary:
	var username: String = args.get("username", "")
	var password: String = args.get("password", "")
	var register_account: bool = args.get("register", false)
	if username.is_empty() or password.is_empty():
		return {"error": "username+password or token required"}

	var api_url: String = base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = ""
	rest.token_type = "Bearer"
	_c.add_child(rest)
	var auth := AuthApi.new(rest)

	var result: RestResult
	if register_account:
		result = await auth.register({
			"username": username, "password": password,
		})
	else:
		result = await auth.login({
			"username": username, "password": password,
		})
	rest.queue_free()

	if not result.ok:
		var err_msg: String = (
			result.error.message
			if result.error else "Auth failed"
		)
		return {"error": err_msg, "_status": result.status_code}

	var token: String = result.data.get("token", "")
	if token.is_empty():
		return {"error": "No token in response"}

	var uid := ""
	var user_obj: Variant = result.data.get("user")
	if user_obj is AccordUser:
		uid = user_obj.id
	elif user_obj is Dictionary:
		uid = str(user_obj.get("id", ""))
	return {"token": token, "user_id": uid}


func _connect_with_token(
	base_url: String, token: String,
	user_id_str: String, username: String,
) -> Dictionary:
	# Fetch spaces to find one to join
	var api_url: String = base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	rest.token = token
	rest.token_type = "Bearer"
	_c.add_child(rest)
	var users_api: UsersApi = UsersApi.new(rest)
	var spaces_result: RestResult = await users_api.list_spaces()
	rest.queue_free()

	if not spaces_result.ok or spaces_result.data.is_empty():
		return {"error": "No spaces found for user"}

	var space: AccordSpace = spaces_result.data[0]
	var space_name: String = (
		space.slug if not space.slug.is_empty() else space.name
	)

	Config.add_server(
		base_url, token, space_name, username, ""
	)
	var server_index: int = Config.get_servers().size() - 1
	var conn_result: Dictionary = await _c.connect_server(
		server_index
	)
	if conn_result.has("error"):
		return {"error": conn_result["error"]}

	var space_id: String = conn_result.get("space_id", "")
	if not space_id.is_empty():
		AppState.select_space(space_id)
		await _c.get_tree().process_frame

	if user_id_str.is_empty() and not _c.current_user.is_empty():
		user_id_str = _c.current_user.get("id", "")

	return {
		"ok": true, "user_id": user_id_str,
		"space_id": space_id, "token": token,
	}


# --- Input simulation endpoints ---

func endpoint_simulate_click(args: Dictionary) -> Dictionary:
	var x: int = args.get("x", -1)
	var y: int = args.get("y", -1)
	if x < 0 or y < 0:
		return {"error": "x and y coordinates are required"}
	var button: int = args.get("button", MOUSE_BUTTON_LEFT)
	var double_click: bool = args.get("double_click", false)
	var pos := Vector2(x, y)

	# Mouse button press
	var press := InputEventMouseButton.new()
	press.position = pos
	press.global_position = pos
	press.button_index = button
	press.pressed = true
	press.double_click = double_click
	Input.parse_input_event(press)
	await _c.get_tree().process_frame

	# Mouse button release
	var release := InputEventMouseButton.new()
	release.position = pos
	release.global_position = pos
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await _c.get_tree().process_frame

	return {"ok": true, "x": x, "y": y, "button": button}


func endpoint_simulate_key(args: Dictionary) -> Dictionary:
	var keycode_str: String = args.get("key", "")
	if keycode_str.is_empty():
		return {"error": "key is required (e.g. 'enter', 'escape', 'a')"}
	var shift: bool = args.get("shift", false)
	var ctrl: bool = args.get("ctrl", false)
	var alt: bool = args.get("alt", false)

	var keycode: Key = _parse_keycode(keycode_str)
	if keycode == KEY_NONE:
		return {"error": "Unknown key: %s" % keycode_str}

	var press := InputEventKey.new()
	press.keycode = keycode
	press.pressed = true
	press.shift_pressed = shift
	press.ctrl_pressed = ctrl
	press.alt_pressed = alt
	Input.parse_input_event(press)
	await _c.get_tree().process_frame

	var release := InputEventKey.new()
	release.keycode = keycode
	release.pressed = false
	release.shift_pressed = shift
	release.ctrl_pressed = ctrl
	release.alt_pressed = alt
	Input.parse_input_event(release)
	await _c.get_tree().process_frame

	return {"ok": true, "key": keycode_str}


func endpoint_simulate_text(args: Dictionary) -> Dictionary:
	var text: String = args.get("text", "")
	if text.is_empty():
		return {"error": "text is required"}

	# Send each character as a key event with unicode
	for i in text.length():
		var ch: String = text[i]
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		ev.keycode = KEY_NONE
		Input.parse_input_event(ev)
	await _c.get_tree().process_frame
	return {"ok": true, "length": text.length()}


func endpoint_simulate_mouse_move(args: Dictionary) -> Dictionary:
	var x: int = args.get("x", -1)
	var y: int = args.get("y", -1)
	if x < 0 or y < 0:
		return {"error": "x and y coordinates are required"}
	var pos := Vector2(x, y)

	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await _c.get_tree().process_frame

	return {"ok": true, "x": x, "y": y}


func _parse_keycode(name: String) -> Key:
	var lower: String = name.to_lower()
	if _KEY_MAP.has(lower):
		return _KEY_MAP[lower] as Key
	# Single character keys (A-Z, 0-9)
	if name.length() == 1:
		var code: int = name.to_upper().unicode_at(0)
		if (code >= 65 and code <= 90) \
				or (code >= 48 and code <= 57):
			return code as Key
	return KEY_NONE


# --- Lifecycle endpoints ---

func endpoint_wait_frames(args: Dictionary) -> Dictionary:
	var count: int = args.get("count", 1)
	count = clampi(count, 1, 60)
	for i in count:
		await _c.get_tree().process_frame
	return {"ok": true, "frames_waited": count}


func endpoint_quit(_args: Dictionary) -> Dictionary:
	var response := {"ok": true, "quitting": true}
	_c.get_tree().create_timer(0.1).timeout.connect(
		_c.get_tree().quit
	)
	return response
