extends Node

## Handles daccord:// URI scheme for deep linking.
## Routes: connect, invite, navigate.

const AddServerDialogScene := preload(
	"res://scenes/sidebar/guild_bar/add_server_dialog.tscn"
)
const URI_IPC_FILE := "user://daccord.uri"
const IPC_POLL_INTERVAL := 0.5

var _ipc_timer: Timer

func _ready() -> void:
	_ensure_protocol_registered()

	# Process any --uri CLI arg
	var uri := _get_cli_uri()
	if not uri.is_empty():
		# Defer processing until Client has finished its startup connect flow
		call_deferred("_process_uri", uri)

	# Start IPC file watcher for URIs forwarded from duplicate instances
	_ipc_timer = Timer.new()
	_ipc_timer.wait_time = IPC_POLL_INTERVAL
	_ipc_timer.timeout.connect(_poll_ipc_file)
	add_child(_ipc_timer)
	_ipc_timer.start()


## Extracts --uri value from command-line arguments.
func _get_cli_uri() -> String:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--uri" and i + 1 < args.size():
			return args[i + 1]
		# macOS may pass the URI as a bare argument (Apple Event)
		if args[i].begins_with("daccord://"):
			return args[i]
	return ""


## Parses a daccord:// URI into a Dictionary.
## Returns empty Dictionary on invalid URI.
##
## Valid routes:
##   daccord://connect/<host>[:<port>][/<space-slug>][?token=<value>&invite=<code>]
##   daccord://invite/<code>@<host>[:<port>]
##   daccord://navigate/<space-id>[/<channel-id>]
static func parse_uri(uri: String) -> Dictionary:
	var text := uri.strip_edges()
	if not text.begins_with("daccord://"):
		return {}

	# Strip scheme
	text = text.substr("daccord://".length())
	if text.is_empty():
		return {}

	# Extract route (first path segment)
	var slash_pos := text.find("/")
	if slash_pos == -1:
		# No slash after route — route with no payload is invalid
		return {}

	var route := text.substr(0, slash_pos)
	var payload := text.substr(slash_pos + 1)

	if payload.is_empty():
		return {}

	match route:
		"connect":
			return _parse_connect(payload)
		"invite":
			return _parse_invite(payload)
		"navigate":
			return _parse_navigate(payload)
		_:
			return {}


static func _parse_connect(payload: String) -> Dictionary:
	var token := ""
	var invite_code := ""
	var channel_name := ""

	# Extract query parameters
	var q_pos := payload.find("?")
	if q_pos != -1:
		var query_str := payload.substr(q_pos + 1)
		payload = payload.substr(0, q_pos)
		for param in query_str.split("&"):
			var kv := param.split("=", true, 1)
			if kv.size() == 2:
				match kv[0]:
					"token":
						token = kv[1]
					"invite":
						invite_code = kv[1]
					"channel":
						channel_name = kv[1].uri_decode()

	# Split remaining into host[:port][/space-slug]
	var space_slug := "general"
	var slug_pos := payload.find("/")
	if slug_pos != -1:
		var slug_part := payload.substr(slug_pos + 1)
		if not slug_part.is_empty():
			space_slug = slug_part
		payload = payload.substr(0, slug_pos)

	if payload.is_empty():
		return {}

	# Parse host:port
	var host := payload
	var port := 443
	var colon_pos := payload.rfind(":")
	if colon_pos != -1:
		var port_str := payload.substr(colon_pos + 1)
		if port_str.is_valid_int():
			port = port_str.to_int()
			host = payload.substr(0, colon_pos)

	# Validate host is not empty and looks reasonable
	if host.is_empty() or not _is_valid_host(host):
		return {}

	var result := {
		"route": "connect",
		"host": host,
		"port": port,
		"space_slug": space_slug,
		"token": token,
		"invite_code": invite_code,
	}
	if not channel_name.is_empty():
		result["channel"] = channel_name
	return result


