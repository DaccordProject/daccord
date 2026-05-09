# In-App Notifications

Priority: 16
Depends on: Messaging, Gateway Events

## Overview

daccord provides visual cues to notify users of new activity across spaces, channels, and DMs. The notification system has three layers: space-level indicators (pills and mention badges on space icons), channel-level indicators (unread dots and bold text on channel items), and message-level indicators (mention highlights on individual messages). Notification behavior is configurable at the space level (default notification setting), per-channel (all/mentions/muted), per-server (mute, suppress @everyone override), and per-role (mentionable toggle). Users can set their status to Do Not Disturb to suppress all notification indicators and sounds. Channel mutes are server-side (persisted via REST API), while per-channel notification levels are client-side (persisted in Config). Server-side read-state tracking via channel ack keeps unread state across restarts. There are no OS-level notifications (desktop toasts, system tray badges).

## User Steps

1. User receives a message in a channel they are not currently viewing.
2. The gateway handler checks DND status, channel mute (server-side), server mute, per-server suppress @everyone, per-channel notification level, and space default notifications before marking unread.
3. If notifications are not suppressed, the space icon's pill transitions from hidden to the UNREAD state (small dot).
4. If the message mentions the user (by ID, @everyone, or role), the space icon's red mention badge increments.
5. In the channel list, the channel item's unread dot becomes visible and the channel name turns white (bold).
6. User clicks the space icon, then clicks the channel with the unread indicator.
7. The message view loads; any message that mentions the user (via structured `mentions` array, `mention_everyone`, or `mention_roles`) is tinted with a warm highlight color.
8. Unread state clears when the user views the channel (via `on_channel_selected_clear_unread`), and a read-state ack is sent to the server.

## Signal Flow

