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

	if token.is_empty():
		# No token -- show auth dialog to register or sign in
		var auth_dialog := AuthDialogScene.instantiate()
		auth_dialog.setup(url)
		auth_dialog.auth_completed.connect(
			func(resolved_url: String, t: String):
				_connect_with_token(resolved_url, guild_name, t, invite_code)
		)
		get_parent().add_child(auth_dialog)
	else:
		_connect_with_token(url, guild_name, token, invite_code)


func _connect_with_token(
	url: String, guild_name: String,
	token: String, invite_code: String,
) -> void:
	_add_btn.disabled = true
	_add_btn.text = "Connecting..."

	Config.add_server(url, token, guild_name)

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
