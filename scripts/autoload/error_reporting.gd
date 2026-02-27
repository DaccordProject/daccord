extends Node

const _SENTRY_TREE := preload("res://scripts/sentry_scene_tree.gd")

var _initialized := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _SENTRY_TREE.initialized:
		_on_sdk_ready()
	elif _SENTRY_TREE._read_consent_from_disk():
		init_sentry()

## Called by the consent dialog (main_window.gd) when the user enables error
## reporting after startup. Delegates to SentrySceneTree.late_init() which
## calls SentrySDK.init() if it wasn't already initialized at startup.
func init_sentry() -> void:
	if _initialized:
		return
	_SENTRY_TREE.late_init()
	if _SENTRY_TREE.initialized:
		_on_sdk_ready()

func _on_sdk_ready() -> void:
	_initialized = true
	_connect_breadcrumbs()
	print("[ErrorReporting] Sentry SDK initialized")

func scrub_pii_text(msg: String) -> String:
	var token_re := RegEx.new()
	token_re.compile("Bearer\\s+[A-Za-z0-9._\\-]+")
	msg = token_re.sub(msg, "Bearer [REDACTED]", true)
	var param_re := RegEx.new()
	param_re.compile("token=[^&\\s\"']+")
	msg = param_re.sub(msg, "token=[REDACTED]", true)
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

func _on_space_selected(space_id: String) -> void:
	_add_breadcrumb(
		"Switched space: %s" % space_id, "navigation"
	)

func _on_channel_selected(channel_id: String) -> void:
	_add_breadcrumb(
		"Opened channel: %s" % channel_id, "navigation"
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
	var crumb := SentryBreadcrumb.create(scrubbed)
	crumb.category = category
	crumb.type = "default"
	SentrySDK.add_breadcrumb(crumb)

func update_context() -> void:
	if not _initialized:
		return
	SentrySDK.set_tag(
		"server_count",
		str(Config.get_servers().size())
	)
	if not AppState.current_space_id.is_empty():
		SentrySDK.set_tag(
			"space_id", AppState.current_space_id
		)
	if not AppState.current_channel_id.is_empty():
		SentrySDK.set_tag(
			"channel_id", AppState.current_channel_id
		)

func report_problem(description: String) -> void:
	if not _initialized:
		return
	update_context()
	var feedback := SentryFeedback.new()
	feedback.message = description
	SentrySDK.capture_feedback(feedback)
