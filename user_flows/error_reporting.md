# Error Reporting

Last touched: 2026-02-19

## Overview

This flow describes how daccord reports crashes, script errors, and diagnostic data to a self-hosted [GlitchTip](https://glitchtip.com/) instance using the [Sentry Godot SDK](https://github.com/getsentry/sentry-godot). GlitchTip is a Sentry-compatible open-source error tracking platform, so the SDK's DSN simply points at the GlitchTip server instead of Sentry's cloud. The goal is automatic, opt-in error reporting that gives developers visibility into real-world crashes without requiring users to manually file bug reports.

## User Steps

### First Launch (Consent)

1. User launches daccord for the first time (or after a fresh config reset).
2. A `ConfirmationDialog` appears: "Help improve daccord by sending anonymous crash and error reports? No personal data is included. You can change this in the user menu at any time." [Enable] [No thanks]
3. **Enable:** `Config.set_error_reporting_enabled(true)` and `Config.set_error_reporting_consent_shown()` are called. `ErrorReporting.init_sentry()` initializes the Sentry SDK immediately.
4. **No thanks:** `Config.set_error_reporting_enabled(false)` and `Config.set_error_reporting_consent_shown()` are called. The SDK is never initialized.
5. The dialog does not appear again unless config is reset (`Config.has_error_reporting_preference()` returns `true`).

### Automatic Error Capture (Background)

1. User uses daccord normally.
2. A GDScript error, crash, or unhandled exception occurs at runtime.
3. The Sentry SDK automatically captures the error with:
   - Error message and type (script error, shader error, crash).
   - GDScript stack trace with file paths and line numbers.
   - Breadcrumbs (recent user actions leading up to the error).
   - Environment info: OS, Godot version, app version, renderer.
   - Current context: connected server count, active space/channel IDs (no message content).
4. The `_before_send` callback (line 33 of `error_reporting.gd`) checks consent, suppresses editor events, and scrubs PII patterns from the event message.
5. The event is sent to the GlitchTip server via the DSN.
6. The user is not interrupted. No popup or toast appears for automatic captures.

### Crash Recovery

1. daccord crashes (native crash, out of memory, GPU driver fault).
2. The Sentry native SDK (via Crashpad) writes a crash dump to disk.
3. On next launch, `main_window._ready()` checks `SentrySDK.get_last_event_id()` (line 63); if non-empty, it calls `_show_crash_toast()`.
4. A subtle toast appears at the bottom of the screen: "An error report from your last session was sent." It auto-fades after 4 seconds.

### User-Initiated Feedback

1. User encounters a bug and wants to report it manually.
2. User opens the user bar menu and selects "Report a Problem" (menu id 13).
3. A dialog appears with a text field: "Describe what happened (optional):" and buttons [Send Report] [Cancel].
4. **Send Report:** `ErrorReporting.report_problem(description)` calls `SentrySDK.capture_feedback()` with a `SentryFeedback` object. Context tags (server_count, space_id, channel_id) are updated first. Toast: "Report sent. Thank you!"
5. **Cancel:** Dialog closes. No event is sent.

### Toggling Error Reporting (User Bar Menu)

1. User opens the user bar menu.
2. A check item is visible: "Send Error Reports" (menu id 14).
3. Toggling off sets `Config.set_error_reporting_enabled(false)`. The `_before_send` callback returns `null` for all subsequent events, suppressing them.
4. Toggling on sets `Config.set_error_reporting_enabled(true)` and calls `ErrorReporting.init_sentry()` if not already initialized. Takes effect immediately.

## Signal Flow

```
Startup (error reporting enabled):
  ErrorReporting._ready()  (line 5)
    -> Config.get_error_reporting_enabled()
    -> If true:
      -> init_sentry()  (line 9)
        -> SentrySDK.init() with before_send callback  (line 13)
        -> Sets tags: app_version, godot_version, os, renderer  (lines 19-29)
        -> _connect_breadcrumbs() hooks AppState signals  (line 30)
    -> If false:
      -> SDK stays uninitialized

First Launch Consent:
  main_window._ready()  (line 57)
    -> Config.has_error_reporting_preference() == false
    -> call_deferred("_show_consent_dialog")  (line 59)
    -> _show_consent_dialog() creates ConfirmationDialog  (line 338)
    -> User clicks [Enable]:
      -> Config.set_error_reporting_enabled(true)
      -> Config.set_error_reporting_consent_shown()
      -> ErrorReporting.init_sentry()
    -> User clicks [No thanks]:
      -> Config.set_error_reporting_enabled(false)
      -> Config.set_error_reporting_consent_shown()

Runtime Error Captured (automatic):
  GDScript error / crash occurs
    -> Sentry logger integration captures error
    -> Breadcrumbs (recent user actions) attached automatically
    -> _before_send callback  (line 33):
      -> If Config.get_error_reporting_enabled() is false -> return null (drop event)
      -> If event.environment contains "editor" -> return null (drop event)
      -> _scrub_pii(event) redacts tokens, URLs with ports, and token= params
      -> return event (allow send)
    -> Event sent to GlitchTip DSN

Manual Report:
  user_bar._on_menu_id_pressed(13)  (line 143)
    -> _show_feedback_dialog()  (line 213)
    -> User enters description, clicks [Send Report]
    -> ErrorReporting.report_problem(description)  (line 131)
      -> update_context() sets server_count, space_id, channel_id tags  (line 115)
      -> SentrySDK.capture_feedback(SentryFeedback)  (line 137)
    -> _show_report_sent_toast()  (line 276)

Toggle Setting:
  user_bar._on_menu_id_pressed(14)  (line 145)
    -> _toggle_error_reporting()  (line 323)
    -> Config.set_error_reporting_enabled(enabled)
    -> Updates menu checkbox via popup.set_item_checked()
    -> If enabled: ErrorReporting.init_sentry()
```

## Key Files

| File | Role |
|------|------|
| `addons/sentry/` | Sentry Godot SDK addon (GDExtension, gitignored). Provides `SentrySDK`, `SentryEvent`, `SentryBreadcrumb`, `SentryFeedback`, `SentryOptions` classes. |
| `project.godot:60-73` | Sentry SDK configuration: DSN, `auto_init=false`, `send_default_pii=false`, logger masks, `logger/include_source=true`. |
| `scripts/autoload/error_reporting.gd` | Dedicated autoload for Sentry lifecycle: manual init, `before_send` PII gate, breadcrumb hooks on `AppState` signals, `report_problem()` for user feedback, `update_context()` for runtime tags. |
| `scripts/autoload/config.gd:160-172` | Persists `error_reporting_enabled` and `consent_shown` under `[error_reporting]` config section. |
| `scripts/autoload/app_state.gd:3-14` | Breadcrumb source signals: `space_selected`, `channel_selected`, `dm_mode_entered`, `message_sent`, `reply_initiated`, `layout_mode_changed`, `sidebar_drawer_toggled`. |
| `scenes/main/main_window.gd:57-65` | First-launch consent dialog trigger and crash recovery toast trigger. |
| `scenes/main/main_window.gd:338-395` | `_show_consent_dialog()` and `_show_crash_toast()` implementations. |
| `scenes/sidebar/user_bar.gd:40-45` | "Report a Problem" (id 13) and "Send Error Reports" check item (id 14) menu entries. |
| `scenes/sidebar/user_bar.gd:213-333` | `_show_feedback_dialog()`, `_show_report_sent_toast()`, and `_toggle_error_reporting()` implementations. |

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
3. The SDK is a GDExtension (C++ native library), not a GDScript plugin. No `plugin.cfg` entry needed -- it auto-registers via `sentry.gdextension`.
4. The directory is gitignored (`addons/sentry` in `.gitignore`, line 19). Developers must download the SDK separately.

### SDK Configuration (project.godot)

The Sentry SDK reads its settings from `project.godot` under the `[sentry]` section (lines 60-73):

```ini
[sentry]
config/dsn="http://d4fe8b2c21184ae6aed88a521956241c@192.168.1.144:8070/1"
config/auto_init=false
config/debug=false
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
- **`auto_init = false`**: We manage initialization manually via `ErrorReporting.init_sentry()` so we can check the user's consent preference first.
- **`send_default_pii = false`**: Never send PII automatically.
- **`attach_log = true`**: Godot's log file is attached to events (useful for reproducing issues).
- **`attach_screenshot = false`**: Screenshots could contain private messages. Disabled.
- **`sample_rate = 1.0`**: Send all errors. For high user counts, reduce to 0.5 or lower.

### ErrorReporting Autoload

The `ErrorReporting` autoload (`scripts/autoload/error_reporting.gd`) is registered in `project.godot` (line 28) after `Config` and before `Client`:

```
Config="*res://scripts/autoload/config.gd"
ErrorReporting="*res://scripts/autoload/error_reporting.gd"
Client="*res://scripts/autoload/client.gd"
```

This ordering ensures `Config` is available when `ErrorReporting._ready()` checks `Config.get_error_reporting_enabled()`.

**`init_sentry()`** (line 9): Guards against double-init with `_initialized` flag. Calls `SentrySDK.init()` with a lambda that sets `options.before_send` to the `_before_send` callback. Then sets four tags (`app_version`, `godot_version`, `os`, `renderer`) and connects breadcrumb signal handlers.

**`_before_send(event)`** (line 33): Returns `null` (drops the event) if consent is disabled or the environment contains "editor". Otherwise scrubs PII patterns (Bearer tokens, URLs with ports, `token=` query params) from the event message via `_scrub_pii()`, then returns the event.

**`_connect_breadcrumbs()`** (line 56): Connects seven `AppState` signals to handler methods that call `_add_breadcrumb()`.

**`_add_breadcrumb(message, category)`** (line 102): Creates a `SentryBreadcrumb`, sets `message`, `category`, and `type = "default"`, then calls `SentrySDK.add_breadcrumb()`.

**`update_context()`** (line 115): Sets `server_count`, `space_id`, and `channel_id` tags on the Sentry scope. Called before manual reports.

**`report_problem(description)`** (line 131): Creates a `SentryFeedback` with the description, calls `SentrySDK.capture_feedback()`.

### Breadcrumb Strategy

Breadcrumbs provide the "trail of actions" leading to an error. Hooked in `error_reporting.gd` via `_connect_breadcrumbs()` (line 56):

| Signal | Breadcrumb | Category |
|--------|------------|----------|
| `space_selected` | `"Switched space: {space_id}"` | `navigation` |
| `channel_selected` | `"Opened channel: {channel_id}"` | `navigation` |
| `dm_mode_entered` | `"Entered DM mode"` | `navigation` |
| `message_sent` | `"Sent message"` (no content) | `action` |
| `reply_initiated` | `"Started reply"` | `action` |
| `layout_mode_changed` | `"Layout: {COMPACT\|MEDIUM\|FULL}"` | `ui` |
| `sidebar_drawer_toggled` | `"Sidebar toggled"` | `ui` |

Breadcrumbs include only structural IDs, never message text, usernames, or server URLs.

### Privacy: before_send Filtering

The `_before_send` callback (line 33) provides three gates:
1. **Consent check**: If `Config.get_error_reporting_enabled()` returns `false`, the event is dropped (`return null`).
2. **Editor suppression**: Events from editor environments are dropped to avoid polluting production data.
3. **PII scrubbing**: `_scrub_pii()` uses regex to redact Bearer tokens, URLs with ports (common in accordserver connections), and `token=` query parameters from the event message before sending.

### Release Tracking

The SDK's release string is derived from `project.godot`'s `application/config/version` (currently `"0.1.1"`, line 18). The `app_version` tag is set explicitly in `init_sentry()` (line 19). GlitchTip groups errors by release, making it easy to see if a new version introduced regressions.

### Environment Tags

The SDK auto-detects the environment (`editor_dev`, `editor_dev_run`, `export_debug`, `export_release`, `dedicated_server`). Editor events are suppressed by `_before_send`. In GlitchTip, filter by environment to separate developer errors from end-user crashes.

### Config Persistence

New keys in `user://config.cfg` under an `[error_reporting]` section:

```ini
[error_reporting]
enabled=true          # User's consent choice (default: false, triggers consent dialog)
consent_shown=true    # Whether the consent dialog has been displayed
```

`config.gd` methods (lines 160-172):

- `get_error_reporting_enabled() -> bool` -- returns `_config.get_value("error_reporting", "enabled", false)`.
- `set_error_reporting_enabled(value: bool)` -- persists and saves.
- `has_error_reporting_preference() -> bool` -- checks if `consent_shown` key exists.
- `set_error_reporting_consent_shown()` -- sets `consent_shown = true` and saves.

### User Bar Menu Changes

`user_bar.gd` adds two new menu items (lines 40-41):

```gdscript
popup.add_item("Report a Problem", 13)
popup.add_check_item("Send Error Reports", 14)
```

The check item is initialized from `Config.get_error_reporting_enabled()` (lines 42-45). The `_on_menu_id_pressed` match block routes id 13 to `_show_feedback_dialog()` and id 14 to `_toggle_error_reporting()`.

**Feedback dialog** (`_show_feedback_dialog()`, line 213): An `AcceptDialog` with a `TextEdit` for the user's description, a privacy notice label, and [Send Report] / [Cancel] buttons. On confirm, calls `ErrorReporting.report_problem()` and shows a toast.

**Toggle** (`_toggle_error_reporting()`, line 323): Flips the config value, updates the checkbox, and calls `ErrorReporting.init_sentry()` if enabling.

### Consent Dialog

`main_window.gd` checks `Config.has_error_reporting_preference()` in `_ready()` (line 58). If false (first launch), it defers `_show_consent_dialog()`.

The dialog (line 338) is a `ConfirmationDialog` with [Enable] / [No thanks] buttons. Both paths call `Config.set_error_reporting_consent_shown()` so the dialog never reappears.

### Crash Recovery Toast

`main_window.gd` checks if error reporting is enabled and initialized (line 62), then calls `SentrySDK.get_last_event_id()` (line 63). If non-empty (indicating a crash dump was sent on restart), a styled toast panel is shown at the bottom of the screen. It auto-fades after 4 seconds via a tween (lines 392-395).

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

The `before_send` callback enforces this as a safety net: `_scrub_pii()` redacts tokens and server URLs even if they accidentally appear in error messages or stack traces.

## Implementation Status

- [x] GlitchTip instance deployed and accessible
- [x] GlitchTip organization and project created, DSN obtained
- [x] Sentry Godot SDK (`addons/sentry/`) added to the project (gitignored)
- [x] SDK configured in `project.godot` (DSN, `auto_init=false`, PII off)
- [x] `config.gd` extended with `[error_reporting]` section
- [x] First-launch consent dialog in `main_window.gd`
- [x] Manual SDK initialization gated on consent preference (`ErrorReporting` autoload)
- [x] `before_send` callback (consent gate + editor suppression)
- [x] Breadcrumb hooks on `AppState` signals (7 signals)
- [x] Release tag set from `application/config/version`
- [x] Environment and OS tags set on scope
- [x] "Report a Problem" menu item in `user_bar.gd`
- [x] Feedback dialog with text input and send (`SentryFeedback`)
- [x] Crash recovery toast on next launch
- [x] Settings toggle for enabling/disabling error reporting (check item in user bar menu)
- [x] CI/CD: DSN injected at export time via `SENTRY_DSN` secret in `release.yml`

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| ~~DSN hardcoded in `project.godot`~~ | ~~Medium~~ | Resolved. `release.yml` now injects `SENTRY_DSN` secret at export time. The dev DSN remains in the repo for local testing. |
| ~~`before_send` lacks deep PII scrubbing~~ | ~~Medium~~ | Resolved. `_scrub_pii()` redacts Bearer tokens, URLs with ports, and `token=` query parameters from event messages. |
| Offline event queuing | Low | If the user is offline, the Sentry SDK queues events locally and sends them when connectivity returns. GlitchTip handles this natively -- no extra work needed. |
| Event volume at scale | Low | With `sample_rate=1.0`, a popular release with a common bug could flood GlitchTip. Set `GLITCHTIP_MAX_EVENT_LIFE_DAYS` and consider rate limiting or reducing `sample_rate` if needed. |
| ~~Crash toast false positives~~ | ~~Low~~ | Resolved. Toast text changed to "error report" instead of "crash report," which is accurate for both crash and non-crash events. |
