# Signal Wiring

## Overview

daccord uses a central signal bus (`AppState`) for all cross-component communication. `AppState` declares 75+ signals that are emitted by backend modules (client, gateway, config) and connected to by UI components. This document maps the complete signal wiring — every emit site and every connection — to identify dead signals, under-connected signals, and propagation gaps.

## User Steps

From a user's perspective, signal wiring determines whether the UI stays in sync:

1. User changes a setting (e.g., mute a server) in User Settings
2. Config writes the value to disk
3. Config emits `AppState.config_changed(section, key)`
4. All UI components connected to `config_changed` react (e.g., guild icon updates muted visual)
5. If a component is NOT connected, the UI is stale until a full refresh

The same pattern applies to every gateway event (message received, member joined, reaction added) and every user action (select guild, send message, toggle sidebar).

## Signal Flow

### Data Flow Architecture
```
┌─────────────────────────────────────────────────────────────────────┐
│                         AppState (signal bus)                       │
│  75+ signals declared, 20+ state vars                               │
│  All cross-component communication goes through here                │
└──────────────┬──────────────────────────────────┬───────────────────┘
               │ .emit()                          │ .connect()
     ┌─────────┴─────────┐             ┌─────────┴──────────┐
     │    EMITTERS        │             │     LISTENERS       │
     │                    │             │                     │
     │  client_gateway.gd │             │  message_view.gd    │
     │  client_fetch.gd   │             │  main_window.gd     │
     │  client_mutations.gd│            │  member_list.gd     │
     │  client_connection.gd│           │  channel_list.gd    │
     │  config.gd         │             │  guild_bar.gd       │
     │  app_state.gd      │             │  dm_list.gd         │
     │  updater.gd        │             │  sidebar.gd         │
     │  client_voice.gd   │             │  composer.gd        │
     │  voice_manager.gd  │             │  user_bar.gd        │
     │  client_admin.gd   │             │  thread_panel.gd    │
     │  guild_bar.gd      │             │  forum_view.gd      │
     │  (UI → AppState)   │             │  error_reporting.gd │
     └────────────────────┘             └─────────────────────┘
```

### Typical Signal Chain
```
Gateway WebSocket event arrives
  → client_gateway.gd parses event, updates Client caches
    → emits AppState.messages_updated(channel_id)
      → message_view.gd._on_messages_updated() re-renders message list
      → thread_panel.gd._on_thread_messages_updated() re-renders thread

User clicks guild icon
  → guild_bar.gd calls AppState.select_guild(id)
    → AppState sets current_guild_id, emits guild_selected(id)
      → sidebar.gd switches to channel list
      → channel_list.gd calls load_guild()
      → member_list.gd reloads members
      → main_window.gd updates header
      → user_bar.gd updates display

Config setting changed
  → config.gd setter writes to disk, emits AppState.config_changed(section, key)
    → guild_icon.gd checks mute state
    → user_bar.gd checks notification preferences
```

## Key Files

| File | Role |
|------|------|
| `scripts/autoload/app_state.gd` | Central signal bus — 75+ signal declarations, 20+ state vars, setter methods |
| `scripts/autoload/client_gateway.gd` | Top emitter — parses gateway events, emits data-updated signals |
| `scripts/autoload/client_fetch.gd` | Emitter — REST fetches complete, emits updated signals |
| `scripts/autoload/client_mutations.gd` | Emitter — write operations (send/edit/delete/react), emits result/failure signals |
| `scripts/autoload/client_connection.gd` | Emitter — server connect/disconnect lifecycle signals |
| `scripts/autoload/config.gd` | Emitter — settings changes, emits `config_changed` |
| `scripts/autoload/client_voice.gd` | Emitter — voice/video state changes |
| `scripts/autoload/client.gd` | Data cache layer — 12+ cache dictionaries accessed by listeners |
| `scenes/messages/message_view.gd` | Top listener — 14+ signal connections |
| `scenes/main/main_window.gd` | Top listener — 10+ signal connections |
| `scenes/sidebar/sidebar.gd` | Listener — guild/channel/DM/layout signals |
| `scenes/members/member_list.gd` | Listener — member/channel/guild/voice signals |
| `scripts/autoload/error_reporting.gd` | Listener — breadcrumb signals for crash reporting |

