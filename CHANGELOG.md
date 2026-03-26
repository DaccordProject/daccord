# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.17] - 2026-03-26

### Added
- Session rejoin, web gateway resilience, and unread acknowledgement
- Plugin helpers refactor

### Fixed
- Mobile responsive layout: full-height drawers and modal width capping

## [0.1.16] - 2026-03-22

### Added
- Mobile gesture navigation (swipe drawer)
- Mobile optimization improvements
- Multi-instance automated app test suite with login and input simulation
- Windows smoke test to CI
- Audit log live updates, guest access control, privacy & data export, screen picker preview

### Fixed
- Mobile modal responsive layout issues
- Crash reporting: restore web crash reporting via JavaScript Sentry SDK, initialize Sentry SDK from MainLoop for desktop
- CI failures in SentrySceneTree MainLoop
- Missing .uid files for NavigationHistory and GuestPromptDialog
- Headless test failures and endpoint count test
- Extracted scenes from programmatic UI

## [0.1.15] - 2026-03-19

### Fixed
- Allow other users to see and join voice channel activities
- Restore last active space and channel on app restart
- Various responsive layout fixes

## [0.1.14] - 2026-03-19

### Added
- MCP tools, content embedding, and gateway events
- Client HTTP API

### Changed
- Reorganized scripts into domain subdirectories and split large files
- Moved mute/color/developer helpers to proper subsystems

### Fixed
- Remove curl -f flag from test assertions expecting HTTP errors
- Clean stale test DB from CWD and add missing UID files
- Use platform-specific asset extensions in updater tests
- Fix GitHub org URLs and add self-hosting deployment guide

## [0.1.13] - 2026-03-17

### Added
- Grouped channel permissions UI
- Swedish (sv) internationalization support
- Server plugins system (client-side)
- Shared modal helpers and refactored admin dialogs
- i18n support, read-only mode, and moderation improvements

### Fixed
- Remove lua-gdextension from CI to fix SIGSEGV crash on Godot 4.5
- Use standard Lua variant in CI to fix SIGSEGV crash
- Modal close behavior
- Lint line-length violation

## [0.1.12] - 2026-03-14

### Added
- Web deep links and UI icon cleanup
- Local friend book for cross-server relationship persistence
- Loading animations for server connection

### Fixed
- Attach remote audio tracks on web so web client can hear desktop clients
- Use Web Audio API for mic test on web to avoid unsupported AudioStreamMicrophone
- Loose web files in release packaging

### Changed
- Updated responsive layout and other user flow documentation
- Code extraction refactors

## [0.1.11] - 2026-03-11

### Added
- Guest/anonymous read-only access and emoji catalog refactor
- Unit tests for ClientAdmin, ClientRelationships, and ClientPermissions autoloads
- Unit tests for DM list, group DM dialog, message action bar, and message view banner
- Unit tests for voice UI components and profile management dialogs
- Strengthened gateway disconnect test with real assertions

### Fixed
- Web export canvas sizing and skip window resize on web
- Android keystore environment variables for export
- CI integration test auth and web export path mismatches
- DM integration tests resilient to idempotent server responses
- gdlint errors (line length, max-returns)

### Changed
- Moved web export templates from export/web/ to dist/web/
- Spring clean: removed duplicate EmojiCatalog, fixed risky tests
- Cached Android SDK in CI and removed website rebuild trigger
- Added priority and dependency metadata to all user flows

## [0.1.10] - 2026-03-10

### Added
- About page and PostgreSQL user flow
- Password visibility toggle on all password fields
- SyncManager autoload with E2E-encrypted config sync
- Web export support with COOP/COEP service worker for Chrome
- Friends/relationships system with REST endpoints and helpers
- Read-only mode user flow

### Changed
- Refactored theme styling and avatar setup
- Refactored REST endpoints

### Fixed
- SyncAPI URL paths
- Sync security audit improvements

## [0.1.9] - 2026-03-05

### Added
- Voice text chat panel for sending messages in voice channels
- URI handler for deep linking (`daccord://` protocol)
- MFA/2FA support in auth dialog
- Permission descriptions for role management UI
- Theme font color metadata system for declarative node theming
- Status colors, image error background, and reaction border theme tokens
- Settings icon

### Changed
- Admin dialogs migrated to modal base system with themed font colors
- Connecting overlay replaced with integrated welcome screen

### Fixed
- Discovery card and detail panel theming improvements

## [0.1.8] - 2026-03-02

### Added
- Android release pipeline (APK build via GitHub Actions with keystore signing)
- Theming system, server discovery, modal base, and active threads
- Copy all files (pck, libs) during auto-update, not just the binary

### Fixed
- Send public flag as top-level field and parse it from server response
- Remove phantom ThemeManager autoload entry
- Lint errors blocking release

## [0.1.7] - 2026-03-02

### Added
- Server management panel with admin access via space context menu
- Browse Servers tab and join flow

### Fixed
- Re-center window after HiDPI resize and cap screen share resolution

## [0.1.6] - 2026-02-28

### Added
- Voice auto-reconnect on unexpected disconnection with intentional-disconnect guard
- Voice config hot-reload: camera republish on resolution/fps change, debug logging toggle
- Audio device application on startup and on change via `apply_devices()`
- Parse embedded user from member gateway events to avoid extra REST fetch
- Voice channels user flow documentation with known issues and edge cases

### Changed
- Always reconnect voice backend on `voice.server_update` (not just when DISCONNECTED)
- Prefer embedded user data in `on_member_join` over REST fetch when available

### Fixed
- Context menus: call `hide()` before `popup()` to prevent stale popup positioning
- Audio capture uses `AudioServer.get_mix_rate()` instead of hardcoded 48000
- Mic cleanup uses immediate `free()` instead of `queue_free()` to prevent silent capture
- MicCapture bus lookup by name instead of cached index to handle shifted indices
- Clean up stale MicCapture bus from previous sessions
- Apply correct input device before starting mic test

## [0.1.5] - 2026-02-28

### Fixed
- Force full opacity on screen share preview for 32-bit depth displays
- Stop converting screen share preview to RGB8 to prevent intermittent transparency
- Remove custom MainLoop to fix SentrySceneTree startup crash

### Changed
- Regenerate app icons from updated icon.svg

## [0.1.4] - 2026-02-27

### Added
- Video picture-in-picture (PiP) mode
- Screen capture support via LiveKitScreenCapture

### Changed
- Use prebuilt godot-livekit binaries in CI
- Security hardening and UI refactors

### Fixed
- Use LiveKitScreenCapture constant for permission check
- Remove default port 39099 so HTTPS uses standard port 443

## [0.1.3] - 2026-02-25

### Added
- Config migration for guild→space config keys

### Changed
- Renamed "guild" to "space" throughout the application
- Split monolithic user settings into app settings and server settings
- Capitalized app name to "Daccord"

### Security
- Removed stored plaintext passwords from config

## [0.1.1] - 2026-02-21

### Changed
- ETC2/ASTC texture import for macOS universal export
- Refactored large modules and overhauled README
- Gated release builds on CI passing
- Added Windows installer job to release workflow
- Added profiles, group DMs, embeds, audit log, imposter mode, auto-update, and UI polish

## [0.1.0] - 2026-02-19

### Added
- Initial client application with multi-server support
- Real-time messaging via WebSocket gateway
- Channel and DM navigation
- Message compose, edit, delete, and reply
- Emoji picker with custom and Unicode emoji
- Server administration (channels, roles, bans, invites, emoji)
- Responsive layout with compact/medium/full modes
- Custom dark theme
