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

# Keep JS callback alive so GC doesn't free it
var _cb_popstate


func _init(client_node: Node) -> void:
	_c = client_node
	_is_web = OS.get_name() == "Web"


func setup() -> void:
	if not _is_web:
		return
	_read_deep_link()
	_setup_popstate_listener()
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.thread_opened.connect(_on_thread_opened)
	AppState.thread_closed.connect(_on_thread_closed)
	AppState.channels_updated.connect(_on_channels_updated)


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


# --- Helpers ---

static func _js_escape(s: String) -> String:
	return s.replace("\\", "\\\\").replace("'", "\\'")
