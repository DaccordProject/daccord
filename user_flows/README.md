# User Flows

Documentation of daccord's user-facing flows. Each document is verified against the actual codebase, noting what's implemented and what's missing.

Ordered by natural user journey:

| # | Document | Last Touched | Description |
|---|----------|:------------:|-------------|
| 1 | [Server Connection](server_connection.md) | 2026-02-18 00:22 | Adding a server, URL parsing, auth (sign-in/register), token management, HTTPS/HTTP fallback, multi-server |
| 2 | [Guild & Channel Navigation](guild_channel_navigation.md) | 2026-02-18 20:21 | Guild bar, guild icons/folders, channel categories/types, channel selection, tab management |
| 3 | [Messaging](messaging.md) | 2026-02-18 20:21 | Send/receive, cozy vs collapsed layout, reply/edit/delete, context menus, markdown, embeds, reactions, typing indicators |
| 4 | [Direct Messages](direct_messages.md) | 2026-02-18 20:21 | DM mode entry, DM list, DM channel items, search, sending DMs |
| 5 | [Responsive Layout](responsive_layout.md) | 2026-02-18 20:21 | Three layout modes (COMPACT/MEDIUM/FULL), sidebar drawer, hamburger button, sidebar/member/search toggles, topic bar, animations |
| 6 | [User Status](user_status.md) | 2026-02-18 00:22 | User bar, status dropdown, avatar rendering, about/quit menu |
| 7 | [Voice Channels](voice_channels.md) | 2026-02-18 20:21 | Voice channel display, AccordKit voice API, AccordStream addon, current gaps |
| 8 | [Data Model](data_model.md) | 2026-02-18 20:21 | ClientModels conversion, dictionary shapes, caching architecture |
| 9 | [Gateway Events](gateway_events.md) | 2026-02-18 00:22 | WebSocket event handling, event-to-signal mapping, real-time sync |
| 10 | [Admin Server Management](admin_server_management.md) | 2026-02-18 20:21 | Space settings, channel/role/member/ban/invite management, permissions, hierarchy enforcement |
| 11 | [Emoji Picker](emoji_picker.md) | 2026-02-18 20:21 | Emoji catalog (160 Twemoji, 8 categories), search, composer insertion, reaction pill integration |
| 12 | [Channel Categories](channel_categories.md) | 2026-02-18 20:21 | Collapsible category groups, parent_id grouping, create/edit/delete categories, permission gating |
| 13 | [Editing Messages](editing_messages.md) | 2026-02-18 20:21 | Inline edit mode, ownership check, Enter/Escape handling, REST PATCH, gateway update, editing state |
| 14 | [Server Disconnects & Timeouts](server_disconnects_timeouts.md) | 2026-02-18 20:21 | Gateway disconnect handling, auto-reconnect, REST timeouts, heartbeat failures, UX gaps for connection state |
| 15 | [Auto-Update](auto_update.md) | 2026-02-18 20:21 | Startup & manual update checks via GitHub Releases, update banner, download dialog, version skipping, platform considerations |
| 16 | [In-App Notifications](in_app_notifications.md) | 2026-02-18 20:21 | Unread/mention indicators on guilds, channels, and DMs; mention highlights in messages; notification settings; current gaps |
| 17 | [Soundboard](soundboard.md) | 2026-02-18 20:21 | Playing audio clips into voice channels, sound management, server/client mixing architecture, permission model |
| 18 | [Message Reactions](message_reactions.md) | 2026-02-18 20:21 | Adding/removing emoji reactions, reaction pills, optimistic updates, gateway sync, emoji picker integration |
| 19 | [Channel Permission Management](channel_permission_management.md) | 2026-02-18 20:21 | Per-channel role permission overwrites, Allow/Inherit/Deny toggles, Discord-style resolution algorithm, server-side enforcement |
| 20 | [Test Coverage](test_coverage.md) | 2026-02-18 20:47 | GUT test framework, test runner, CI pipeline, 437 tests across unit/integration/e2e/AccordStream suites, coverage gaps |
| 21 | [Video Chat](video_chat.md) | 2026-02-18 20:21 | Camera video, screen/window sharing, WebRTC video tracks, SDP negotiation, AccordStream media pipeline, video state flags |
| 22 | [Reducing Build Size](reducing_build_size.md) | 2026-02-18 20:21 | Custom export templates, stripping unused engine features (3D, Vulkan, OpenXR), selective modules, UPX compression, CI integration |
| 23 | [UI Animations](ui_animations.md) | 2026-02-18 20:21 | Tween-based drawer/panel/pill/avatar animations, shader morphing, typing indicator sine wave, hover state machines, flash feedback |
| 24 | [Error Reporting](error_reporting.md) | 2026-02-18 20:21 | Self-hosted GlitchTip (Sentry-compatible) error tracking via the Sentry Godot SDK, opt-in consent, PII filtering, breadcrumbs, crash recovery |
| 25 | [Application Sound Effects](application_sound_effects.md) | 2026-02-18 21:14 | Client-side audio feedback for messages, mentions, voice join/leave, and UI events; SoundManager architecture, Config persistence, AudioBus layout |