```
Gateway MESSAGE_CREATE
  └─> client_gateway.on_message_create()
        └─> Appends to _message_cache (message dict includes mentions, mention_everyone, mention_roles)
        └─> Checks DND status → if DND, skips unread tracking
        └─> Checks is_channel_muted() (server-side, inherits from parent category) → if muted, skips
        └─> Checks Config.is_server_muted() → if muted, skips
        └─> Determines is_mention (user ID in mentions, mention_everyone + per-server suppress check, role mentions)
        └─> Checks per-channel notification level (Config) → falls back to space default_notifications
              "muted" → skips; "mentions" with no mention → skips
        └─> Calls Client.mark_channel_unread(channel_id, is_mention)
              └─> Updates _unread_channels, _channel_mention_counts
              └─> Updates _channel_cache[cid]["unread"] = true
              └─> Calls update_space_unread() to aggregate space-level unread/mention counts
              └─> Emits channels_updated + spaces_updated
        └─> SoundManager.play_for_message() (checks DND, channel/server mute, per-channel level)
        └─> AppState.messages_updated.emit(channel_id)
              └─> message_view renders messages; ClientModels.is_user_mentioned() drives highlight tint

Channel selected
  └─> Client.unread.on_channel_selected_clear_unread()
        └─> Erases from _unread_channels and _channel_mention_counts
        └─> Updates channel/DM dict unread = false
        └─> Recalculates space unread/mentions
        └─> Sends read-state ack to server (channels.ack with last_message_id)

Gateway READY (on connect)
  └─> client_gateway_ready._apply_unread()
        └─> Reads "unread" array from server (channel_id + mention_count pairs)
        └─> Populates _unread_channels and _channel_mention_counts
        └─> Recomputes space-level unread for affected spaces
  └─> Reads "mutes" array → populates _muted_channels
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_icon.gd` | Reads `unread`/`mentions` from space dict, drives pill state and mention badge; "Mute Server"/"Unmute Server" context menu; dimmed visual when muted |
| `scenes/sidebar/guild_bar/pill.gd` | Three-state indicator (HIDDEN/UNREAD/ACTIVE) with animated transitions |
| `scenes/sidebar/guild_bar/mention_badge.gd` | Red circular badge showing mention count, auto-hides when count is 0 |
| `scenes/sidebar/guild_bar/mention_badge.tscn` | Badge scene with red `StyleBoxFlat` (Color 0.929, 0.259, 0.271) |
| `scenes/sidebar/channels/channel_item.gd` | Reads `unread` from channel dict; shows/hides unread dot and bolds name; context menu with Mute/Unmute toggle and Notification Settings submenu (All/Mentions/Muted); dims when muted or notification level is "muted" |
| `scenes/sidebar/channels/voice_channel_item.gd` | Voice channel item with Mute/Unmute context menu toggle (line 332-336) |
| `scenes/sidebar/channels/category_item.gd` | Category item with Mute/Unmute context menu toggle (line 188-195); muting a category inherits to child channels |
| `scenes/sidebar/direct/dm_channel_item.gd` | Reads `unread` from DM dict, shows/hides unread dot |
| `scripts/client/client_models.gd` | Converts AccordKit models to UI dicts; `message_to_dict()` includes `mentions`, `mention_everyone`, `mention_roles`; `is_user_mentioned()` helper for structured mention checks |
| `scripts/client/client_gateway.gd` | Handles MESSAGE_CREATE; enforces DND, channel mute, server mute, per-server suppress @everyone, per-channel notification level, and space `default_notifications` before marking channels unread (lines 361-404) |
| `scripts/client/client_unread.gd` | Manages `_unread_channels`, `_channel_mention_counts`, `_muted_channels`; `mark_channel_unread()`, `clear_channel_unread()`, `update_space_unread()`, `is_channel_muted()` (with parent category inheritance), `mute_channel()`/`unmute_channel()` (REST API calls), `_ack_channel()` (server read-state ack) |
| `scripts/client/client_gateway_ready.gd` | On READY: loads mutes array into `_muted_channels` (line 97-104), applies server-side unread state via `_apply_unread()` (line 234-263) |
| `scripts/client/client_gateway_events.gd` | Handles `CHANNEL_MUTE_CREATE`/`CHANNEL_MUTE_DELETE` gateway events to sync mute state in real-time (lines 132-142) |
| `scripts/client/client_fetch.gd` | `list_mutes()` fetches muted channels from server via `users.list_mutes()` on connection (line 185-191) |
| `scripts/autoload/client.gd` | Delegates to `ClientUnread` via `unread` property; exposes `is_channel_muted()`, `mute_channel()`, `unmute_channel()`, `mark_channel_unread()`, `clear_channel_unread()` (lines 688-728) |
| `scripts/autoload/sound_manager.gd` | `play_for_message()` respects per-channel notification level, channel mute, server mute, DND, and window focus before playing sounds (lines 78-115) |
| `scenes/messages/cozy_message.gd` | Uses `ClientModels.is_user_mentioned()` for structured mention highlight tint |
| `scenes/messages/collapsed_message.gd` | Uses `ClientModels.is_user_mentioned()` for structured mention highlight tint |
| `scenes/messages/composer/composer.gd` | Warns when user types `@everyone` without `MENTION_EVERYONE` permission |
| `addons/accordkit/models/message.gd` | Parses `mention_everyone`, `mentions`, `mention_roles` from server data |
| `addons/accordkit/models/space.gd` | Has `default_notifications` field ("all" or "mentions") |
| `addons/accordkit/rest/endpoints/channels_api.gd` | REST endpoints: `ack()` (line 86), `mute()` (line 72), `unmute()` (line 79) |
| `addons/accordkit/rest/endpoints/users_api.gd` | `list_mutes()` endpoint (line 58) |
| `scenes/admin/space_settings_dialog.gd` | UI for configuring default notification level per space |
| `scenes/admin/role_management_dialog.gd` | UI for toggling role mentionable flag |
| `scenes/user/app_settings.gd` | Global notification settings: suppress @everyone, idle timeout (lines 671-715) |
| `scenes/user/server_settings.gd` | Per-server notification settings: server mute toggle, per-server @everyone suppress override (lines 79-108) |
| `scenes/sidebar/user_bar.gd` | User status menu including Do Not Disturb |
| `scripts/autoload/config.gd` | Persists notification preferences: `suppress_everyone` (line 474), `server_suppress` per-server override (line 484), `muted_servers` (line 495), `channel_notifications` per-channel level (line 521), `thread_notifications` (line 509) |
| `scripts/autoload/app_state.gd` | Signals: `channel_mutes_updated` (line 150), `channel_notification_updated` (line 152) |
| `addons/accordkit/models/role.gd` | Parses `mentionable` flag from server |
| `addons/accordkit/models/permission.gd` | Defines `MENTION_EVERYONE` permission constant |