static func _parse_invite(payload: String) -> Dictionary:
	# Format: <code>@<host>[:<port>]
	var at_pos := payload.find("@")
	if at_pos == -1 or at_pos == 0:
		return {}

	var code := payload.substr(0, at_pos)
	var host_part := payload.substr(at_pos + 1)

	if host_part.is_empty():
		return {}

	# Validate invite code: alphanumeric only
	if not _is_alphanumeric(code):
		return {}

	# Parse host:port
	var host := host_part
	var port := 443
	var colon_pos := host_part.rfind(":")
	if colon_pos != -1:
		var port_str := host_part.substr(colon_pos + 1)
		if port_str.is_valid_int():
			port = port_str.to_int()
			host = host_part.substr(0, colon_pos)

	if host.is_empty() or not _is_valid_host(host):
		return {}

	return {
		"route": "invite",
		"invite_code": code,
		"host": host,
		"port": port,
	}


static func _parse_navigate(payload: String) -> Dictionary:
	# Format: <space-id>[/<channel-id>][?msg=<message-id>]
	var message_id := ""
	var q_pos := payload.find("?")
	if q_pos != -1:
		var query_str := payload.substr(q_pos + 1)
		payload = payload.substr(0, q_pos)
		for param in query_str.split("&"):
			var kv := param.split("=", true, 1)
			if kv.size() == 2 and kv[0] == "msg":
				message_id = kv[1]

	var parts := payload.split("/")
	if parts.is_empty() or parts[0].is_empty():
		return {}

	var result := {
		"route": "navigate",
		"space_id": parts[0],
	}

	if parts.size() > 1 and not parts[1].is_empty():
		result["channel_id"] = parts[1]

	if not message_id.is_empty():
		result["message_id"] = message_id

	return result


static func _is_alphanumeric(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)):
			return false
	return true


static func _is_valid_host(host: String) -> bool:
	# Basic validation: not empty, no spaces, no dangerous chars
	if host.is_empty() or host.contains(" ") or host.contains("'") or host.contains('"'):
		return false
	if host.contains("<") or host.contains(">") or host.contains(";"):
		return false
	return true


## Constructs a base_url from host and port for use with AddServerDialog/Client.
static func build_base_url(host: String, port: int) -> String:
	if port == 443:
		return "https://" + host
	return "https://" + host + ":" + str(port)


## Constructs a daccord://connect/ URL for sharing a space or channel.
static func build_connect_url(
	host: String, port: int, space_slug: String, channel_name: String = ""
) -> String:
	var url := "daccord://connect/" + host
	if port != 443:
		url += ":" + str(port)
	if not space_slug.is_empty():
		url += "/" + space_slug
	if not channel_name.is_empty():
		url += "?channel=" + channel_name.uri_encode()
	return url


## Constructs a daccord://navigate/ URL for sharing a message or channel link.
static func build_navigate_url(
	space_id: String, channel_id: String, message_id: String = ""
) -> String:
	var url := "daccord://navigate/" + space_id
	if not channel_id.is_empty():
		url += "/" + channel_id
	if not message_id.is_empty():
		url += "?msg=" + message_id
	return url


## Processes a parsed URI by dispatching to the appropriate handler.
func _process_uri(uri: String) -> void:
	var parsed := parse_uri(uri)
	if parsed.is_empty():
		push_warning("UriHandler: invalid URI: %s" % uri)
		return

	var route: String = parsed["route"]
	match route:
		"connect":
			_handle_connect(parsed)
		"invite":
			_handle_invite(parsed)
		"navigate":
			_handle_navigate(parsed)


