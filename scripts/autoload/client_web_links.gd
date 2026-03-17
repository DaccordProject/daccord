class_name ClientWebLinks
extends RefCounted

## Manages shareable URL fragment routing on web exports.
## Parses deep links on startup, updates the browser URL as the user navigates,
## and handles browser back/forward (popstate) events.
##
## URL format: #<space-slug>/<channel-name>[/<post-id>]
##
## On non-web builds all methods are no-ops.

var _c: Node # Client autoload
var _is_web: bool = false

# Deep link parsed on startup (before connection)
var _deep_link_space: String = ""
var _deep_link_channel: String = ""
var _deep_link_post_id: String = ""
var _deep_link_pending: bool = false

# Preset server config read from window.daccordPresetServer
var _preset_base_url: String = ""
var _preset_space_slug: String = ""

# Keep JS callback alive so GC doesn't free it
var _cb_popstate


func _init(client_node: Node) -> void:
	_c = client_node
	_is_web = OS.get_name() == "Web"


func setup() -> void:
	if not _is_web:
		return
	_read_deep_link()
	_read_preset_server()
	_setup_popstate_listener()
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.channels_updated.connect(_on_channels_updated)
	AppState.guest_mode_changed.connect(_on_guest_mode_changed)


## Checks localStorage for an existing auth token, or auto-connects as
## guest via the preset server. Returns true if a connection was initiated.
func try_auto_connect() -> bool:
	if not _is_web:
		return false
	# 1. Check localStorage for a previously saved auth token
	var stored: String = _read_local_storage("daccord_auth_token")
	if not stored.is_empty():
		var json := JSON.new()
		if json.parse(stored) == OK and json.data is Dictionary:
			var d: Dictionary = json.data
			var base_url: String = d.get("base_url", "")
			var token: String = d.get("token", "")
			var space: String = d.get("space_name", "")
			var username: String = d.get("username", "")
			var display_name: String = d.get("display_name", "")
			if not token.is_empty() and not base_url.is_empty():
				Config.add_server(
					base_url, token, space, username,
					display_name,
				)
				var idx: int = Config.get_servers().size() - 1
				_c.connect_server(idx)
				return true
	# 2. If no auth token, try auto-guest via preset server
	if _preset_base_url.is_empty():
		return false
	_auto_guest_connect()
	return true


# --- Preset server ---

## Reads window.daccordPresetServer from the HTML shell.
## If base_url is omitted, defaults to window.location.origin.
func _read_preset_server() -> void:
	var result = JavaScriptBridge.eval(
		"(function(){"
		+ "var ps=window.daccordPresetServer;"
		+ "if(!ps)return null;"
		+ "var bu=ps.base_url||window.location.origin;"
		+ "return JSON.stringify({base_url:bu,space_slug:ps.space_slug||''})"
		+ "})()", true
	)
	if result == null:
		return
	var json := JSON.new()
	if json.parse(str(result)) != OK:
		return
	var data = json.data
	if not data is Dictionary:
		return
	_preset_base_url = data.get("base_url", "")
	_preset_space_slug = data.get("space_slug", "")


## Silently connects as a guest to the preset server. No user interaction.
func _auto_guest_connect() -> void:
	if _preset_base_url.is_empty():
		return
	var api_url := _preset_base_url + AccordConfig.API_BASE_PATH
	var rest := AccordRest.new(api_url)
	_c.add_child(rest)
	var auth := AuthApi.new(rest)
	var result: RestResult = await auth.guest()
	rest.queue_free()

	if not result.ok:
		push_warning("[WebLinks] Auto-guest failed: ",
			result.error.message if result.error else "unknown")
		return

	var token: String = result.data.get("token", "")
	var space_id: String = result.data.get("space_id", "")
	var expires_at: String = result.data.get("expires_at", "")

	if token.is_empty() or space_id.is_empty():
		push_warning("[WebLinks] Auto-guest: missing token or space_id")
		return

	# Store guest token in sessionStorage (transient)
	_write_session_storage("daccord_guest_token", token)

	_c.connect_guest(_preset_base_url, token, space_id, expires_at)


# --- Deep link (startup) ---