## Implementation Details

### Signal Declaration Pattern

All signals are declared in `app_state.gd` (lines 3-146). Most use `@warning_ignore("unused_signal")` because they're emitted from other files, not from AppState itself:

```gdscript
@warning_ignore("unused_signal")
signal guilds_updated()
```

Signals emitted directly by AppState methods (like `guild_selected`, `channel_selected`) don't need the annotation.

### Complete Signal Wiring Map

#### Navigation Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `guild_selected` | 2 | 6 | app_state, guild_bar | search_panel, main_window, member_list, user_bar, sidebar, error_reporting | OK |
| `channel_selected` | 2 | 9 | app_state, channel_list | main_window, member_list, channel_list, user_bar, sidebar, composer, message_view, error_reporting, client | OK |
| `dm_mode_entered` | 1 | 4 | app_state | search_panel, main_window, user_bar, error_reporting | OK |
| `search_toggled` | 2 | 1 | app_state | sidebar | OK |
| `member_list_toggled` | 1 | 1 | app_state | main_window | OK |
| `channel_panel_toggled` | 1 | 1 | app_state | main_window | OK |
| ~~`orientation_changed`~~ | — | — | — | — | REMOVED |

#### Messaging Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `message_sent` | 1 | 3 | app_state | message_view, error_reporting, sound_manager | OK |
| `reply_initiated` | 1 | 2 | app_state | composer, error_reporting | OK |
| `reply_cancelled` | 1 | 1 | app_state | composer | OK |
| `message_edited` | 1 | 1 | app_state | message_view | OK |
| `edit_requested` | 2 | 2 | channel_row, composer | channel_management_dialog, message_view | OK |
| `message_deleted` | 1 | 1 | app_state | message_view | OK |
| `messages_updated` | 14 | 2 | client_fetch, client_gateway | thread_panel, message_view | UNDER-CONNECTED |
| `typing_started` | 1 | 1 | client_gateway | message_view | OK |
| `typing_stopped` | 1 | 1 | client_gateway | message_view | OK |
| `image_lightbox_requested` | 1 | 1 | message_content | main_window | OK |

#### Data Update Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `guilds_updated` | 10 | 8 | guild_icon, guild_folder, client_connection, client, client_fetch, client_gateway | connecting_overlay, main_window, add_server_button, guild_bar, user_bar, sidebar, updater | OK |
| `channels_updated` | 18 | 5 | client_mutations_dm, client, client_fetch, client_gateway | channel_management_dialog, member_list, dm_list, channel_list, forum_view | OK |
| `dm_channels_updated` | 12 | 2 | client_mutations_dm, client, client_fetch, client_gateway | member_list, dm_list | UNDER-CONNECTED |
| `user_updated` | 5 | 2 | client_mutations, client_fetch, client_gateway | dm_list, user_bar | OK |
| `members_updated` | 9 | 1 | client_mutations, client_fetch, client_gateway_members, client_gateway | member_list | UNDER-CONNECTED |
| `roles_updated` | 4 | 2 | client_fetch, client_gateway | role_management_dialog | OK |
| `bans_updated` | 4 | 1 | client_admin, client_gateway_events | ban_list_dialog | OK |
| `invites_updated` | 4 | 1 | client_admin, client_gateway_events | invite_management_dialog | OK |
| `emojis_updated` | 6 | 2 | client_admin, client_gateway_events | emoji_management_dialog, emoji_picker | OK |
| `reactions_updated` | 8 | 2 | client_mutations, client_gateway_reactions | thread_panel, message_view | OK |
| `soundboard_updated` | 6 | 3 | client_admin, client_gateway_events | soundboard_management_dialog | OK |
| `soundboard_played` | 1 | 1 | client_gateway_events | sound_manager | OK |
| `forum_posts_updated` | 5 | 1 | client_fetch, client_gateway | forum_view | OK |