## Implementation Details

### Space-Level Indicators (Pill + Mention Badge)

`guild_icon.gd` reads notification state from the space dictionary during `setup()` (line 79-109):

- `_has_unread = data.get("unread", false)` (line 85) -- boolean driving pill state
- `mentions = data.get("mentions", 0)` (line 86) -- integer driving badge visibility
- The pill has three states: `HIDDEN` (no activity), `UNREAD` (6px dot), `ACTIVE` (20px bar for selected space)
- `set_active()` transitions pill state with animation via `set_state_animated()`
- The mention badge auto-shows when `count > 0` and hides when `count == 0`
- Badge styled as red rounded pill (corner radius 8, bg `Color(0.929, 0.259, 0.271)`)

### Pill Animation

`pill.gd` implements smooth height transitions:

- `set_state_animated()` uses a `Tween` to animate `custom_minimum_size.y` and `size.y`
- UNREAD state: 6px height; ACTIVE state: 20px height
- Animation duration: 0.15 seconds

### Channel-Level Indicators (Unread Dot)

`channel_item.gd` reads unread state in `setup()` (lines 133-135):

- `_has_unread = data.get("unread", false)` -- boolean
- `unread_dot.visible = _has_unread` -- a `ColorRect` node toggled by the `unread` field
- When unread, channel name turns white; otherwise muted gray (line 158-162)
- Channels with notification level "muted" or server-side mute are visually dimmed (alpha 0.4, lines 164-175)

### DM-Level Indicators

`dm_channel_item.gd` reads unread state in `setup()`:

- `unread_dot.visible = data.get("unread", false)` -- same dot pattern as channel items

### Message-Level Mention Highlights

Both `cozy_message.gd` and `collapsed_message.gd` use `ClientModels.is_user_mentioned()` for structured mention detection:

```gdscript
var my_id: String = Client.current_user.get("id", "")
var my_roles: Array = _get_current_user_roles()
if ClientModels.is_user_mentioned(data, my_id, my_roles):
    modulate = Color(1.0, 0.95, 0.85)
```

`is_user_mentioned()` checks: (1) user ID in the `mentions` array, (2) `mention_everyone` flag (respecting the suppress @everyone preference), and (3) whether any of the user's roles are in the `mention_roles` array.

### Server-Side Mention Data (AccordKit)

`AccordMessage` (lines 16-18) parses three mention fields from the server:

- `mention_everyone: bool` -- whether `@everyone` was used
- `mentions: Array` -- array of user IDs who were mentioned
- `mention_roles: Array` -- array of role IDs that were mentioned

These are passed through to the UI dictionary by `ClientModels.message_to_dict()` as `"mentions"`, `"mention_everyone"`, and `"mention_roles"` fields.

### Default Notification Setting

`AccordSpace` has a `default_notifications` field (line 16) with values `"all"` or `"mentions"`. This is:

- Stored in the space dict by `ClientModels.space_to_dict()`
- Editable via `space_settings_dialog.gd` with an OptionButton offering "All Messages" and "Mentions Only"
- **Enforced** by `client_gateway.gd` in `on_message_create()`: when a space's `default_notifications` is `"mentions"`, non-mention messages do not trigger unread indicators
- **Overridden** by per-channel notification level when the channel has a non-default setting

### Per-Channel Notification Level

Users can set per-channel notification levels via the channel item context menu (`channel_item.gd`):

- **UI:** Right-click a channel → "Notification Settings" submenu with three radio options: "All Messages" (id 20), "Only Mentions" (id 21), "Muted" (id 22) (lines 42-47)
- **Storage:** `Config.get_channel_notification_level(channel_id)` / `Config.set_channel_notification_level(channel_id, level)` in the `[channel_notifications]` config section (lines 521-530 of `config.gd`). Values: `"default"`, `"all"`, `"mentions"`, `"muted"`.
- **Signal:** Setting a level emits `AppState.channel_notification_updated(channel_id)` (line 530 of `config.gd`)
- **Visual:** Channels with notification level "muted" are visually dimmed to 0.4 alpha (lines 164-175 of `channel_item.gd`). The `_on_notification_updated()` callback (line 245) refreshes the visual state when the level changes.
- **Enforcement (unread tracking):** `client_gateway.gd` (lines 391-404) reads the per-channel level and falls back to the space default. If the effective level is "muted", unread tracking is skipped entirely. If "mentions", only mentions trigger unread.
- **Enforcement (sounds):** `sound_manager.gd` (lines 96-107) checks per-channel level, server mute, and channel mute before playing notification sounds. "Muted" suppresses all sounds; "mentions" suppresses non-mention sounds.