func _read_deep_link() -> void:
	var result = JavaScriptBridge.eval(
		"(function(){"
		+ "var h=window.location.hash;"
		+ "if(!h||h.length<2)return null;"
		+ "var p=h.substring(1).split('/');"
		+ "return JSON.stringify({space:p[0]||'',channel:p[1]||'',postId:p[2]||''})"
		+ "})()", true
	)
	if result == null:
		return
	var json := JSON.new()
	if json.parse(str(result)) != OK:
		return
	var data = json.data
	if not data is Dictionary:
		return
	_deep_link_space = data.get("space", "")
	_deep_link_channel = data.get("channel", "")
	_deep_link_post_id = data.get("postId", "")
	if not _deep_link_space.is_empty():
		_deep_link_pending = true
		# Store on window so index.html popstate handler knows
		# the initial deep link was consumed
		JavaScriptBridge.eval(
			"window.daccordDeepLink={space:'%s',channel:'%s',postId:'%s'}"
			% [
				_js_escape(_deep_link_space),
				_js_escape(_deep_link_channel),
				_js_escape(_deep_link_post_id),
			], true
		)


func get_deep_link() -> Dictionary:
	if not _deep_link_pending:
		return {}
	return {
		"space": _deep_link_space,
		"channel": _deep_link_channel,
		"post_id": _deep_link_post_id,
	}


## Called when channels are loaded after connection. Attempts to navigate
## to the deep link target if one is pending.
func _on_channels_updated(_space_id: String) -> void:
	if not _deep_link_pending:
		return
	_navigate_to_deep_link()


func _navigate_to_deep_link() -> void:
	if not _deep_link_pending:
		return
	# Find the target space by slug
	var target_space_id := ""
	for space in _c._space_cache.values():
		var slug: String = space.get("slug", "")
		if slug == _deep_link_space:
			target_space_id = space.get("id", "")
			break
	if target_space_id.is_empty():
		# Space not found (yet) -- keep pending
		return
	# Select the space
	if AppState.current_space_id != target_space_id:
		AppState.select_space(target_space_id)
	# Find the target channel by name
	if _deep_link_channel.is_empty():
		_deep_link_pending = false
		return
	var target_channel_id := ""
	for ch in _c._channel_cache.values():
		if ch.get("space_id", "") != target_space_id:
			continue
		if ch.get("name", "") == _deep_link_channel:
			target_channel_id = ch.get("id", "")
			break
	if target_channel_id.is_empty():
		# Channel not found -- clear pending, space is selected
		_deep_link_pending = false
		return
	_deep_link_pending = false
	AppState.select_channel(target_channel_id)
	# If a post ID was specified, open the thread
	if not _deep_link_post_id.is_empty():
		AppState.open_thread(_deep_link_post_id)


# --- URL updates on navigation ---

func _on_channel_selected(channel_id: String) -> void:
	if not _is_web:
		return
	_update_url_for_channel(channel_id)


func _on_thread_opened(parent_message_id: String) -> void:
	if not _is_web:
		return
	var channel_id: String = AppState.current_channel_id
	_update_url_for_channel(channel_id, parent_message_id)


func _on_thread_closed() -> void:
	if not _is_web:
		return
	var channel_id: String = AppState.current_channel_id
	if not channel_id.is_empty():
		_update_url_for_channel(channel_id)


func _update_url_for_channel(
	channel_id: String, post_id: String = ""
) -> void:
	if channel_id.is_empty():
		return
	var ch: Dictionary = _c._channel_cache.get(channel_id, {})
	if ch.is_empty():
		return
	var space_id: String = ch.get("space_id", "")
	var channel_name: String = ch.get("name", "")
	var space: Dictionary = _c._space_cache.get(space_id, {})
	var space_slug: String = space.get("slug", "")
	if space_slug.is_empty() or channel_name.is_empty():
		return
	var fragment: String = space_slug + "/" + channel_name
	if not post_id.is_empty():
		fragment += "/" + post_id
	_push_url_fragment(fragment)


func _push_url_fragment(fragment: String) -> void:
	var safe: String = _js_escape(fragment)
	JavaScriptBridge.eval(
		"history.replaceState(null,'','#%s')" % safe, true
	)


