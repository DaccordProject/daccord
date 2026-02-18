extends ColorRect

signal server_added(guild_id: String)

const AuthDialogScene := preload("res://scenes/sidebar/guild_bar/auth_dialog.tscn")

@onready var _url_input: LineEdit = $CenterContainer/Panel/VBox/ServerUrlInput
@onready var _close_btn: Button = $CenterContainer/Panel/VBox/Header/CloseButton
@onready var _add_btn: Button = $CenterContainer/Panel/VBox/AddButton
@onready var _error_label: Label = $CenterContainer/Panel/VBox/ErrorLabel

func _ready() -> void:
	_close_btn.pressed.connect(_close)
	_url_input.text_submitted.connect(func(_t): _on_add_pressed())
	_add_btn.pressed.connect(_on_add_pressed)

	# Focus first input after a frame
	await get_tree().process_frame
	_url_input.grab_focus()

## Parses a server URL string into its components.
## Format: [protocol://]host[:port][#guild-name][?token=value&invite=code]
## Defaults: https protocol, port 39099, guild "general", no token, no invite.
static func parse_server_url(raw: String) -> Dictionary:
	var text := raw.strip_edges()
	var token := ""
	var guild_name := "general"
	var invite_code := ""

	# Extract query parameters (?token=...&invite=...)
	var q_pos := text.find("?")
	if q_pos != -1:
		var query_str := text.substr(q_pos + 1)
		text = text.substr(0, q_pos)
		for param in query_str.split("&"):
			var kv := param.split("=", true, 1)
			if kv.size() == 2 and kv[0] == "token":
				token = kv[1]
			elif kv.size() == 2 and kv[0] == "invite":
				invite_code = kv[1]

	# Extract #guild-name fragment
	var h_pos := text.find("#")
	if h_pos != -1:
		var name_part := text.substr(h_pos + 1)
		if not name_part.is_empty():
			guild_name = name_part
		text = text.substr(0, h_pos)

	# Add protocol if missing
	if not text.begins_with("http://") and not text.begins_with("https://"):
		text = "https://" + text

	# Add default port if not specified (check host portion only, before any /)
	var proto_end := text.find("://") + 3
	var after_proto := text.substr(proto_end)
	var host_port := after_proto.split("/")[0]
	if ":" not in host_port:
		var host_end := proto_end + host_port.length()
		text = text.substr(0, host_end) + ":39099" + text.substr(host_end)

	return {
		"base_url": text,
		"guild_name": guild_name,
		"token": token,
		"invite_code": invite_code,
	}

func _on_add_pressed() -> void:
	var raw := _url_input.text.strip_edges()

	if raw.is_empty():
		_show_error("Please enter a server URL.")
		return

	var parsed := parse_server_url(raw)
	var url: String = parsed["base_url"]
	var guild_name: String = parsed["guild_name"]
	var token: String = parsed["token"]
	var invite_code: String = parsed["invite_code"]

	_error_label.visible = false

	# Check if this server + guild is already configured
	var servers := Config.get_servers()
	for i in servers.size():
		var server: Dictionary = servers[i]
		var urls_match: bool = server["base_url"] == url
		if not urls_match:
			# Also check HTTP vs HTTPS variant
			var alt_url := url
			if alt_url.begins_with("https://"):
				alt_url = alt_url.replace("https://", "http://")
			elif alt_url.begins_with("http://"):
				alt_url = alt_url.replace("http://", "https://")
			urls_match = server["base_url"] == alt_url
		if urls_match and server["guild_name"] == guild_name:
			# If the server is in config but its connection failed, remove the
			# stale entry and let the user re-add it with fresh credentials.
			if Client.is_server_connected(i):
				_show_error("This server is already added.")
				return
			Config.remove_server(i)
			break

	# Probe the server to verify it's reachable before proceeding
	_add_btn.disabled = true
	_add_btn.text = "Checking..."
	var reachable := await _probe_server(url)
	if not reachable:
		_add_btn.disabled = false
		_add_btn.text = "Add"
		return

	_add_btn.disabled = false
	_add_btn.text = "Add"

	if token.is_empty():
		# No token -- show auth dialog to register or sign in
		var auth_dialog := AuthDialogScene.instantiate()
		auth_dialog.setup(url)
		auth_dialog.auth_completed.connect(
			func(resolved_url: String, t: String, u: String, p: String):
				_connect_with_token(resolved_url, guild_name, t, invite_code, u, p)
		)
		get_parent().add_child(auth_dialog)
	else:
		_connect_with_token(url, guild_name, token, invite_code)


## Makes a lightweight request to verify the server is reachable.
## Tries HTTPS first, then falls back to HTTP. Returns true if the server
## responded (any HTTP status is fine -- we just need a connection).
func _probe_server(url: String) -> bool:
	var api_url := url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	add_child(rest)

	# Try a GET to /auth/login -- doesn't need auth, will return 405 or similar
	# but any HTTP response means the server is there.
	var result := await rest.make_request("GET", "/auth/login")

	if not result.ok and result.status_code == 0 and url.begins_with("https://"):
		# Connection-level failure with HTTPS -- retry with HTTP (local dev servers)
		var http_url := url.replace("https://", "http://")
		rest.base_url = http_url + AccordConfig.API_BASE_PATH
		result = await rest.make_request("GET", "/auth/login")

	rest.queue_free()

	# status_code > 0 means we got an HTTP response (server is reachable)
	if result.status_code > 0:
		return true

	# Connection-level failure -- show the error from AccordRest
	var msg: String = result.error.message if result.error else "Could not reach server"
	_show_error(msg)
	return false


func _connect_with_token(
	url: String, guild_name: String,
	token: String, invite_code: String,
	username: String = "", password: String = "",
) -> void:
	_add_btn.disabled = true
	_add_btn.text = "Connecting..."

	Config.add_server(url, token, guild_name, username, password)

	var result: Dictionary = await Client.connect_server(Config.get_servers().size() - 1, invite_code)
	_add_btn.disabled = false
	_add_btn.text = "Add"

	if result.has("error"):
		Config.remove_server(Config.get_servers().size() - 1)
		_show_error(result["error"])
	else:
		server_added.emit(result.get("guild_id", ""))
		_close()

func _show_error(msg: String) -> void:
	_error_label.text = msg
	_error_label.visible = true

func _close() -> void:
	queue_free()

func _gui_input(event: InputEvent) -> void:
	# Close on backdrop click
	if event is InputEventMouseButton and event.pressed:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()
