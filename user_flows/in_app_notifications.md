# In-App Notifications

## Overview

daccord provides visual cues to notify users of new activity across guilds, channels, and DMs. The notification system has three layers: guild-level indicators (pills and mention badges on guild icons), channel-level indicators (unread dots and bold text on channel items), and message-level indicators (mention highlights on individual messages). Notification behavior is configurable at the space level (default notification setting) and per-role (mentionable toggle), and users can set their status to Do Not Disturb. There are no OS-level notifications (desktop toasts, system tray badges, or sounds), and no per-channel or per-user override settings.

## User Steps

1. User receives a message in a channel they are not currently viewing.
2. The guild icon's pill transitions from hidden to the UNREAD state (small dot).
3. If the message contains an `@mention` of the user, the guild icon's red mention badge appears showing the count.
4. In the channel list, the channel item's unread dot becomes visible and the channel name turns white (bold).
5. User clicks the guild icon, then clicks the channel with the unread indicator.
6. The message view loads; any message containing `@<display_name>` is tinted with a warm highlight color.
7. (Not yet implemented) Unread state clears when the user views the channel.

## Signal Flow

```
Gateway MESSAGE_CREATE
  └─> client_gateway.on_message_create()
        └─> Appends to _message_cache
        └─> AppState.messages_updated.emit(channel_id)
              └─> message_view._on_messages_updated()     // Renders messages if current channel
              └─> (No automatic unread tracking)

Note: Unread/mention state is NOT currently computed from gateway events.
      The "unread" and "mentions" fields in guild/channel dicts are
      hardcoded to false/0 by ClientModels and never updated at runtime.
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/guild_icon.gd` | Reads `unread`/`mentions` from guild dict, drives pill state and mention badge |
| `scenes/sidebar/guild_bar/pill.gd` | Three-state indicator (HIDDEN/UNREAD/ACTIVE) with animated transitions |
| `scenes/sidebar/guild_bar/mention_badge.gd` | Red circular badge showing mention count, auto-hides when count is 0 |
| `scenes/sidebar/guild_bar/mention_badge.tscn` | Badge scene with red `StyleBoxFlat` (Color 0.929, 0.259, 0.271) |
| `scenes/sidebar/channels/channel_item.gd` | Reads `unread` from channel dict, shows/hides unread dot and bolds name |
| `scenes/sidebar/direct/dm_channel_item.gd` | Reads `unread` from DM dict, shows/hides unread dot |
| `scripts/autoload/client_models.gd` | Converts AccordKit models to UI dicts; hardcodes `unread: false`, `mentions: 0` |
| `scripts/autoload/client_gateway.gd` | Handles MESSAGE_CREATE and other gateway events; no unread tracking logic |
| `scenes/messages/cozy_message.gd` | Applies mention highlight tint (line 71) |
| `scenes/messages/collapsed_message.gd` | Applies mention highlight tint (line 49) |
| `addons/accordkit/models/message.gd` | Parses `mention_everyone`, `mentions`, `mention_roles` from server data |
| `addons/accordkit/models/space.gd` | Has `default_notifications` field ("all" or "mentions") |
| `scenes/admin/space_settings_dialog.gd` | UI for configuring default notification level per space |
| `scenes/admin/role_management_dialog.gd` | UI for toggling role mentionable flag |
| `scenes/sidebar/user_bar.gd` | User status menu including Do Not Disturb option |
| `scripts/autoload/config.gd` | Persists server configs; no notification preferences stored |
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

Both `cozy_message.gd` (lines 68-72) and `collapsed_message.gd` (lines 46-50) apply a tint when the message content contains `@<display_name>`:

```gdscript
var content: String = data.get("content", "")
var current_user_name: String = Client.current_user.get("display_name", "")
if content.contains("@" + current_user_name):
    modulate = Color(1.0, 0.95, 0.85)
```

This is a simple string match -- it does not use the structured `mentions` array from AccordKit.

### Server-Side Mention Data (AccordKit)

`AccordMessage` (lines 16-18) parses three mention fields from the server:

- `mention_everyone: bool` -- whether `@everyone` was used
- `mentions: Array` -- array of user IDs who were mentioned
- `mention_roles: Array` -- array of role IDs that were mentioned

These are available in the AccordKit model but are **not** passed through to the UI dictionary by `ClientModels.message_to_dict()` (lines 226-237). The UI dict omits `mentions`, `mention_everyone`, and `mention_roles`.

### Default Notification Setting

`AccordSpace` has a `default_notifications` field (line 16) with values `"all"` or `"mentions"`. This is:

- Stored in the guild dict by `ClientModels.space_to_guild_dict()` (line 141)
- Editable via `space_settings_dialog.gd` (lines 29-30, 55-59, 79) with an OptionButton offering "All Messages" and "Mentions Only"
- **Not consumed** by any client-side notification logic -- the setting is saved to the server but never checked when determining whether to show unread/mention indicators

### Hardcoded Unread/Mention Values

`ClientModels` hardcodes notification state in all conversion functions:

- `space_to_guild_dict()`: `"unread": false, "mentions": 0` (lines 136-137)
- `channel_to_dict()`: `"unread": false` (line 164)
- `dm_channel_to_dict()`: `"unread": false` (line 280)

These values are never updated after initial creation, even when new messages arrive via the gateway.

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
- **Effect:** Server-side only. The client does not gate `@everyone` usage in the composer, nor does it check this permission when highlighting mentions.

### User Status: Do Not Disturb

Users can set their status to Do Not Disturb via the user bar menu (`user_bar.gd`):

