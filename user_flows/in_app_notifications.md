# In-App Notifications


## Overview

daccord provides visual cues to notify users of new activity across guilds, channels, and DMs. The notification system has three layers: guild-level indicators (pills and mention badges on guild icons), channel-level indicators (unread dots and bold text on channel items), and message-level indicators (mention highlights on individual messages). Notification behavior is configurable at the space level (default notification setting) and per-role (mentionable toggle). Users can set their status to Do Not Disturb to suppress all notification indicators, mute individual servers via context menu, and suppress @everyone mentions via a user preference toggle. There are no OS-level notifications (desktop toasts, system tray badges) and no per-channel override settings.

## User Steps

1. User receives a message in a channel they are not currently viewing.
2. The gateway handler checks DND status, server mute, `default_notifications` setting, and suppress @everyone before marking unread.
3. If notifications are not suppressed, the guild icon's pill transitions from hidden to the UNREAD state (small dot).
4. If the message mentions the user (by ID, @everyone, or role), the guild icon's red mention badge increments.
5. In the channel list, the channel item's unread dot becomes visible and the channel name turns white (bold).
6. User clicks the guild icon, then clicks the channel with the unread indicator.
7. The message view loads; any message that mentions the user (via structured `mentions` array, `mention_everyone`, or `mention_roles`) is tinted with a warm highlight color.
8. Unread state clears when the user views the channel (via `_on_channel_selected_clear_unread`).

## Signal Flow

```
Gateway MESSAGE_CREATE
  └─> client_gateway.on_message_create()
        └─> Appends to _message_cache (message dict includes mentions, mention_everyone, mention_roles)
        └─> Checks DND status → if DND, skips unread tracking
        └─> Checks Config.is_server_muted() → if muted, skips unread tracking
        └─> Determines is_mention (user ID in mentions, mention_everyone + suppress check, role mentions)
        └─> Checks guild default_notifications → if "mentions" and not a mention, skips
        └─> Calls Client.mark_channel_unread(channel_id, is_mention)
              └─> Updates _unread_channels, _channel_mention_counts
              └─> Updates _channel_cache[cid]["unread"] = true
              └─> Calls _update_guild_unread() to aggregate guild-level unread/mention counts
              └─> Emits channels_updated + guilds_updated
        └─> SoundManager.play_for_message() (also checks DND)
        └─> AppState.messages_updated.emit(channel_id)
              └─> message_view renders messages; ClientModels.is_user_mentioned() drives highlight tint

Channel selected
  └─> Client._on_channel_selected_clear_unread()
        └─> Erases from _unread_channels and _channel_mention_counts
        └─> Updates channel/DM dict unread = false
        └─> Recalculates guild unread/mentions
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_icon.gd` | Reads `unread`/`mentions` from guild dict, drives pill state and mention badge; "Mute Server"/"Unmute Server" context menu; dimmed visual when muted |
| `scenes/sidebar/guild_bar/pill.gd` | Three-state indicator (HIDDEN/UNREAD/ACTIVE) with animated transitions |
| `scenes/sidebar/guild_bar/mention_badge.gd` | Red circular badge showing mention count, auto-hides when count is 0 |
| `scenes/sidebar/guild_bar/mention_badge.tscn` | Badge scene with red `StyleBoxFlat` (Color 0.929, 0.259, 0.271) |
| `scenes/sidebar/channels/channel_item.gd` | Reads `unread` from channel dict, shows/hides unread dot and bolds name |
| `scenes/sidebar/direct/dm_channel_item.gd` | Reads `unread` from DM dict, shows/hides unread dot |
| `scripts/autoload/client_models.gd` | Converts AccordKit models to UI dicts; `message_to_dict()` includes `mentions`, `mention_everyone`, `mention_roles`; `is_user_mentioned()` helper for structured mention checks |
| `scripts/autoload/client_gateway.gd` | Handles MESSAGE_CREATE; enforces DND suppression, server mute, `default_notifications`, suppress @everyone, and role mention checks before marking channels unread |
| `scripts/autoload/client.gd` | Manages `_unread_channels` and `_channel_mention_counts` dicts; `mark_channel_unread()` updates channel/guild caches and emits signals; `_on_channel_selected_clear_unread()` clears read state |
| `scenes/messages/cozy_message.gd` | Uses `ClientModels.is_user_mentioned()` for structured mention highlight tint |
| `scenes/messages/collapsed_message.gd` | Uses `ClientModels.is_user_mentioned()` for structured mention highlight tint |
| `scenes/messages/composer/composer.gd` | Warns when user types `@everyone` without `MENTION_EVERYONE` permission |
| `addons/accordkit/models/message.gd` | Parses `mention_everyone`, `mentions`, `mention_roles` from server data |
| `addons/accordkit/models/space.gd` | Has `default_notifications` field ("all" or "mentions") |
| `scenes/admin/space_settings_dialog.gd` | UI for configuring default notification level per space |
| `scenes/admin/role_management_dialog.gd` | UI for toggling role mentionable flag |
| `scenes/sidebar/user_bar.gd` | User status menu including Do Not Disturb; "Suppress @everyone" toggle |
| `scripts/autoload/config.gd` | Persists server configs, sound preferences, notification preferences (`suppress_everyone`, `muted_servers`) |
| `addons/accordkit/models/role.gd` | Parses `mentionable` flag from server |
| `addons/accordkit/models/permission.gd` | Defines `MENTION_EVERYONE` permission constant |