# --- Browser back/forward (popstate) ---

func _setup_popstate_listener() -> void:
	_cb_popstate = JavaScriptBridge.create_callback(_on_popstate)
	var win: JavaScriptObject = JavaScriptBridge.get_interface("window")
	win._daccordPopStateCb = _cb_popstate
	JavaScriptBridge.eval(
		"window.addEventListener('popstate',function(){"
		+ "var h=window.location.hash;"
		+ "var p=(h&&h.length>1)?h.substring(1).split('/'):[];"
		+ "window._daccordPopStateCb(JSON.stringify("
		+ "{space:p[0]||'',channel:p[1]||'',postId:p[2]||''}))"
		+ "})", true
	)


func _on_popstate(args) -> void:
	if args is Array and args.size() > 0:
		var json := JSON.new()
		if json.parse(str(args[0])) != OK:
			return
		var data = json.data
		if not data is Dictionary:
			return
		var space_slug: String = data.get("space", "")
		var channel_name: String = data.get("channel", "")
		var post_id: String = data.get("postId", "")
		_navigate_by_slug(space_slug, channel_name, post_id)


func _navigate_by_slug(
	space_slug: String, channel_name: String, post_id: String
) -> void:
	if space_slug.is_empty():
		return
	# Find space
	var target_space_id := ""
	for space in _c._space_cache.values():
		if space.get("slug", "") == space_slug:
			target_space_id = space.get("id", "")
			break
	if target_space_id.is_empty():
		return
	if AppState.current_space_id != target_space_id:
		AppState.select_space(target_space_id)
	if channel_name.is_empty():
		return
	# Find channel
	var target_channel_id := ""
	for ch in _c._channel_cache.values():
		if ch.get("space_id", "") != target_space_id:
			continue
		if ch.get("name", "") == channel_name:
			target_channel_id = ch.get("id", "")
			break
	if target_channel_id.is_empty():
		return
	AppState.select_channel(target_channel_id)
	if not post_id.is_empty():
		AppState.open_thread(post_id)
	elif AppState.thread_panel_visible:
		AppState.close_thread()


# --- Auth token persistence ---

## Called when guest mode changes. After sign-in/register (is_guest=false),
## persist the auth token to localStorage so future visits skip guest flow.
func _on_guest_mode_changed(is_guest: bool) -> void:
	if not _is_web:
		return
	if is_guest:
		return
	# Guest mode ended — user upgraded to authenticated.
	# Remove the guest token from sessionStorage.
	_remove_session_storage("daccord_guest_token")
	# Persist auth token to localStorage for future visits.
	_persist_auth_token()


func _persist_auth_token() -> void:
	# Find the most recently added server config and persist its credentials
	var servers: Array = Config.get_servers()
	if servers.is_empty():
		return
	var latest: Dictionary = servers[servers.size() - 1]
	var data := {
		"base_url": latest.get("base_url", ""),
		"token": latest.get("token", ""),
		"space_name": latest.get("space_name", ""),
		"username": latest.get("username", ""),
		"display_name": latest.get("display_name", ""),
	}
	_write_local_storage("daccord_auth_token", JSON.stringify(data))


# --- Web storage helpers ---

static func _read_local_storage(key: String) -> String:
	var result = JavaScriptBridge.eval(
		"localStorage.getItem('%s')||''" % _js_escape(key), true
	)
	return str(result) if result != null else ""


static func _write_local_storage(key: String, value: String) -> void:
	JavaScriptBridge.eval(
		"localStorage.setItem('%s','%s')"
		% [_js_escape(key), _js_escape(value)], true
	)


static func _remove_local_storage(key: String) -> void:
	JavaScriptBridge.eval(
		"localStorage.removeItem('%s')" % _js_escape(key), true
	)


static func _write_session_storage(key: String, value: String) -> void:
	JavaScriptBridge.eval(
		"sessionStorage.setItem('%s','%s')"
		% [_js_escape(key), _js_escape(value)], true
	)


static func _remove_session_storage(key: String) -> void:
	JavaScriptBridge.eval(
		"sessionStorage.removeItem('%s')" % _js_escape(key), true
	)


# --- Helpers ---

static func _js_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'")