#### Member Lifecycle Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `member_joined` | 1 | 1 | client_gateway_members | member_list | OK |
| `member_left` | 1 | 1 | client_gateway_members | member_list | OK |
| `member_status_changed` | 1 | 1 | client_gateway | member_list | OK |

#### Thread & Forum Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `thread_opened` | 1 | 2 | app_state | main_window, thread_panel | OK |
| `thread_closed` | 1 | 2 | app_state | main_window, thread_panel | OK |
| `thread_messages_updated` | 4 | 1 | client_fetch, client_gateway | thread_panel | OK |

#### Voice & Video Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `voice_joined` | 1 | 4 | app_state | voice_bar, voice_channel_item | OK |
| `voice_left` | 1 | 6 | app_state | soundboard_panel, voice_bar | OK |
| `voice_error` | 8 | 3 | voice_manager, client_voice | main_window, voice_bar, error_reporting | OK |
| `voice_mute_changed` | 1 | 2 | app_state | voice_bar, sound_manager | OK |
| `voice_deafen_changed` | 1 | 2 | app_state | voice_bar, sound_manager | OK |
| `video_enabled_changed` | 1 | 2 | app_state | voice_bar, video_grid | OK |
| `screen_share_changed` | 1 | 2 | app_state | voice_bar, video_grid | OK |
| `voice_state_updated` | 6 | 2 | client_voice, client_fetch, client_gateway_events | voice_channel_item, video_grid | OK |
| `remote_track_received` | 1 | 1 | client_voice | video_grid | OK |
| `remote_track_removed` | 1 | 1 | client_voice | video_grid | OK |
| `speaking_changed` | 4 | 2 | client_voice, client | voice_channel_item | OK |

#### Server Connection Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `server_connecting` | 1 | 1 | client_connection | connecting_overlay | OK |
| `connection_step` | 5 | 2 | client_connection | add_server_dialog, sidebar | OK |
| `server_connection_failed` | 4 | 4 | client_connection | connecting_overlay, guild_icon, composer, message_view | OK |
| `server_disconnected` | 2 | 3 | client_gateway | guild_icon, composer, message_view | OK |
| `server_reconnecting` | 1 | 2 | client_gateway | guild_icon, message_view | OK |
| `server_reconnected` | 3 | 4 | client_gateway | guild_icon, composer, message_view, client | OK |
| `server_synced` | 1 | 2 | client_gateway | composer, message_view | OK |
| `server_version_warning` | 2 | 1 | client_connection, client_gateway | message_view | OK |
| `server_removed` | 1 | 2 | — | — | OK |
| `reauth_needed` | 1 | 1 | client_connection | main_window | OK |

#### Error Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `message_send_failed` | 2 | 1 | client_mutations | composer | OK |
| `message_edit_failed` | 3 | 1 | client_mutations | message_view | OK |
| `message_delete_failed` | 3 | 1 | client_mutations | message_view | OK |
| `message_fetch_failed` | 4 | 1 | client_fetch | message_view | OK |
| `reaction_failed` | 4 | 1 | client_mutations | reaction_pill | OK |

#### Auto-Update Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `update_available` | 1 | 2 | updater | user_bar, update_banner | OK |
| `update_check_complete` | 2 | 1 | updater | user_bar | OK |
| `update_check_failed` | 4 | 1 | updater | user_bar | OK |
| `update_download_started` | 1 | 1 | updater | update_download_dialog | OK |
| `update_download_progress` | 1 | 1 | updater | update_download_dialog | OK |
| `update_download_complete` | 1 | 3 | updater | main_window, user_bar, update_download_dialog | OK |
| `update_download_failed` | 5 | 1 | updater | update_download_dialog | OK |

#### UI & Config Signals

