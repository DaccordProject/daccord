extends Node

var _initialized := false

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if Config.get_error_reporting_enabled():
		init_sentry()

func init_sentry() -> void:
	if _initialized:
		return
	_initialized = true
	SentrySDK.init(func(options: SentryOptions) -> void:
		options.dsn = ProjectSettings.get_setting(
			"sentry/config/dsn", ""
		)
		options.before_send = _before_send
	)
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	SentrySDK.set_tag("app_version", version)
	SentrySDK.set_tag(
		"godot_version", Engine.get_version_info().string
	)
	SentrySDK.set_tag("os", OS.get_name())
	SentrySDK.set_tag("renderer", ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "unknown"
	))
	_connect_breadcrumbs()
	print("[ErrorReporting] Sentry SDK initialized")

func _before_send(event: SentryEvent) -> SentryEvent:
	if not Config.get_error_reporting_enabled():
		return null
	if event.environment.contains("editor"):
		return null
	_scrub_pii(event)
	return event

func _scrub_pii(event: SentryEvent) -> void:
	var msg: String = event.message
	if msg.is_empty():
		return
	event.message = scrub_pii_text(msg)

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
	AppState.guild_selected.connect(_on_guild_selected)
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

func _on_guild_selected(guild_id: String) -> void:
	_add_breadcrumb(
		"Switched guild: %s" % guild_id, "navigation"
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
	var crumb := SentryBreadcrumb.create(message)
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
	if not AppState.current_guild_id.is_empty():
		SentrySDK.set_tag(
			"guild_id", AppState.current_guild_id
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
