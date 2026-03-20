# Data Model

Priority: 2
Depends on: Server Connection
Status: Complete

The data model subsystem converts AccordKit typed models into dictionary shapes consumed by UI components via `setup(data: Dictionary)`. It spans three layers: conversion (`scripts/client/client_models*.gd`), caching (`scripts/autoload/client.gd` + `scripts/client/client_fetch.gd`), and real-time updates (`scripts/client/client_gateway*.gd`). Client maintains 12+ in-memory caches with routing maps for multi-server support, unread/mention tracking, and O(1) message lookup via `_message_id_index`.

## Key Files

| File | Role |
|------|------|
| `scripts/client/client_models.gd` | Conversion dispatch hub: enums, color palette, delegates to sub-modules |
| `scripts/client/client_models_user.gd` | User/relationship/badge dict conversion |
| `scripts/client/client_models_space.gd` | Space/channel/DM/invite/emoji/sound dict conversion |
| `scripts/client/client_models_message.gd` | Message dict conversion with timestamp formatting and mention detection |
| `scripts/client/client_models_member.gd` | Member/role/voice-state dict conversion |
| `scripts/client/client_fetch.gd` | REST data fetching with pagination and cache population |
| `scripts/client/client_admin.gd` | Admin API wrappers with cache refresh |
| `scripts/client/client_gateway.gd` | Gateway event handling for messages, channels, spaces, roles, typing |
| `scripts/client/client_gateway_events.gd` | Admin/voice/relationship gateway events |
| `scripts/client/client_gateway_members.gd` | Member lifecycle events with index rebuild |
| `scripts/client/client_gateway_reactions.gd` | Reaction events with optimistic dedup |
| `scripts/client/client_markdown.gd` | Markdown-to-BBCode conversion pipeline |
| `scripts/autoload/client.gd` | Core client: caches, routing maps, mutation/voice/permission API |
| `scripts/autoload/app_state.gd` | Central signal bus and UI state tracking |
| `scripts/autoload/config.gd` | Multi-profile encrypted config persistence |
| `scenes/common/avatar.gd` | Avatar rendering with HTTP fetch and LRU cache |
