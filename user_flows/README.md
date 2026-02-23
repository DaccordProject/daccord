# User Flows

Documentation of daccord's user-facing flows. Each document is verified against the actual codebase, noting what's implemented and what's missing.

Ordered by natural user journey:

| # | Document | Description |
|---|----------|-------------|
| 1 | [Server Connection](server_connection.md) | Adding a server, URL parsing, auth (sign-in/register), token management, HTTPS/HTTP fallback, multi-server |
| 2 | [Guild & Channel Navigation](guild_channel_navigation.md) | Guild bar, guild icons/folders, channel categories/types, channel selection, tab management |
| 3 | [Messaging](messaging.md) | Send/receive, cozy vs collapsed layout, reply/edit/delete, context menus, markdown, embeds, reactions, typing indicators |
| 4 | [Direct Messages](direct_messages.md) | DM mode entry, DM list, DM channel items, search, sending DMs |
| 5 | [Responsive Layout](responsive_layout.md) | Three layout modes (COMPACT/MEDIUM/FULL), sidebar drawer, hamburger button, sidebar/member/search toggles, topic bar, animations |
| 6 | [User Status](user_status.md) | User bar, status dropdown, avatar rendering, about/quit menu |
| 7 | [Voice Channels](voice_channels.md) | Voice channel display, AccordKit voice API, AccordStream addon, current gaps |
| 8 | [Data Model](data_model.md) | ClientModels conversion, dictionary shapes, caching architecture |
| 9 | [Gateway Events](gateway_events.md) | WebSocket event handling, event-to-signal mapping, real-time sync |
| 10 | [Admin Server Management](admin_server_management.md) | Space settings, channel/role/member/ban/invite management, permissions, hierarchy enforcement |
| 11 | [Emoji Picker](emoji_picker.md) | Emoji catalog (160 Twemoji, 8 categories), search, composer insertion, reaction pill integration |
| 12 | [Channel Categories](channel_categories.md) | Collapsible category groups, parent_id grouping, create/edit/delete categories, permission gating |
| 13 | [Editing Messages](editing_messages.md) | Inline edit mode, ownership check, Enter/Escape handling, REST PATCH, gateway update, editing state |
| 14 | [Server Disconnects & Timeouts](server_disconnects_timeouts.md) | Gateway disconnect handling, auto-reconnect, REST timeouts, heartbeat failures, UX gaps for connection state |
| 15 | [Auto-Update](auto_update.md) | Startup & manual update checks via GitHub Releases, update banner, download dialog, version skipping, platform considerations |
| 16 | [In-App Notifications](in_app_notifications.md) | Unread/mention indicators on guilds, channels, and DMs; mention highlights in messages; notification settings; current gaps |
| 17 | [Soundboard](soundboard.md) | Playing audio clips into voice channels, sound management, server/client mixing architecture, permission model |
| 18 | [Message Reactions](message_reactions.md) | Adding/removing emoji reactions, reaction pills, optimistic updates, gateway sync, emoji picker integration |
| 19 | [Channel Permission Management](channel_permission_management.md) | Per-channel role permission overwrites, Allow/Inherit/Deny toggles, Discord-style resolution algorithm, server-side enforcement |
| 20 | [Test Coverage](test_coverage.md) | GUT test framework, test runner, CI pipeline, 437 tests across unit/integration/e2e/AccordStream suites, coverage gaps |
| 21 | [Video Chat](video_chat.md) | Camera video, screen/window sharing, WebRTC video tracks, SDP negotiation, AccordStream media pipeline, video state flags |
| 22 | [Reducing Build Size](reducing_build_size.md) | Custom export templates, stripping unused engine features (3D, Vulkan, OpenXR), selective modules, UPX compression, CI integration |
| 23 | [UI Animations](ui_animations.md) | Tween-based drawer/panel/pill/avatar animations, shader morphing, typing indicator sine wave, hover state machines, flash feedback |
| 24 | [Error Reporting](error_reporting.md) | Self-hosted GlitchTip (Sentry-compatible) error tracking via the Sentry Godot SDK, opt-in consent, PII filtering, breadcrumbs, crash recovery |
| 25 | [Application Sound Effects](application_sound_effects.md) | Client-side audio feedback for messages, mentions, voice join/leave, and UI events; SoundManager architecture, Config persistence, AudioBus layout |
| 26 | [Cross-Platform GitHub Releases](cross_platform_github_releases.md) | Release CI pipeline, cross-platform Godot export (Linux/Windows/macOS), artifact packaging, changelog extraction, GitHub Release creation, code signing gaps |
| 27 | [User Onboarding](user_onboarding.md) | First-run experience, empty states, Add Server + auth flow, startup auto-connect, session restore, subsequent launches |
| 28 | [Group DMs](group_dms.md) | Group DM detection via recipient count, comma-separated names, channel-ID avatar, gateway handling, creation/management gaps |
| 29 | [File Sharing](file_sharing.md) | File attachments, image/file upload via composer, clipboard paste (images & large text), multipart form infrastructure, attachment rendering (inline images & download links), CDN URLs |
| 30 | [Guild Folders](guild_folders.md) | Client-side guild grouping, folder assignment via context menu, collapsible mini-grid preview, folder persistence in Config, expand/collapse animation |
| 31 | [User Management](user_management.md) | Authentication (sign-in/register), user data model, presence/status control, user bar, member list with admin actions, avatar rendering, user caching |
| 32 | [Administrative User Management](admin_user_management.md) | Kick/ban/unban members, role assignment via context menu, role management dialog, ban list with bulk unban, permission gating, gateway sync |
| 33 | [User Configuration](user_configuration.md) | Per-profile encrypted config, profile registry, migration from legacy single-file, server credentials, session restore, voice/sound/status preferences, per-profile emoji cache, notification settings, export/import profiles, local data layout |
| 34 | [Messages Performance](messages_performance.md) | Full re-render strategy, message/user/avatar caching, markdown regex cost, reaction update optimization, sequential author fetches, attachment loading |
| 35 | [Member List Performance](memberlist_performance.md) | Virtual scrolling with object pooling, status grouping, gateway-driven cache updates, rebuild costs, fetch bottlenecks |
| 36 | [Content Embedding](content_embedding.md) | Image/video URL previews, embed cards, inline image rendering, YouTube/oEmbed, link unfurling, attachment display |
| 37 | [Localization](localization.md) | i18n status, PO/POT translation approach, hardcoded string inventory, RTL text server gap, locale persistence |
| 38 | [Accessibility](accessibility.md) | Tooltips, keyboard shortcuts, focus management, touch targets, animation behavior, missing screen reader/high-contrast/reduced-motion support |
| 39 | [Continuous Integration](continuous_integration.md) | CI pipeline architecture, `gh` CLI monitoring/debugging guide, job step breakdowns, failure pattern diagnosis, current status and resolution checklist |
| 40 | [Nightly Branch](nightly_branch.md) | Nightly build branch, automated pre-release CI, rolling `nightly` tag, update channel detection, stable/nightly update routing, Sentry channel tagging |
| 41 | [Profiles](profiles.md) | Multi-profile support, profile switching with optional passwords, per-profile config and emoji cache, migration from single-config, export/import as profiles |
| 42 | [Imposter Mode](imposter_mode.md) | Admin permission preview, "View As" role picker, impersonated permission resolution, channel visibility filtering, write-protection, imposter banner |
| 43 | [User Settings Menu](user_settings.md) | Fullscreen settings panel with 10 pages (Profiles, My Account, Profile edit, Voice & Video, Sound, Notifications, Change Password, Delete Account, 2FA, Connections), profile management dialogs, UX gaps |
| 44 | [Message Threads](message_threads.md) | Slack-style message threads: thread panel UI, thread data model, reply count indicators, thread composer, permission gating, responsive layout |
| 45 | [Forums](forums.md) | Discord-style forum channels: post list view, post creation with titles, thread panel integration, sort/filter, builds on Message Threads |
| 46 | [Master Server Discovery](master_server_discovery.md) | Public server directory via accordmasterserver: server registration, background indexing, search/browse/join flow, discovery panel UI |
| 47 | [Text Channel Chat Bot](text_channel_chat_bot.md) | Bot message rendering, bot user flag, webhook messages, interaction model, slash command API, component support gaps |
| 48 | [Server Update](server_update.md) | Reconnection after server restart/update, stale cache risks, permission race windows, API version gaps, data resync coverage |
| 49 | [Web Export](web_export.md) | Browser export (Godot Web/WASM), hosting, and web-specific voice/video plan (Web APIs instead of AccordStream) |