func _handle_connect(parsed: Dictionary) -> void:
	var space_slug: String = parsed["space_slug"]
	var token: String = parsed["token"]
	var invite_code: String = parsed["invite_code"]
	var channel_name: String = parsed.get("channel", "")
	var host: String = parsed["host"]
	var port: int = parsed["port"]

	# Check if already connected to this server — navigate directly
	var base_url: String = build_base_url(host, port)
	for space in Client.spaces:
		var sid: String = space.get("id", "")
		var surl: String = Client.get_base_url_for_space(sid)
		if surl == base_url and space.get("slug", "") == space_slug:
			AppState.select_space(sid)
			if not channel_name.is_empty():
				_navigate_to_channel_by_name(sid, channel_name)
			return

	# Build a URL string the AddServerDialog can understand
	var url_str: String = host
	if port != 443:
		url_str += ":" + str(port)
	url_str += "#" + space_slug
	if not token.is_empty():
		url_str += "?token=" + token
		if not invite_code.is_empty():
			url_str += "&invite=" + invite_code
	elif not invite_code.is_empty():
		url_str += "?invite=" + invite_code

	# Token-bearing URIs get a confirmation dialog before proceeding
	if not token.is_empty():
		_confirm_token_connect(host, url_str)
		return

	_open_add_server_prefilled(url_str)


func _handle_invite(parsed: Dictionary) -> void:
	var host: String = parsed["host"]
	var port: int = parsed["port"]
	var code: String = parsed["invite_code"]

	# Check if already connected to this server — accept invite directly
	var base_url: String = build_base_url(host, port)
	for space in Client.spaces:
		var sid: String = space.get("id", "")
		var surl: String = Client.get_base_url_for_space(sid)
		if surl == base_url:
			_accept_invite_directly(sid, code)
			return

	# Not connected — open add server dialog with the invite code
	var url_str := host
	if port != 443:
		url_str += ":" + str(port)
	url_str += "?invite=" + code

	_open_add_server_prefilled(url_str)


func _handle_navigate(parsed: Dictionary) -> void:
	var space_id: String = parsed["space_id"]
	var channel_id: String = parsed.get("channel_id", "")
	var message_id: String = parsed.get("message_id", "")

	# Check if we're connected to this space
	var spaces := Client.spaces
	var found := false
	for space in spaces:
		if space["id"] == space_id:
			found = true
			break

	if not found:
		push_warning("UriHandler: not connected to space %s" % space_id)
		AppState.toast_requested.emit(tr("Space not found — not connected"))
		return

	AppState.select_space(space_id)
	if not channel_id.is_empty():
		AppState.select_channel(channel_id)
	if not message_id.is_empty():
		AppState.navigate_to_message.emit(channel_id, message_id)


## Finds a channel by name within a space and selects it.
func _navigate_to_channel_by_name(space_id: String, channel_name: String) -> void:
	for ch in Client.channels:
		if ch.get("space_id", "") == space_id and ch.get("name", "") == channel_name:
			AppState.select_channel(ch.get("id", ""))
			return
	push_warning("UriHandler: channel '%s' not found in space %s" % [channel_name, space_id])
	AppState.toast_requested.emit(tr("Channel not found"))


## Accepts an invite directly using an existing connection to the server.
func _accept_invite_directly(space_id: String, code: String) -> void:
	var accord_client: AccordClient = Client._client_for_space(space_id)
	if accord_client == null:
		push_warning("UriHandler: no client for space %s" % space_id)
		AppState.toast_requested.emit(tr("Failed to accept invite"))
		return

	var result: RestResult = await accord_client.invites.accept(code)
	if result.ok:
		AppState.toast_requested.emit(tr("Invite accepted!"))
	else:
		push_warning("UriHandler: invite accept failed: %s" % result.error_message)
		AppState.toast_requested.emit(tr("Failed to accept invite"))


## Shows a confirmation dialog before connecting with a token-bearing URI.
func _confirm_token_connect(host: String, url_str: String) -> void:
	var main_window := get_tree().root.get_node_or_null("MainWindow")
	if main_window == null:
		push_warning("UriHandler: MainWindow not found")
		return

	var dialog := ConfirmationDialog.new()
	dialog.title = tr("Connect to Server")
	dialog.dialog_text = tr("Connect to %s with an embedded token?\n\n" % host
		+ "Only proceed if you trust the source of this link.")
	dialog.ok_button_text = tr("Connect")
	dialog.confirmed.connect(func() -> void:
		_open_add_server_prefilled(url_str)
	)
	main_window.add_child(dialog)
	dialog.popup_centered()