### Channel Mute (Server-Side)

Channel mute is a server-side feature persisted via REST API:

- **Mute:** `Client.mute_channel(channel_id)` → `PUT /channels/:id/mute` (line 102-113 of `client_unread.gd`)
- **Unmute:** `Client.unmute_channel(channel_id)` → `DELETE /channels/:id/mute` (line 115-126 of `client_unread.gd`)
- **Check:** `Client.is_channel_muted(channel_id)` checks `_muted_channels` dict, with inheritance from parent category (lines 92-100 of `client_unread.gd`)
- **Initialization:** Muted channels are loaded from the READY payload (line 97-104 of `client_gateway_ready.gd`) and via `list_mutes()` REST call (line 185-191 of `client_fetch.gd`)
- **Real-time sync:** `CHANNEL_MUTE_CREATE`/`CHANNEL_MUTE_DELETE` gateway events update `_muted_channels` in real-time (lines 132-142 of `client_gateway_events.gd`)
- **UI:** Context menu "Mute Channel"/"Unmute Channel" toggle on channel items (line 212-215 of `channel_item.gd`), voice channel items (line 332-336 of `voice_channel_item.gd`), and category items (line 188-195 of `category_item.gd`)

### Unread/Mention Tracking

`ClientUnread` (`client_unread.gd`) manages all unread state:

- `mark_channel_unread(cid, is_mention)` (line 59): Sets `_unread_channels[cid] = true`, increments `_channel_mention_counts[cid]` if mention, updates channel cache, recomputes space unread, emits signals.
- `clear_channel_unread(cid)` (line 15): Erases from tracking dicts, updates cache, recomputes space, sends server ack.
- `update_space_unread(gid)` (line 75): Aggregates channel unread/mention counts to space level.
- `on_channel_selected_clear_unread(cid)` (line 8): Connected to `AppState.channel_selected`; clears unread and always acks to server.

### Server-Side Read-State Ack

The client sends read-state acknowledgments to the server when channels are viewed:

- **Ack call:** `_ack_channel(cid)` (line 32) sends `POST /channels/:id/ack` with `{"message_id": last_message_id}` via `client.channels.ack()`.
- **Last message ID resolution:** `_get_last_message_id(cid)` (line 44) checks the message cache first, then falls back to `last_message_id` in the channel cache.
- **Server response on connect:** The READY payload includes an `unread` array (channel_id + mention_count pairs) reflecting server-side read state. `_apply_unread()` (line 234 of `client_gateway_ready.gd`) populates local tracking from this data.
- **Effect:** Unread state persists across app restarts since the server tracks the last-read message per channel.

## Notification Options

### Space Default Notification Level

Admins can configure the space-wide default notification level in **Space Settings** (`space_settings_dialog.gd`):

- **UI:** An `OptionButton` with two items: "All Messages" (id 0) and "Mentions Only" (id 1)
- **Tooltip:** "The default notification setting applied to new members. They can override this individually."
- **Load:** Reads `space.get("default_notifications", "all")` and selects the matching option
- **Save:** Sends `"default_notifications": notif_levels[selected]` to the server via `Client.update_space()`, where `notif_levels = ["all", "mentions"]`
- **Server model:** `AccordSpace.default_notifications` stores the value as a string, defaulting to `"all"` (line 16 of `space.gd`)
- **Effect:** Enforced by the gateway's unread tracking logic. Per-channel overrides take precedence.

### Per-Channel Notification Level

Users can override the space default per-channel via right-click context menu:

- **UI:** "Notification Settings" submenu in channel item context menu with radio-checked items (lines 42-47, 216-221 of `channel_item.gd`)
- **Options:** "All Messages" → `"all"`, "Only Mentions" → `"mentions"`, "Muted" → `"muted"` (lines 239-243)
- **Storage:** `Config.set_channel_notification_level(channel_id, level)` in `[channel_notifications]` section
- **Default:** `"default"` (falls through to space default)
- **Enforcement:** Gateway checks per-channel level before space default (lines 391-404 of `client_gateway.gd`). SoundManager also respects this level (lines 96-107 of `sound_manager.gd`).

