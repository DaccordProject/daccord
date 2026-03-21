extends Node

var _sentry_tree = null # loaded dynamically; null on web
var _initialized := false
var _is_web := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_is_web = OS.has_feature("web")
	if _is_web:
		_try_init_web()
		return
	if not ClassDB.class_exists(&"SentrySDK"):
		return
	_sentry_tree = load("res://scripts/helpers/sentry_scene_tree.gd")
	if _sentry_tree == null:
		return
	if _sentry_tree.initialized:
		_on_sdk_ready()
	elif _sentry_tree._read_consent_from_disk():
		init_sentry()

func _try_init_web() -> void:
	if not Config.has_error_reporting_preference():
		return
	if Config.get_error_reporting_enabled():
		init_sentry()

## Called by the consent dialog (main_window.gd) when the user enables error
## reporting after startup. Delegates to SentrySceneTree.late_init() which
## calls SentrySDK.init() if it wasn't already initialized at startup.
## On web, initializes the JavaScript Sentry SDK instead.
func init_sentry() -> void:
	if _initialized:
		return
	if _is_web:
		_init_web_sentry()
		return
	if _sentry_tree == null:
		return
	_sentry_tree.late_init()
	if _sentry_tree.initialized:
		_on_sdk_ready()

func _init_web_sentry() -> void:
	var dsn: String = ProjectSettings.get_setting(
		"sentry/config/dsn", ""
	)
	if dsn.is_empty():
		return
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	var js := "window.daccordSentry && window.daccordSentry.init(%s, %s, %s)" % [
		JSON.stringify(dsn),
		JSON.stringify("web"),
		JSON.stringify("daccord@" + version),
	]
	JavaScriptBridge.eval(js)
	_on_sdk_ready()

func _on_sdk_ready() -> void:
	_initialized = true
	_connect_breadcrumbs()

func scrub_pii_text(msg: String) -> String:
	var token_re := RegEx.new()
	token_re.compile("Bearer\\s+[A-Za-z0-9._\\-]+")
	msg = token_re.sub(msg, "Bearer [REDACTED]", true)
	var param_re := RegEx.new()
	param_re.compile("token=[^&\\s\"']+")
	msg = param_re.sub(msg, "token=[REDACTED]", true)
	# Scrub hex-encoded developer tokens (test API / MCP)
	var hex_re := RegEx.new()
	hex_re.compile("dk_[0-9a-fA-F]{8,}")
	msg = hex_re.sub(msg, "[TOKEN REDACTED]", true)
	# Scrub bare 64-char hex strings (raw token values)
	var bare_hex_re := RegEx.new()
	bare_hex_re.compile("\\b[0-9a-fA-F]{64}\\b")
	msg = bare_hex_re.sub(msg, "[TOKEN REDACTED]", true)
	var url_re := RegEx.new()
	url_re.compile("https?://[^\\s\"']+:\\d{2,5}[^\\s\"']*")
	msg = url_re.sub(msg, "[URL REDACTED]", true)
	return msg

func _connect_breadcrumbs() -> void:
	AppState.space_selected.connect(_on_space_selected)
	AppState.channel_selected.connect(_on_channel_selected)
	AppState.dm_mode_entered.connect(_on_dm_mode_entered)
	AppState.message_sent.connect(_on_message_sent)
	AppState.reply_initiated.connect(_on_reply_initiated)
	AppState.layout_mode_changed.connect(
		_on_layout_mode_changed
	)
	AppState.sidebar_drawer_toggled.connect(
		_on_sidebar_drawer_toggled
	)
	AppState.voice_error.connect(_on_voice_error)

func _truncate_id(id: String) -> String:
	if id.length() <= 4:
		return id
	return "…" + id.right(4)

func _on_space_selected(space_id: String) -> void:
	_add_breadcrumb(
		"Switched space: %s" % _truncate_id(space_id), "navigation"
	)

func _on_channel_selected(channel_id: String) -> void:
	_add_breadcrumb(
		"Opened channel: %s" % _truncate_id(channel_id), "navigation"
	)

func _on_dm_mode_entered() -> void:
	_add_breadcrumb("Entered DM mode", "navigation")

func _on_message_sent(_text: String) -> void:
	_add_breadcrumb("Sent message", "action")

func _on_reply_initiated(_message_id: String) -> void:
	_add_breadcrumb("Started reply", "action")

func _on_layout_mode_changed(mode: AppState.LayoutMode) -> void:
	var mode_name: String
	match mode:
		AppState.LayoutMode.COMPACT:
			mode_name = "COMPACT"
		AppState.LayoutMode.MEDIUM:
			mode_name = "MEDIUM"
		_:
			mode_name = "FULL"
	_add_breadcrumb("Layout: %s" % mode_name, "ui")

func _on_sidebar_drawer_toggled(_is_open: bool) -> void:
	_add_breadcrumb("Sidebar toggled", "ui")

func _on_voice_error(error: String) -> void:
	_add_breadcrumb("Voice error: %s" % error, "voice")

func _add_breadcrumb(
	message: String, category: String
) -> void:
	if not _initialized:
		return
	var scrubbed := scrub_pii_text(message)
	if _is_web:
		_web_call(
			"addBreadcrumb(%s, %s)"
			% [JSON.stringify(scrubbed), JSON.stringify(category)]
		)
	else:
		_sentry_tree.add_breadcrumb(scrubbed, category)

func update_context() -> void:
	if not _initialized:
		return
	var server_count := str(Config.get_servers().size())
	if _is_web:
		_web_call("setTag('server_count', %s)" % JSON.stringify(
			server_count
		))
	else:
		_sentry_tree.set_tag("server_count", server_count)
	if not AppState.current_space_id.is_empty():
		var sid := _truncate_id(AppState.current_space_id)
		if _is_web:
			_web_call(
				"setTag('space_id', %s)" % JSON.stringify(sid)
			)
		else:
			_sentry_tree.set_tag("space_id", sid)
	if not AppState.current_channel_id.is_empty():
		var cid := _truncate_id(AppState.current_channel_id)
		if _is_web:
			_web_call(
				"setTag('channel_id', %s)" % JSON.stringify(cid)
			)
		else:
			_sentry_tree.set_tag("channel_id", cid)

func get_last_event_id() -> String:
	if not _initialized or _sentry_tree == null:
		return ""
	return _sentry_tree.get_last_event_id()

func report_problem(description: String) -> void:
	if not _initialized:
		return
	update_context()
	if _is_web:
		_web_call("setTag('type', 'user-feedback')")
		var scrubbed := scrub_pii_text(description)
		_web_call(
			"captureMessage(%s, 'info')"
			% JSON.stringify(scrubbed)
		)
	else:
		_sentry_tree.set_tag("type", "user-feedback")
		_sentry_tree.capture_message(description)

func _web_call(method_and_args: String) -> void:
	JavaScriptBridge.eval(
		"window.daccordSentry && window.daccordSentry."
		+ method_and_args
	)