## Opens the Add Server dialog with a pre-filled URL.
func _open_add_server_prefilled(url_text: String) -> void:
	var main_window := get_tree().root.get_node_or_null("MainWindow")
	if main_window == null:
		push_warning("UriHandler: MainWindow not found")
		return

	var dialog: ColorRect = AddServerDialogScene.instantiate()
	main_window.add_child(dialog)
	dialog.open_prefilled(url_text)


## Silently registers the daccord:// protocol handler if not already registered.
func _ensure_protocol_registered() -> void:
	if OS.has_feature("editor"):
		return
	var platform := OS.get_name()
	match platform:
		"Linux", "FreeBSD", "NetBSD", "OpenBSD":
			_ensure_protocol_linux()
		"Windows":
			_ensure_protocol_windows()


func _ensure_protocol_linux() -> void:
	var output: Array = []
	var exit_code := OS.execute(
		"xdg-mime", ["query", "default", "x-scheme-handler/daccord"], output
	)
	if exit_code == 0 and output.size() > 0:
		var result: String = output[0].strip_edges()
		if not result.is_empty():
			return

	# Find the executable path
	var exe_path := OS.get_executable_path()
	if exe_path.is_empty():
		return

	# Write .desktop file to ~/.local/share/applications/
	var apps_dir := OS.get_environment("HOME") + "/.local/share/applications"
	DirAccess.make_dir_recursive_absolute(apps_dir)
	var desktop_path := apps_dir + "/daccord.desktop"

	var content := "[Desktop Entry]\n"
	content += "Name=daccord\n"
	content += "Comment=Chat client for accordserver instances\n"
	content += "Exec=\"" + exe_path + "\" --uri %u\n"
	content += "Icon=daccord\n"
	content += "Terminal=false\n"
	content += "Type=Application\n"
	content += "Categories=Network;Chat;InstantMessaging;\n"
	content += "MimeType=x-scheme-handler/daccord;\n"

	var file := FileAccess.open(desktop_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(content)
	file.close()

	OS.execute("xdg-mime", [
		"default", "daccord.desktop", "x-scheme-handler/daccord"
	])


func _ensure_protocol_windows() -> void:
	var output: Array = []
	var exit_code := OS.execute("reg", [
		"query", "HKCU\\Software\\Classes\\daccord",
	], output)
	if exit_code == 0:
		return

	var exe_path := OS.get_executable_path().replace("/", "\\")
	if exe_path.is_empty():
		return

	OS.execute("reg", [
		"add", "HKCU\\Software\\Classes\\daccord",
		"/ve", "/d", "URL:daccord Protocol", "/f",
	])
	OS.execute("reg", [
		"add", "HKCU\\Software\\Classes\\daccord",
		"/v", "URL Protocol", "/d", "", "/f",
	])
	OS.execute("reg", [
		"add", "HKCU\\Software\\Classes\\daccord\\DefaultIcon",
		"/ve", "/d", exe_path + ",0", "/f",
	])
	OS.execute("reg", [
		"add", "HKCU\\Software\\Classes\\daccord\\shell\\open\\command",
		"/ve", "/d", "\"" + exe_path + "\" --uri \"%1\"", "/f",
	])


## Writes a URI to the IPC file so a running instance can pick it up.
static func write_ipc_uri(uri: String) -> void:
	var file := FileAccess.open(URI_IPC_FILE, FileAccess.WRITE)
	if file:
		file.store_string(uri)
		file.close()


## Polls for a URI in the IPC file (written by a duplicate instance).
func _poll_ipc_file() -> void:
	if not FileAccess.file_exists(URI_IPC_FILE):
		return

	var file := FileAccess.open(URI_IPC_FILE, FileAccess.READ)
	if file == null:
		return

	var uri := file.get_as_text().strip_edges()
	file.close()

	# Delete the IPC file immediately
	DirAccess.remove_absolute(ProjectSettings.globalize_path(URI_IPC_FILE))

	if not uri.is_empty():
		_process_uri(uri)