### Role Mentionable Toggle

Admins can control whether a role can be @mentioned in **Role Management** (`role_management_dialog.gd`):

- **UI:** A `CheckBox` labeled "Allow anyone to mention this role"
- **Tooltip:** "Anyone can @mention this role to notify all members who have it."
- **Load:** `_mentionable_check.button_pressed = role.get("mentionable", false)`
- **Save:** Included in the role update payload as `"mentionable": _mentionable_check.button_pressed`, sent via `Client.update_role()`
- **Server model:** `AccordRole.mentionable` is a boolean (line 14 of `role.gd`)
- **Effect:** The flag controls server-side behavior (whether the API allows @mentioning the role).

### MENTION_EVERYONE Permission

The `MENTION_EVERYONE` permission (`permission.gd:23`) controls whether a user is allowed to use `@everyone` in messages:

- Defined as `const MENTION_EVERYONE := "mention_everyone"` in `AccordPermission`
- Included in the full permission list and exposed in the role editor's permission checkboxes
- **Client-side:** The composer shows a warning label when the user types `@everyone` without the `MENTION_EVERYONE` permission. The send is not blocked (the server enforces the permission), but the warning prevents user confusion.

### User Status: Do Not Disturb

Users can set their status to Do Not Disturb via the user bar menu (`user_bar.gd`):

- **UI:** `MenuButton` popup with four status options: Online, Idle, Do Not Disturb, Invisible
- **Selection:** Calls `Client.update_presence(ClientModels.UserStatus.DND)`, which broadcasts the status to all connected servers
- **Visual:** Status icon turns red (`Color(0.929, 0.259, 0.271)`) when DND
- **Model:** `ClientModels.UserStatus.DND` enum value (value 2) maps to/from the `"dnd"` string sent over the wire
- **Effect:** DND suppresses all notification indicators. `client_gateway.gd` skips unread tracking entirely when the user is in DND mode (line 364). `SoundManager` also suppresses notification sounds in DND mode (line 65 of `sound_manager.gd`).

### Local Notification Preferences (Config)

`Config` (`config.gd`) persists notification preferences in the encrypted per-profile config file:

- [x] SFX volume and per-event sound toggles (`get_sfx_volume()`, `is_sound_enabled()`, etc.)
- [x] Per-server mute/unmute setting (`is_server_muted()`, `set_server_muted()` in `[muted_servers]` section, line 495)
- [x] "Suppress @everyone" global toggle (`get_suppress_everyone()`, `set_suppress_everyone()` in `[notifications]` section, line 474)
- [x] Per-server suppress @everyone override (`get_server_suppress_everyone()`, `set_server_suppress_everyone()` in `[server_suppress]` section, line 484). Values: -1 = use global, 0 = don't suppress, 1 = suppress.
- [x] Per-channel notification level (`get_channel_notification_level()`, `set_channel_notification_level()` in `[channel_notifications]` section, line 521). Values: `"default"`, `"all"`, `"mentions"`, `"muted"`.
- [x] Per-thread notification level (`get_thread_notifications()`, `set_thread_notifications()` in `[thread_notifications]` section, line 509)

Sound preferences are managed via the Sound Settings dialog (accessible from the user bar menu). See [Application Sound Effects](application_sound_effects.md). The "Suppress @everyone" toggle is accessible from the user bar menu.

### Per-Server Notification Settings

Server-specific settings are available in **Server Settings** (`server_settings.gd`, lines 79-108):

- **Server mute toggle:** `Config.is_server_muted(_space_id)` / `Config.set_server_muted()` (lines 82-88)
- **Per-server @everyone suppress:** Three-option dropdown with "Use global default" / "Suppress on this server" / "Don't suppress on this server" (lines 92-106). Maps to `Config.get_server_suppress_everyone()` values -1/1/0.
- **Enforcement:** The gateway (lines 377-385 of `client_gateway.gd`) checks `Config.get_server_suppress_everyone(space_id)` first, falling back to the global `Config.get_suppress_everyone()` when the per-server override is -1.

## Implementation Status