- **UI:** `MenuButton` popup with four status options: Online, Idle, Do Not Disturb, Invisible (lines 14-17)
- **Selection:** Calls `Client.update_presence(ClientModels.UserStatus.DND)` (line 59), which broadcasts the status to all connected servers
- **Visual:** Status icon turns red (`Color(0.929, 0.259, 0.271)`) when DND (line 41)
- **Model:** `ClientModels.UserStatus.DND` enum value (value 2) maps to/from the `"dnd"` string sent over the wire (lines 37-38, 48-49 of `client_models.gd`)
- **Effect:** DND status is purely cosmetic. The client does **not** suppress notifications, sounds, or visual indicators when the user is in DND mode. Other users see the red status dot, but the local notification behavior is unchanged.

### Local Notification Preferences (Config)

`Config` (`config.gd`) persists server connection data to `user://config.cfg` but stores **no notification preferences**:

- No per-server mute/unmute setting
- No per-channel notification override
- No "suppress @everyone" toggle
- No desktop notification enable/disable flag
- No notification sound preferences

All notification configuration exists only server-side (space default, role mentionable). There is no local persistence layer for user notification preferences.

## Implementation Status

### Notification Indicators
- [x] Guild pill indicator (HIDDEN/UNREAD/ACTIVE states with animation)
- [x] Guild mention badge (red pill with count, auto-hide at 0)
- [x] Channel unread dot (visibility + bold text)
- [x] DM unread dot (visibility toggle)
- [x] Message mention highlight (warm tint for `@display_name`)
- [x] AccordKit parses `mentions`, `mention_everyone`, `mention_roles` from server
- [ ] Client-side unread tracking (all `unread` fields hardcoded to `false`)
- [ ] Client-side mention counting (all `mentions` fields hardcoded to `0`)
- [ ] Passing mention data through `message_to_dict()` to UI layer
- [ ] Using structured `mentions` array instead of string matching for highlights
- [ ] Marking channels as read when viewed
- [ ] `@everyone` / `@here` highlight support
- [ ] Role mention highlight support

### Notification Options
- [x] Space default notification level UI ("All Messages" / "Mentions Only" in Space Settings)
- [x] Space default notification level saved to server via REST API
- [x] Role mentionable toggle UI (checkbox in Role Management)
- [x] Role mentionable flag saved to server via REST API
- [x] `MENTION_EVERYONE` permission in role editor
- [x] Do Not Disturb status option in user bar menu
- [x] DND status broadcast to all connected servers
- [x] DND visual indicator (red status dot)
- [ ] Client-side enforcement of `default_notifications` setting
- [ ] DND suppresses notification indicators locally
- [ ] Per-channel notification overrides (mute, all, mentions only)
- [ ] Per-server mute/unmute in local config
- [ ] "Suppress @everyone" user preference
- [ ] Local notification preferences in `Config` (persisted to disk)
- [ ] OS-level desktop notifications (toasts)
- [ ] Notification sounds
- [ ] Composer-side gating of `@everyone` based on `MENTION_EVERYONE` permission

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Unread state never set to `true` | High | `ClientModels` hardcodes `"unread": false` (lines 136, 164, 280). No gateway handler increments unread counts. The pill, dot, and badge UI all work but receive no live data. |
| Mention count never incremented | High | `ClientModels` hardcodes `"mentions": 0` (line 137). `on_message_create()` in `client_gateway.gd` (line 65) does not check `msg.mentions` or update guild mention counts. |
| `default_notifications` setting is write-only | High | Space Settings lets admins set "All Messages" or "Mentions Only" (`space_settings_dialog.gd:79`), but the client never reads this value to filter which messages trigger unread/mention indicators. The tooltip promises per-user overrides (`space_settings_dialog.tscn:131`) but no override mechanism exists. |
| `message_to_dict()` drops mention fields | Medium | The UI dictionary (`client_models.gd:226-237`) does not include `mentions`, `mention_everyone`, or `mention_roles` from AccordKit. Mention highlighting relies on naive string matching (`@display_name`) instead. |
| String-based mention detection is fragile | Medium | `cozy_message.gd:71` and `collapsed_message.gd:49` use `content.contains("@" + name)` which can false-positive on substrings (e.g., user "Al" matches "@Alice") and misses mentions by username vs display name. |
| DND status does not suppress notifications | Medium | Setting status to DND (`user_bar.gd:59`) broadcasts the status to other users but has no effect on local notification behavior. Unread dots, mention badges, and highlights appear identically regardless of DND state. |
| No read-state tracking | Medium | No mechanism to mark a channel as "read" when the user views it. There is no `read_state` cache, no `ack` API call, and no last-read message ID tracking. |
| Role mentionable flag unused client-side | Medium | The mentionable toggle (`role_management_dialog.gd:191`) is saved to the server, but the client does not check `role.mentionable` when rendering mention highlights or determining if a role mention should notify the user. |
| No local notification preferences | Medium | `Config` (`config.gd`) stores no notification settings. Users cannot persist per-server mute state, suppress @everyone preference, or desktop notification toggles locally. |
| No `@everyone`/`@here` support | Low | `AccordMessage.mention_everyone` is parsed (`message.gd:16`) but never used in the UI. Messages with `@everyone` receive no special highlighting. |
| No role mention support | Low | `AccordMessage.mention_roles` is parsed (`message.gd:18`) but the UI does not check if the current user has a mentioned role. |
| `MENTION_EVERYONE` not enforced in composer | Low | The `MENTION_EVERYONE` permission (`permission.gd:23`) is only used server-side. The composer does not prevent users without this permission from typing `@everyone`. |
| No OS-level notifications | Low | No calls to OS notification APIs, no system tray integration, no notification sounds. The app provides no alerts when the window is not focused. |
| No per-channel notification overrides | Low | Only a space-wide `default_notifications` setting exists. Users cannot mute individual channels or set per-channel notification levels. |
