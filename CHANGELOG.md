# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