### Notification Indicators
- [x] Space pill indicator (HIDDEN/UNREAD/ACTIVE states with animation)
- [x] Space mention badge (red pill with count, auto-hide at 0)
- [x] Channel unread dot (visibility + bold text)
- [x] DM unread dot (visibility toggle)
- [x] Message mention highlight (warm tint via structured `is_user_mentioned()` check)
- [x] AccordKit parses `mentions`, `mention_everyone`, `mention_roles` from server
- [x] Client-side unread tracking (`Client.mark_channel_unread()` updates channel/space caches)
- [x] Client-side mention counting (`_channel_mention_counts` aggregated to space level)
- [x] Passing mention data through `message_to_dict()` to UI layer
- [x] Using structured `mentions` array instead of string matching for highlights
- [x] Marking channels as read when viewed (`on_channel_selected_clear_unread()`)
- [x] `@everyone` / `@here` highlight support (via `mention_everyone` field)
- [x] Role mention highlight support (via `mention_roles` + user role lookup)

### Notification Options
- [x] Space default notification level UI ("All Messages" / "Mentions Only" in Space Settings)
- [x] Space default notification level saved to server via REST API
- [x] Role mentionable toggle UI (checkbox in Role Management)
- [x] Role mentionable flag saved to server via REST API
- [x] `MENTION_EVERYONE` permission in role editor
- [x] Do Not Disturb status option in user bar menu
- [x] DND status broadcast to all connected servers
- [x] DND visual indicator (red status dot)
- [x] Client-side enforcement of `default_notifications` setting (gateway checks before marking unread)
- [x] DND suppresses notification indicators locally (gateway skips unread tracking; SoundManager skips sounds)
- [x] Per-channel notification overrides (all, mentions, muted) via context menu submenu
- [x] Per-channel notification level enforced in gateway unread tracking
- [x] Per-channel notification level enforced in SoundManager sound playback
- [x] Per-channel notification level visual dimming (0.4 alpha for "muted" channels)
- [x] Per-server mute/unmute in local config (`Config.is_server_muted()` + space icon context menu)
- [x] "Suppress @everyone" user preference (`Config.get_suppress_everyone()` + user bar menu toggle)
- [x] Per-server suppress @everyone override (`Config.get_server_suppress_everyone()` + Server Settings UI)
- [x] Per-server suppress @everyone enforced in gateway (overrides global setting)
- [x] Sound preferences in `Config` (volume, per-event toggles, persisted to disk)
- [x] Per-channel notification preferences in `Config` (`[channel_notifications]` section)
- [x] Per-thread notification preferences in `Config` (`[thread_notifications]` section)
- [x] Notification sounds (see [Application Sound Effects](application_sound_effects.md))
- [x] Composer-side warning for `@everyone` without `MENTION_EVERYONE` permission
- [ ] OS-level desktop notifications (toasts)

### Channel Mute (Server-Side)
- [x] Mute/unmute via REST API (`PUT`/`DELETE /channels/:id/mute`)
- [x] Muted channels loaded from READY payload and `list_mutes()` endpoint
- [x] Real-time sync via `CHANNEL_MUTE_CREATE`/`CHANNEL_MUTE_DELETE` gateway events
- [x] Parent category mute inheritance (`is_channel_muted()` checks parent_id)
- [x] Context menu toggle on channel items, voice channel items, and category items
- [x] Visual dimming for muted channels
- [x] Gateway skips unread tracking for muted channels
- [x] SoundManager skips sounds for muted channels

### Server-Side Read State
- [x] Channel ack endpoint (`POST /channels/:id/ack` with last_message_id)
- [x] Ack sent when channel is viewed (`_ack_channel()` in `client_unread.gd`)
- [x] Ack sent even when channel is not locally unread (line 12 of `client_unread.gd`)
- [x] Server provides unread state on connect (READY payload `unread` array)
- [x] Unread state persists across app restarts

## Tasks

### NOTIF-1: No per-user notification overrides per space
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** config, ui
- **Notes:** The tooltip in Space Settings promises per-user overrides but no override mechanism exists beyond the per-channel level. A user cannot set their personal notification level for an entire space to override the admin-set default (e.g., "I want mentions-only for this space even though the admin set it to all").

### NOTIF-2: No OS-level notifications
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** api, audio, ui
- **Notes:** No calls to OS notification APIs, no system tray integration. Notification sounds exist (see [Application Sound Effects](application_sound_effects.md)) but there are no desktop toasts or system tray badges.