## Implementation Details

### Guild-Level Indicators (Pill + Mention Badge)

`guild_icon.gd` reads notification state from the guild dictionary during `setup()` (line 64-73):

- `_has_unread = data.get("unread", false)` -- boolean driving pill state
- `mentions = data.get("mentions", 0)` -- integer driving badge visibility
- The pill has three states: `HIDDEN` (no activity), `UNREAD` (6px dot), `ACTIVE` (20px bar for selected guild)
- `set_active()` (line 75-83) transitions pill state with animation via `set_state_animated()`
- The mention badge (`mention_badge.gd`, line 3-8) auto-shows when `count > 0` and hides when `count == 0`
- Badge styled as red rounded pill (corner radius 8, bg `Color(0.929, 0.259, 0.271)`)

### Pill Animation

`pill.gd` implements smooth height transitions (line 29-40):

- `set_state_animated()` uses a `Tween` to animate `custom_minimum_size.y` and `size.y`
- UNREAD state: 6px height; ACTIVE state: 20px height
- Animation duration: 0.15 seconds

### Channel-Level Indicators (Unread Dot)

`channel_item.gd` reads unread state in `setup()` (lines 71-76):

- `unread_dot.visible = has_unread` -- a `ColorRect` node toggled by the `unread` field
- When unread, channel name turns white (`Color(1, 1, 1)`); otherwise muted gray (`Color(0.58, 0.608, 0.643)`)

### DM-Level Indicators

`dm_channel_item.gd` reads unread state in `setup()` (line 24):

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

- Stored in the guild dict by `ClientModels.space_to_guild_dict()`
- Editable via `space_settings_dialog.gd` with an OptionButton offering "All Messages" and "Mentions Only"
- **Enforced** by `client_gateway.gd` in `on_message_create()`: when a guild's `default_notifications` is `"mentions"`, non-mention messages do not trigger unread indicators

### Unread/Mention Tracking

`ClientModels` initializes notification state to defaults (`"unread": false`, `"mentions": 0`) in all conversion functions. At runtime, `Client.mark_channel_unread()` updates these values in the channel/guild caches when new messages arrive via the gateway. `_on_channel_selected_clear_unread()` resets the state when a channel is viewed.

## Notification Options

### Space Default Notification Level

Admins can configure the space-wide default notification level in **Space Settings** (`space_settings_dialog.gd`):

- **UI:** An `OptionButton` with two items: "All Messages" (id 0) and "Mentions Only" (id 1) (lines 29-30)
- **Tooltip:** "The default notification setting applied to new members. They can override this individually." (`space_settings_dialog.tscn:131`)
- **Load:** Reads `guild.get("default_notifications", "all")` and selects the matching option (lines 55-59)
- **Save:** Sends `"default_notifications": notif_levels[selected]` to the server via `Client.update_space()` (line 79), where `notif_levels = ["all", "mentions"]` (line 73)
- **Server model:** `AccordSpace.default_notifications` stores the value as a string, defaulting to `"all"` (line 16 of `space.gd`)
- **Effect:** The setting is persisted server-side and included in the guild dict (`client_models.gd:141`), but **no client-side code reads it** to filter which incoming messages trigger unread/mention indicators. It is effectively write-only.

### Role Mentionable Toggle

Admins can control whether a role can be @mentioned in **Role Management** (`role_management_dialog.gd`):

- **UI:** A `CheckBox` labeled "Allow anyone to mention this role" (lines 28-29, `role_management_dialog.tscn:156`)
- **Tooltip:** "Anyone can @mention this role to notify all members who have it." (`role_management_dialog.tscn:161`)
- **Load:** `_mentionable_check.button_pressed = role.get("mentionable", false)` (line 152)
- **Save:** Included in the role update payload as `"mentionable": _mentionable_check.button_pressed` (line 191), sent via `Client.update_role()`
- **Server model:** `AccordRole.mentionable` is a boolean (line 14 of `role.gd`), stored in the role dict as `"mentionable"` (`client_models.gd:292`)
- **Effect:** The flag controls server-side behavior (whether the API allows @mentioning the role). The client does **not** use this flag when rendering mention highlights or counting mentions.

