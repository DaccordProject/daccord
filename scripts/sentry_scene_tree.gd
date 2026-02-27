class_name SentrySceneTree
extends RefCounted
## Sentry SDK initialization helper. Provides consent reading from encrypted
## config on disk, SDK initialization, before_send filtering, and PII
## scrubbing. Called by the ErrorReporting autoload at startup or via the
## consent dialog — not used as a custom MainLoop.

const _SALT := "daccord-config-v1"
const _REGISTRY_PATH := "user://profile_registry.cfg"

static var initialized := false


static func late_init() -> void:
	if initialized:
		return
	if DisplayServer.get_name() == "headless":
		return
	_init_sdk()


static func _init_sdk() -> void:
	initialized = true
	SentrySDK.init(func(options: SentryOptions) -> void:
		options.dsn = ProjectSettings.get_setting("sentry/config/dsn", "")
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
	print("[SentrySceneTree] Sentry SDK initialized")


static func _before_send(event: SentryEvent) -> SentryEvent:
	# Re-read consent at send time — the user may have toggled it off after
	# init. We read from the Config autoload if available, otherwise from
	# disk as a fallback.
	var node: Node = Engine.get_singleton("Config") if Engine.has_singleton("Config") else null
	var enabled: bool
	if node != null and node.has_method("get_error_reporting_enabled"):
		enabled = node.get_error_reporting_enabled()
	else:
		enabled = _read_consent_from_disk()
	if not enabled:
		return null
	if event.environment.contains("editor"):
		return null
	_scrub_pii(event)
	return event


static func _scrub_pii(event: SentryEvent) -> void:
	var msg: String = event.message
	if msg.is_empty():
		return
	var token_re := RegEx.new()
	token_re.compile("Bearer\\s+[A-Za-z0-9._\\-]+")
	msg = token_re.sub(msg, "Bearer [REDACTED]", true)
	var param_re := RegEx.new()
	param_re.compile("token=[^&\\s\"']+")
	msg = param_re.sub(msg, "token=[REDACTED]", true)
	var url_re := RegEx.new()
	url_re.compile("https?://[^\\s\"']+:\\d{2,5}[^\\s\"']*")
	msg = url_re.sub(msg, "[URL REDACTED]", true)
	event.message = msg


static func _read_consent_from_disk() -> bool:
	# 1. Determine active profile slug from the registry
	var slug := "default"
	var registry := ConfigFile.new()
	if FileAccess.file_exists(_REGISTRY_PATH):
		if registry.load(_REGISTRY_PATH) == OK:
			slug = registry.get_value("state", "active", "default")

	# 2. Read the encrypted profile config
	var path := "user://profiles/%s/config.cfg" % slug
	if not FileAccess.file_exists(path):
		return false
	var config := ConfigFile.new()
	var key := _SALT + OS.get_user_data_dir()
	var err := config.load_encrypted_pass(path, key)
	if err != OK:
		# Try plain-text fallback (pre-encryption migration)
		err = config.load(path)
		if err != OK:
			return false

	# 3. Read the consent preference
	return config.get_value("error_reporting", "enabled", false)