| Signal | Emits | Connects | Emit Files | Connect Files | Status |
|--------|-------|----------|-----------|---------------|--------|
| `layout_mode_changed` | 1 | 9 | app_state | welcome_screen, main_window, forum_post_row, forum_view, thread_panel, collapsed_message, message_view, video_grid, error_reporting | OK |
| `sidebar_drawer_toggled` | 2 | 2 | app_state | main_window, error_reporting | OK |
| `profile_switched` | 1 | 3 | config_profiles | main_window, user_settings_profiles_page, client | OK |
| `profile_card_requested` | 2 | 1 | member_item, cozy_message | main_window | OK |
| `imposter_mode_changed` | 2 | 4 | app_state | imposter_banner, banner, channel_list, composer | OK |
| `config_changed` | 10 | 2 | config | guild_icon, user_bar | UNDER-CONNECTED |

### Fixes Applied (2026-02-24 Audit)

#### 1. Config Propagation Infrastructure
**Problem:** Config.gd had zero signals. Changing settings (mute server, toggle notifications) never propagated to running UI components.

**Fix:** Added `config_changed(section: String, key: String)` signal to AppState (line 146). Added `AppState.config_changed.emit()` calls to 10 Config setters:
- `set_sfx_volume` → `("sounds", "volume")`
- `set_sound_enabled` → `("sounds", "enabled")`
- `set_suppress_everyone` → `("notifications", "suppress_everyone")`
- `set_server_muted` → `("muted_servers", server_name)`
- `set_idle_timeout` → `("status", "idle_timeout")`
- `set_reduced_motion` → `("accessibility", "reduced_motion")`
- `_set_ui_scale` → `("accessibility", "ui_scale")`
- `_set_auto_update_check` → `("updates", "auto_check")`
- `set_emoji_skin_tone` → `("emoji", "skin_tone")`
- `set_error_reporting_enabled` → `("privacy", "error_reporting")`

Connected consumers: `guild_icon.gd` (mute visual), `user_bar.gd` (suppress @everyone checkbox).

#### 2. Dead Signal Connections
**`message_delete_failed`** (3 emits, was 0 connections):
- Connected in `message_view.gd` — shows error text on the message via `show_edit_error()`

**`update_download_started`** (1 emit, was 0 connections):
- Connected in `update_download_dialog.gd` — switches to downloading state with version text

#### 3. Under-Connected Signal Fixes
**`user_updated`** (5 emits, was 1 connection → now 2):
- Connected in `dm_list.gd` — refreshes DM items when a user's name/avatar changes

**`reactions_updated`** (8 emits, was 1 connection → now 2):
- Connected in `thread_panel.gd` — re-renders thread messages to pick up reaction changes

**`channels_updated`** (18 emits, was 4 connections → now 5):
- Connected in `forum_view.gd` — updates forum channel name when renamed

**`emojis_updated`** (6 emits, was 1 connection → now 2):
- Connected in `emoji_picker.gd` — invalidates custom emoji cache and refreshes if viewing custom tab

#### 4. Data Cache Propagation Fix
**Problem:** `on_user_update` in `client_gateway.gd` updated `_user_cache` but NOT `_member_cache`. When a user changed their display name or avatar, the member list showed stale data.

**Fix:** After updating `_user_cache`, the handler now iterates `_member_cache` entries and propagates `display_name`, `avatar`, and `username` changes. Emits `members_updated` for each affected guild.

#### 5. Voice Error Propagation
**Problem:** `voice_error` had 8 emit sites but only `main_window.gd` listened (showing a toast). The voice bar had no error indication, and voice errors weren't logged in crash reports.

**Fix:** Connected `voice_error` in two additional files:
- `voice_bar.gd` — Shows error text in the channel label and turns the status dot red for 4 seconds, then reverts to normal state.
- `error_reporting.gd` — Adds a breadcrumb with category "voice" so voice errors appear in Sentry crash trails.

