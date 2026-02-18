# User Flows

Documentation of daccord's user-facing flows. Each document is verified against the actual codebase, noting what's implemented and what's missing.

Ordered by natural user journey:

| # | Document | Description |
|---|----------|-------------|
| 1 | [Server Connection](server_connection.md) | Adding a server, URL parsing, auth (sign-in/register), token management, HTTPS/HTTP fallback, multi-server |
| 2 | [Guild & Channel Navigation](guild_channel_navigation.md) | Guild bar, guild icons/folders, channel categories/types, channel selection, tab management |
| 3 | [Messaging](messaging.md) | Send/receive, cozy vs collapsed layout, reply/edit/delete, context menus, markdown, embeds, reactions, typing indicators |
| 4 | [Direct Messages](direct_messages.md) | DM mode entry, DM list, DM channel items, search, sending DMs |
| 5 | [Responsive Layout](responsive_layout.md) | Three layout modes (COMPACT/MEDIUM/FULL), sidebar drawer, hamburger button, animations |
| 6 | [User Status](user_status.md) | User bar, status dropdown, avatar rendering, about/quit menu |
| 7 | [Voice Channels](voice_channels.md) | Voice channel display, AccordKit voice API, AccordStream addon, current gaps |
| 8 | [Data Model](data_model.md) | ClientModels conversion, dictionary shapes, caching architecture |
| 9 | [Gateway Events](gateway_events.md) | WebSocket event handling, event-to-signal mapping, real-time sync |
| 10 | [Admin Server Management](admin_server_management.md) | Space settings, channel/role/member/ban/invite management, permissions, hierarchy enforcement |