### MENTION_EVERYONE Permission

The `MENTION_EVERYONE` permission (`permission.gd:23`) controls whether a user is allowed to use `@everyone` in messages:

- Defined as `const MENTION_EVERYONE := "mention_everyone"` in `AccordPermission`
- Included in the full permission list (`permission.gd:64`) and exposed in the role editor's permission checkboxes
- **Client-side:** The composer shows a warning label when the user types `@everyone` without the `MENTION_EVERYONE` permission. The send is not blocked (the server enforces the permission), but the warning prevents user confusion.
- **Server-side:** The server blocks unauthorized `@everyone` mentions.

### User Status: Do Not Disturb

Users can set their status to Do Not Disturb via the user bar menu (`user_bar.gd`):

- **UI:** `MenuButton` popup with four status options: Online, Idle, Do Not Disturb, Invisible
- **Selection:** Calls `Client.update_presence(ClientModels.UserStatus.DND)`, which broadcasts the status to all connected servers
- **Visual:** Status icon turns red (`Color(0.929, 0.259, 0.271)`) when DND
- **Model:** `ClientModels.UserStatus.DND` enum value (value 2) maps to/from the `"dnd"` string sent over the wire
- **Effect:** DND suppresses all notification indicators. `client_gateway.gd` skips unread tracking entirely when the user is in DND mode. `SoundManager` also suppresses notification sounds in DND mode.

### Local Notification Preferences (Config)

`Config` (`config.gd`) persists server connection data to `user://config.cfg`. It stores **sound preferences** in the `[sounds]` section and **notification preferences** in the `[notifications]` and `[muted_servers]` sections:

- [x] SFX volume and per-event sound toggles (`get_sfx_volume()`, `is_sound_enabled()`, etc.)
- [x] Per-server mute/unmute setting (`is_server_muted()`, `set_server_muted()` in `[muted_servers]` section)
- [x] "Suppress @everyone" toggle (`get_suppress_everyone()`, `set_suppress_everyone()` in `[notifications]` section)
- [ ] Per-channel notification override
- [ ] Desktop notification enable/disable flag

Sound preferences are managed via the Sound Settings dialog (accessible from the user bar menu). See [Application Sound Effects](application_sound_effects.md). The "Suppress @everyone" toggle is accessible from the user bar menu.

## Implementation Status

### Notification Indicators
- [x] Guild pill indicator (HIDDEN/UNREAD/ACTIVE states with animation)
- [x] Guild mention badge (red pill with count, auto-hide at 0)
- [x] Channel unread dot (visibility + bold text)
- [x] DM unread dot (visibility toggle)
- [x] Message mention highlight (warm tint via structured `is_user_mentioned()` check)
- [x] AccordKit parses `mentions`, `mention_everyone`, `mention_roles` from server
- [x] Client-side unread tracking (`Client.mark_channel_unread()` updates channel/guild caches)
- [x] Client-side mention counting (`_channel_mention_counts` aggregated to guild level)
- [x] Passing mention data through `message_to_dict()` to UI layer
- [x] Using structured `mentions` array instead of string matching for highlights
- [x] Marking channels as read when viewed (`_on_channel_selected_clear_unread()`)
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
- [ ] Per-channel notification overrides (mute, all, mentions only)
- [x] Per-server mute/unmute in local config (`Config.is_server_muted()` + guild icon context menu)
- [x] "Suppress @everyone" user preference (`Config.get_suppress_everyone()` + user bar menu toggle)
- [x] Sound preferences in `Config` (volume, per-event toggles, persisted to disk)
- [ ] Per-channel notification preferences in `Config`
- [ ] OS-level desktop notifications (toasts)
- [x] Notification sounds (see [Application Sound Effects](application_sound_effects.md))
- [x] Composer-side warning for `@everyone` without `MENTION_EVERYONE` permission

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No per-channel notification overrides | Medium | Only a space-wide `default_notifications` setting exists. Users cannot mute individual channels or set per-channel notification levels. Requires new UI (per-channel settings dialog). |
| No per-user notification overrides per space | Medium | The tooltip in Space Settings promises per-user overrides (`space_settings_dialog.tscn:131`) but no override mechanism exists. Currently only the space-wide default is enforced. |
| No OS-level notifications | Low | No calls to OS notification APIs, no system tray integration. Notification sounds exist (see [Application Sound Effects](application_sound_effects.md)) but there are no desktop toasts or system tray badges. |
| No server-side read-state ack | Low | Unread state is tracked client-side only. There is no `ack` API call or server-side last-read message ID. Unread state resets on app restart. |

*Last touched: 2026-02-19*
