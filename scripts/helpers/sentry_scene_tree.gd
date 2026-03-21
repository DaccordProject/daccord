class_name SentrySceneTree
extends SceneTree
## Custom MainLoop that initializes the Sentry SDK at the earliest possible
## point (_initialize), before any scenes or autoloads are loaded.  The
## before_send callback gates every event on user consent so no data leaves
## the device until the user explicitly opts in.
##
## Registered via Project Settings -> Application -> Run -> Main Loop Type.
## On platforms where the SentrySDK GDExtension is unavailable (web, headless)
## this class is still used as the main loop but skips SDK initialization.
##
## IMPORTANT: This script must NOT reference Sentry types (SentrySDK,
## SentryOptions, SentryEvent, SentryBreadcrumb) in type annotations
## because the GDExtension is excluded from web exports.  All Sentry
## access uses duck-typed Variant calls guarded by ClassDB checks.

const _SALT := "daccord-config-v1"
const _REGISTRY_PATH := "user://profile_registry.cfg"

static var initialized := false


func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not ClassDB.class_exists(&"SentrySDK"):
		return
	_init_sdk()


static func late_init() -> void:
	## Called by ErrorReporting when the user enables crash reporting
	## after startup (consent dialog).  If the SDK was already
	## initialized in _initialize() this is a no-op.
	if initialized:
		return
	if DisplayServer.get_name() == "headless":
		return
	if not ClassDB.class_exists(&"SentrySDK"):
		return
	_init_sdk()


static func _init_sdk() -> void:
	initialized = true
	# Use duck-typed access — no SentrySDK/SentryOptions type refs.
	var sdk = Engine.get_singleton(&"SentrySDK")
	if sdk == null:
		initialized = false
		return
	sdk.init(func(options) -> void:
		options.dsn = ProjectSettings.get_setting(
			"sentry/config/dsn", ""
		)
		options.before_send = _before_send
	)
	var version: String = ProjectSettings.get_setting(
		"application/config/version", "unknown"
	)
	sdk.set_tag("app_version", version)
	sdk.set_tag(
		"godot_version", Engine.get_version_info().string
	)
	sdk.set_tag("os", OS.get_name())
	sdk.set_tag("renderer", ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "unknown"
	))


static func _before_send(event) -> Variant:
	# Re-read consent at send time — the user may have toggled it
	# off after init.  Try Config autoload first, fall back to disk.
	var node = (
		Engine.get_singleton("Config")
		if Engine.has_singleton("Config")
		else null
	)
	var enabled: bool
	if (
		node != null
		and node.has_method("get_error_reporting_enabled")
	):
		enabled = node.get_error_reporting_enabled()
	else:
		enabled = _read_consent_from_disk()
	if not enabled:
		return null
	if event.environment.contains("editor"):
		return null
	_scrub_pii(event)
	return event


static func _scrub_pii(event) -> void:
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
	url_re.compile(
		"https?://[^\\s\"']+:\\d{2,5}[^\\s\"']*"
	)
	msg = url_re.sub(msg, "[URL REDACTED]", true)
	event.message = msg


## --- Helpers called by ErrorReporting ---

static func add_breadcrumb(
	message: String, category: String,
	type: String = "default",
) -> void:
	var sdk = Engine.get_singleton(&"SentrySDK")
	if sdk == null:
		return
	# SentryBreadcrumb.create() is a static factory — call via
	# ClassDB.instantiate() and set message property directly.
	var crumb = ClassDB.instantiate(&"SentryBreadcrumb")
	if crumb == null:
		return
	crumb.message = message
	crumb.category = category
	crumb.type = type
	sdk.add_breadcrumb(crumb)


static func set_tag(key: String, value: String) -> void:
	var sdk = Engine.get_singleton(&"SentrySDK")
	if sdk == null:
		return
	sdk.set_tag(key, value)


static func capture_message(
	description: String, level: int = -1,
) -> void:
	var sdk = Engine.get_singleton(&"SentrySDK")
	if sdk == null:
		return
	if level < 0:
		level = ClassDB.class_get_integer_constant(
			&"SentrySDK", &"LEVEL_INFO"
		)
	sdk.capture_message(description, level)


static func get_last_event_id() -> String:
	var sdk = Engine.get_singleton(&"SentrySDK")
	if sdk == null:
		return ""
	var val = sdk.get_last_event_id()
	return val if val != null else ""


static func _read_consent_from_disk() -> bool:
	# 1. Determine active profile slug from the registry
	var slug := "default"
	var registry := ConfigFile.new()
	if FileAccess.file_exists(_REGISTRY_PATH):
		if registry.load(_REGISTRY_PATH) == OK:
			slug = registry.get_value(
				"state", "active", "default"
			)

	# 2. Read the encrypted profile config
	var path := "user://profiles/%s/config.cfg" % slug
	if not FileAccess.file_exists(path):
		return false
	var config := ConfigFile.new()
	var key := _SALT
	var err := config.load_encrypted_pass(path, key)
	if err != OK:
		# Try legacy key (salt + data dir)
		var legacy_key := _SALT + OS.get_user_data_dir()
		err = config.load_encrypted_pass(path, legacy_key)
	if err != OK:
		# Try plain-text fallback (pre-encryption migration)
		err = config.load(path)
		if err != OK:
			return false

	# 3. Read the consent preference
	return config.get_value(
		"error_reporting", "enabled", false
	)