#### 6. Dead Signal Removal — `orientation_changed`
**Problem:** `orientation_changed` was emitted when the viewport aspect ratio crossed 1.5, but nothing connected to it (0 listeners). The `is_landscape` state variable was maintained but never read.

**Fix:** Removed the signal declaration, the `is_landscape` state variable, and the landscape detection block from `update_layout_mode()` in `app_state.gd`. The responsive layout system uses `layout_mode_changed` for breakpoint-based adjustments, making orientation detection redundant.

#### 7. Reduced Motion Audit
**Problem:** The `config_changed` signal had only 2 consumers, and the user flow flagged that animation components might not react to `reduced_motion` changes live.

**Finding:** All 16 files with `create_tween()` calls already check `Config.get_reduced_motion()` before creating animations. The check is done at animation time (not cached at startup), so toggling reduced_motion in settings takes effect immediately without needing a `config_changed` listener. No code changes needed.

### Remaining Under-Connected Signals

These signals have significantly more emit sites than connections, suggesting components that should be listening but aren't:

#### `members_updated` — 9 emits, 1 connection
Only `member_list.gd` listens. The member list is the primary consumer, but components displaying member info outside the member list (e.g., profile cards, mention autocomplete) might benefit from listening.

**Acceptable:** The member list is the only component that renders the full member roster. Other components that show user info (cozy_message, dm_list) already listen to `user_updated` instead.

#### `messages_updated` — 14 emits, 2 connections
Only `message_view.gd` and `thread_panel.gd` listen. Search results and pinned messages (if implemented) would need this.

**Acceptable for now:** Search results are point-in-time snapshots. No pinned message view exists yet.

#### `dm_channels_updated` — 12 emits, 2 connections
Only `dm_list.gd` and `member_list.gd` listen. Sidebar badge counts might benefit.

**Acceptable:** The DM list and member list are the primary DM consumers. Guild bar already derives unread state from `_unread_channels`.

#### `config_changed` — 10 emits, 2 connections
Only `guild_icon.gd` and `user_bar.gd` listen. Many config settings (reduced motion, UI scale, sound volume) affect more components.

**Gap:** Components that read config values at startup but don't watch for changes: `sound_manager.gd` (reads volume/enabled on each `play()` so this is acceptable), responsive layout components (UI scale requires restart anyway).

#### `orientation_changed` — 1 emit, 0 connections
Emitted in `app_state.gd` (line 236) when aspect ratio crosses 1.5. Nothing listens.

**Gap:** Either add landscape-specific layout behavior or remove the signal.

## Implementation Status

- [x] Central signal bus (AppState) with 75+ signals
- [x] Gateway events emit data-updated signals
- [x] REST fetch completions emit data-updated signals
- [x] Write operations emit success/failure signals
- [x] Config changes emit `config_changed` signal
- [x] Dead signals connected (`message_delete_failed`, `update_download_started`)
- [x] `user_updated` connected in dm_list.gd
- [x] `reactions_updated` connected in thread_panel.gd
- [x] `channels_updated` connected in forum_view.gd
- [x] `emojis_updated` connected in emoji_picker.gd
- [x] Member cache propagation on user update
- [x] `voice_error` connected in voice_bar.gd and error_reporting.gd
- [x] `orientation_changed` removed (dead signal, no consumers needed)
- [x] Reduced motion audit — all 16 tween sites already check `Config.get_reduced_motion()` at animation time

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| `config_changed` has only 2 consumers | Low | Most config values are read on-demand (e.g., sound_manager reads volume each play), so reactive updates aren't critical for all settings |
| `members_updated` has 1 consumer | Low | member_list.gd is the only member roster renderer. Acceptable unless member info is displayed elsewhere |
| `dm_channels_updated` has 2 consumers | Low | dm_list and member_list cover the DM UI. Guild bar unread badges derive from `_unread_channels` separately |
| No signal for permission changes | Medium | Permission updates arrive via gateway but don't have a dedicated signal — components re-derive permissions on guild/channel select |
