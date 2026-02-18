# Error Reporting

*Last touched: 2026-02-18 20:21*

## Overview

This flow describes how daccord reports crashes, script errors, and diagnostic data to a self-hosted [GlitchTip](https://glitchtip.com/) instance using the [Sentry Godot SDK](https://github.com/getsentry/sentry-godot). GlitchTip is a Sentry-compatible open-source error tracking platform, so the SDK's DSN simply points at the GlitchTip server instead of Sentry's cloud. The goal is automatic, opt-in error reporting that gives developers visibility into real-world crashes without requiring users to manually file bug reports.

None of this is implemented yet. This document serves as a UX specification.

## User Steps

### First Launch (Consent)

1. User launches daccord for the first time (or after a fresh config reset).
2. A dialog appears: "Help improve daccord by sending anonymous crash and error reports? No personal data is included. You can change this in Settings at any time." [Enable] [No thanks]
3. **Enable:** Error reporting is turned on. The Sentry SDK initializes on all subsequent launches. Config saves `error_reporting_enabled = true`.
4. **No thanks:** Error reporting stays disabled. The SDK is never initialized. Config saves `error_reporting_enabled = false`.
5. The dialog does not appear again unless config is reset.

### Automatic Error Capture (Background)

1. User uses daccord normally.
2. A GDScript error, crash, or unhandled exception occurs at runtime.
3. The Sentry SDK automatically captures the error with:
   - Error message and type (script error, shader error, crash).
   - GDScript stack trace with file paths and line numbers.
   - Breadcrumbs (recent user actions leading up to the error).
   - Environment info: OS, Godot version, app version, renderer.
   - Current context: connected server count, active guild/channel IDs (no message content).
4. The event is sent to the GlitchTip server via the DSN.
5. The user is not interrupted. No popup or toast appears for automatic captures.

### Crash Recovery

1. daccord crashes (native crash, out of memory, GPU driver fault).
2. The Sentry native SDK writes a crash dump to disk.
3. On next launch, the SDK detects the unsent crash report and uploads it to GlitchTip.
4. A subtle toast appears: "A crash report from your last session was sent." (Only if error reporting is enabled.)

### User-Initiated Feedback

1. User encounters a bug and wants to report it manually.
2. User opens the user bar menu and selects "Report a Problem".
3. A dialog appears with a text field: "Describe what happened (optional):" and buttons [Send Report] [Cancel].
4. **Send Report:** The SDK captures a manual event (`SentrySDK.capture_message()`) with the user's description as an attachment. A breadcrumb trail of recent actions is included. Toast: "Report sent. Thank you!"
5. **Cancel:** Dialog closes. No event is sent.

### Toggling Error Reporting (Settings)

1. User opens the user bar menu and selects "Settings" (or "About").
2. A toggle is visible: "Send anonymous error reports" with an on/off switch.
3. Toggling off stops the SDK from sending events. Already-queued events are discarded.
4. Toggling on re-enables the SDK. Takes effect immediately (no restart needed).
5. A small info label below the toggle: "Crash and error data only. No messages, usernames, or personal info is ever sent."

## Signal Flow

```
Startup (error reporting enabled):
  Client._ready()
    -> Config.get_error_reporting_enabled()
    -> If true:
      -> SentrySDK initializes automatically (auto_init in project.godot)
      -> DSN points to GlitchTip instance
      -> SentrySDK.configure_scope():
        -> Sets tag "app_version" from project.godot version
        -> Sets tag "server_count" from Config.get_servers().size()
        -> Sets environment ("export_release" or "export_debug")
    -> If false:
      -> SentrySDK does not initialize (auto_init disabled, manual init skipped)

First Launch Consent:
  main_window._ready()
    -> Config.has_error_reporting_preference() == false
    -> Shows consent dialog
    -> User clicks [Enable]:
      -> Config.set_error_reporting_enabled(true)
      -> SentrySDK.init()  # manual init since auto_init was skipped
    -> User clicks [No thanks]:
      -> Config.set_error_reporting_enabled(false)

Runtime Error Captured (automatic):
  GDScript error / crash occurs
    -> Sentry logger integration captures error
    -> Breadcrumbs (recent prints, signals) attached automatically
    -> before_send callback:
      -> Strips any PII (user tokens, message content, server URLs)
      -> Adds tags: guild_id, channel_id (IDs only, not names)
    -> Event sent to GlitchTip DSN

Manual Report:
  user_bar._on_menu_id_pressed(13)  # "Report a Problem"
    -> Shows feedback dialog
    -> User enters description, clicks [Send Report]
    -> SentrySDK.capture_message(description, SentrySDK.LEVEL_INFO)
    -> Toast: "Report sent. Thank you!"

Toggle Setting:
  settings_dialog._on_error_reporting_toggled(enabled)
    -> Config.set_error_reporting_enabled(enabled)
    -> If enabled: SentrySDK.init()
    -> If disabled: SDK stops sending (next launch will skip init)
```

## Key Files

| File | Role |
|------|------|
| `addons/sentry/` | Sentry Godot SDK addon (GDExtension). Downloaded from [GitHub releases](https://github.com/getsentry/sentry-godot/releases/). |
| `project.godot` | Sentry SDK configuration: DSN, environment, sample rate, `auto_init`, breadcrumb settings. Also `config/version` for release tracking. |
| `scripts/autoload/config.gd` | Persists `error_reporting_enabled` preference under an `[error_reporting]` config section. |
| `scripts/autoload/client.gd` | Sets Sentry scope context (server count, connection status) after connections are established. Calls `SentrySDK.add_breadcrumb()` on key events (guild switch, channel switch, message send). |
| `scripts/autoload/app_state.gd` | Breadcrumb source. Key signals (`guild_selected`, `channel_selected`, `message_sent`) are hooked to add Sentry breadcrumbs for error context. |
| `scenes/main/main_window.gd` | Hosts the first-launch consent dialog. Shows crash recovery toast. |
| `scenes/sidebar/user_bar.gd` | Adds "Report a Problem" menu item. Hosts the feedback dialog. |

## Implementation Details

### GlitchTip Server Setup

GlitchTip runs as a Docker Compose deployment alongside (or near) the accordserver infrastructure. Minimum requirements: 512 MB RAM, PostgreSQL 14+.

**Docker Compose (minimal):**
```yaml
# compose.yml for GlitchTip
services:
  web:
    image: glitchtip/glitchtip
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgres://glitchtip:password@postgres:5432/glitchtip
      SECRET_KEY: <random-secret>
      GLITCHTIP_DOMAIN: https://errors.example.com
      DEFAULT_FROM_EMAIL: errors@example.com
      GLITCHTIP_MAX_EVENT_LIFE_DAYS: 90
      ENABLE_USER_REGISTRATION: "false"
    depends_on:
      - postgres
  worker:
    image: glitchtip/glitchtip
    command: bin/run-celery-with-beat.sh
    environment:
      DATABASE_URL: postgres://glitchtip:password@postgres:5432/glitchtip
      SECRET_KEY: <random-secret>
    depends_on:
      - postgres
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: glitchtip
      POSTGRES_USER: glitchtip
      POSTGRES_PASSWORD: password
    volumes:
      - pg-data:/var/lib/postgresql/data

volumes:
  pg-data:
```

After deploying, create an organization and project in the GlitchTip web UI. The project's DSN (e.g., `https://key@errors.example.com/1`) is what goes into the Sentry SDK config.

### Sentry SDK Installation

1. Download `sentry-godot` from [GitHub releases](https://github.com/getsentry/sentry-godot/releases/) (v1.x requires Godot 4.5+).
2. Extract `addons/sentry/` into the project root.
3. The SDK is a GDExtension (C++ native library), not a GDScript plugin. No `plugin.cfg` entry needed in `editor_plugins` -- it auto-registers.

### SDK Configuration (project.godot)

The Sentry SDK reads its settings from `project.godot` under the `[sentry]` section:

```ini
[sentry]
config/dsn="https://<key>@errors.example.com/<project-id>"
config/auto_init=false
config/debug=false
config/environment="{auto}"
config/sample_rate=1.0
config/max_breadcrumbs=100
config/send_default_pii=false
config/attach_log=true
config/attach_screenshot=false
logger/enabled=true
logger/event_mask=5
logger/breadcrumb_mask=7
logger/include_source=true
```

Key choices:
- **`auto_init = false`**: We manage initialization manually so we can check the user's consent preference first.
- **`send_default_pii = false`**: Never send PII automatically.
- **`attach_log = true`**: Godot's log file is attached to events (useful for reproducing issues).
- **`attach_screenshot = false`**: Screenshots could contain private messages. Disabled.
- **`sample_rate = 1.0`**: Send all errors. For high user counts, reduce to 0.5 or lower.

### Manual Initialization

Since `auto_init` is `false`, the SDK must be initialized in code after checking consent:

```gdscript
# In client.gd or a dedicated error_reporting.gd autoload
func _ready() -> void:
    if Config.get_error_reporting_enabled():
        _init_sentry()

func _init_sentry() -> void:
    SentrySDK.init()
    # Set release from project.godot version
    var version: String = ProjectSettings.get_setting("application/config/version", "unknown")
    SentrySDK.set_tag("app_version", version)
    SentrySDK.set_tag("godot_version", Engine.get_version_info().string)
    SentrySDK.set_tag("os", OS.get_name())
    SentrySDK.set_tag("renderer", ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
```

### Privacy: before_send Filtering

A `before_send` callback strips sensitive data before events reach GlitchTip:

```gdscript
func _before_send(event: SentryEvent) -> SentryEvent:
    # Remove server URLs and tokens from breadcrumbs/extra data
    # Only allow safe context: guild IDs, channel IDs, error info
    # Strip any string that looks like a token or URL with credentials
    return event
```

This is set up during manual init via `SentrySDK.set_before_send(Callable(self, "_before_send"))`.

### Breadcrumb Strategy

Breadcrumbs provide the "trail of actions" leading to an error. Hook into `AppState` signals:

| Signal | Breadcrumb |
|--------|------------|
| `guild_selected` | `"Switched guild: {guild_id}"` |
| `channel_selected` | `"Opened channel: {channel_id}"` |
| `dm_mode_entered` | `"Entered DM mode"` |
| `message_sent` | `"Sent message"` (no content) |
| `reply_initiated` | `"Started reply"` |
| `layout_mode_changed` | `"Layout: {mode}"` |
| `sidebar_drawer_toggled` | `"Sidebar toggled"` |

Breadcrumbs include only structural IDs, never message text, usernames, or server URLs.

### Release Tracking

The SDK's release string is derived from `project.godot`'s `application/config/version` (currently `"0.1.0"`). GlitchTip groups errors by release, making it easy to see if a new version introduced regressions or fixed known issues.

The release format is `daccord@{version}` (e.g., `daccord@0.1.0`), matching Sentry's convention.

### Environment Tags

The SDK auto-detects the environment (`editor_dev`, `editor_dev_run`, `export_debug`, `export_release`, `dedicated_server`). In GlitchTip, filter by environment to separate developer errors from end-user crashes.

### Config Persistence

New keys in `user://config.cfg` under an `[error_reporting]` section:

```ini
[error_reporting]
enabled=true          # User's consent choice (default: unset, triggers consent dialog)
consent_shown=true    # Whether the consent dialog has been displayed
```

`config.gd` additions:

```gdscript
func get_error_reporting_enabled() -> bool:
    return _config.get_value("error_reporting", "enabled", false)

func set_error_reporting_enabled(value: bool) -> void:
    _config.set_value("error_reporting", "enabled", value)
    _config.save(CONFIG_PATH)

func has_error_reporting_preference() -> bool:
    return _config.has_section_key("error_reporting", "consent_shown")

func set_error_reporting_consent_shown() -> void:
    _config.set_value("error_reporting", "consent_shown", true)
    _config.save(CONFIG_PATH)
```

### User Bar Menu Changes

`user_bar.gd` adds a new menu item:

```gdscript
popup.add_item("Report a Problem", 13)
```

The `_on_menu_id_pressed` match block adds:

```gdscript
13:
    _show_feedback_dialog()
```

The feedback dialog is a simple `AcceptDialog` with a `TextEdit` for the user's description and a send button that calls `SentrySDK.capture_message()`.

### GlitchTip vs Sentry Compatibility

GlitchTip implements the Sentry event ingestion API (v7). The Sentry Godot SDK sends events to whatever DSN is configured -- it does not check whether the server is Sentry or GlitchTip. Confirmed compatible features:

| Feature | GlitchTip Support |
|---------|-------------------|
| Error events | Yes |
| Breadcrumbs | Yes |
| Stack traces | Yes |
| Release tracking | Yes |
| Environment tags | Yes |
| Attachments (log files) | Yes |
| User feedback | Yes |
| Performance/tracing | Partial (not needed for error reporting) |

### What Is NOT Sent

To maintain user trust, daccord explicitly never sends:

- Message content, usernames, or display names.
- Server URLs, tokens, or authentication credentials.
- IP addresses (GlitchTip can be configured to not store IPs).
- Screenshots (disabled in SDK config).
- File contents from the user's system.

The `before_send` callback enforces this as a safety net even if breadcrumbs accidentally include sensitive strings.

## Implementation Status

- [ ] GlitchTip instance deployed and accessible
- [ ] GlitchTip organization and project created, DSN obtained
- [ ] Sentry Godot SDK (`addons/sentry/`) added to the project
- [ ] SDK configured in `project.godot` (DSN, `auto_init=false`, PII off)
- [ ] `config.gd` extended with `[error_reporting]` section
- [ ] First-launch consent dialog in `main_window.gd`
- [ ] Manual SDK initialization gated on consent preference
- [ ] `before_send` callback stripping PII
- [ ] Breadcrumb hooks on `AppState` signals
- [ ] Release tag set from `application/config/version`
- [ ] Environment and OS tags set on scope
- [ ] "Report a Problem" menu item in `user_bar.gd`
- [ ] Feedback dialog with text input and send
- [ ] Crash recovery toast on next launch
- [ ] Settings toggle for enabling/disabling error reporting
- [ ] CI/CD: DSN injected at export time (not hardcoded in repo)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No GlitchTip instance | High | Need to deploy a GlitchTip server and configure DNS, SSL, and email. Docker Compose minimal is the fastest path. |
| Sentry SDK not installed | High | The `addons/sentry/` directory does not exist yet. Download from GitHub releases and add to the project. SDK v1.x requires Godot 4.5+; the project targets 4.6, so this is compatible. |
| DSN management | Medium | The DSN should not be hardcoded in `project.godot` in the public repo. Use an environment variable (`SENTRY_DSN`) or inject it during CI export. For local dev, the DSN can be set in a `.env` file or `export_presets.cfg` (already gitignored). |
| Consent UX not designed | Medium | The consent dialog needs visual design consistent with `discord_dark.tres`. Consider adding a privacy policy link. |
| No settings dialog | Medium | There is currently no general "Settings" dialog in daccord. The error reporting toggle needs a home -- either a new settings dialog or an addition to the About dialog. |
| `before_send` robustness | Medium | The PII filter needs thorough testing. Tokens, URLs, and message snippets could appear in stack traces or local variable captures. `logger/include_variables` should potentially be `false` in release builds to avoid leaking local variable values. |
| Offline event queuing | Low | If the user is offline, the Sentry SDK queues events locally and sends them when connectivity returns. GlitchTip handles this natively -- no extra work needed. |
| Event volume at scale | Low | With `sample_rate=1.0`, a popular release with a common bug could flood GlitchTip. Set `GLITCHTIP_MAX_EVENT_LIFE_DAYS` and consider rate limiting or reducing `sample_rate` if needed. |
