# Server Welcoming

## Overview
Discord-style server welcoming: when a new member joins a space, a system message is automatically posted in the designated system/welcome channel announcing their arrival. Other members can react to the welcome message (e.g. wave emoji) to greet the newcomer. Admins configure which channel receives these join announcements via space settings.

## User Steps

### Admin: Configure Welcome Channel
1. Open space settings (right-click space icon → "Settings")
2. Navigate to the "Overview" or "General" section
3. Select a text channel from the "System Messages Channel" dropdown
4. Save — the server stores the `system_channel_id` on the space

### New Member Joins
1. A user joins the space (via invite link or server discovery)
2. The server generates a system message in the configured system channel: _"**Username** joined the server. Welcome!"_
3. The message appears in the welcome channel with system message styling (italic, muted color)
4. Other members see the join announcement in real-time via the gateway

### Existing Members React
1. A member sees the join announcement in the welcome channel
2. They click the reaction button (or right-click → "Add Reaction") on the system message
3. They select a wave emoji (or any emoji) from the picker
4. The reaction pill appears on the welcome message, visible to all members including the newcomer

## Signal Flow

```
[Server-side: member joins space]
        │
        ▼
GatewaySocket.member_join ──────────────────────────────────┐
        │                                                    │
        ▼                                                    ▼
ClientGatewayMembers                              [Server generates system
  .on_member_join()                                message in system_channel]
        │                                                    │
        ├─► AppState.member_joined                           ▼
        │     .emit(space_id, member_dict)        GatewaySocket.message_create
        │         │                                          │
        │         ▼                                          ▼
        │   MemberList                              MessageList renders
        │     ._on_member_joined()                  system message (italic,
        │                                           muted color)
        ├─► AppState.members_updated                         │
              .emit(space_id)                                ▼
                                                    Members react with
                                                    wave emoji (existing
                                                    reaction flow)
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/space.gd` | `system_channel_id` field (line 28), parsed from API (lines 74-77) |
| `addons/accordkit/models/message.gd` | `type` field (line 11), supports values beyond `"default"` |
| `scripts/autoload/app_state.gd` | `member_joined` signal (line 32), `member_left` signal (line 34) |
| `scripts/autoload/client_gateway_members.gd` | `on_member_join()` (lines 44-73), emits `member_joined` |
| `scripts/autoload/client_models.gd` | `space_to_dict()` includes `system_channel_id` (line 332); `message_to_dict()` includes `message_type` (line 470) and `system` flag (line 469) |
| `scripts/autoload/sound_manager.gd` | `member_join` sound entry (line 18); `play_for_message()` routes `member_join` type to dedicated sound (line 86) |
| `scripts/autoload/client_gateway.gd` | Passes `message.type` to `SoundManager.play_for_message()` (line 385) |
| `scenes/messages/message_content.gd` | Rich `member_join` rendering: bold accent name + muted welcome text (lines 68-77); `_add_wave_button()` (lines 199-231); generic system messages fall through to italic text |
| `scenes/members/member_list.gd` | `_on_member_joined()` handler for member list UI updates |
| `scenes/admin/space_settings_dialog.gd` | "System Messages Channel" dropdown: build (lines 75-97), populate (lines 179-191), save (lines 208-212) |
| `../accordserver/src/models/space.rs` | `system_channel_id: Option<String>` field |
| `../accordserver/src/db/spaces.rs` | System channel ID stored/updated in DB |
| `../accordserver/migrations/002_expand_schema.sql` | `system_channel_id TEXT` column on spaces table |
| `../accordserver/src/db/messages.rs` | `create_message()` + `create_system_message()` for custom message types (line 216) |
| `../accordserver/src/routes/system_messages.rs` | `broadcast_member_join_message()` — shared helper for all join paths |

## Implementation Details

### Existing Infrastructure

#### System Channel ID (model layer — fully wired)
The `AccordSpace` model has a `system_channel_id` field (line 28 of `space.gd`), parsed from the server response at lines 74-77. The accordserver stores this field in the `spaces` table (`002_expand_schema.sql` line 17) and handles updates via the space update endpoint. `ClientModels.space_to_dict()` (line 332) now includes `system_channel_id` in the returned dictionary, surfacing it to UI code.

#### System Message Rendering (exists)
`message_content.gd` already handles system messages. When `data.get("system", false)` is true (line 59), the content is rendered as italic text in the `text_muted` theme color, with BBCode brackets escaped to prevent injection (lines 61-68). The `system` flag is computed by `ClientModels.message_to_dict()` at line 448: `msg.type != "default" and msg.type != "reply"`.

This means any message with a type like `"member_join"` would already render correctly as a system message.

#### Member Join Gateway Event (exists)
The full pipeline is wired:
1. `GatewaySocket` emits `member_join(member: AccordMember)` (line 25 of `gateway_socket.gd`)
2. `ClientGateway` connects it to `ClientGatewayMembers.on_member_join()` (line 35 of `client_gateway.gd`)
3. `on_member_join()` caches the member and emits `AppState.member_joined` (line 72) and `AppState.members_updated` (line 73)
4. `MemberList._on_member_joined()` inserts the new member into the list UI

#### Reaction System (exists)
The emoji reaction system is fully implemented. Members can add reactions to any message via the reaction button or context menu. Reaction pills render below messages with click-to-toggle. This works on system messages too — no changes needed.

### What Needs to Be Built

#### Server-Side: System Message Generation (implemented)
When a member joins a space, if `system_channel_id` is set, the server:
1. Looks up the space to check for a configured `system_channel_id`
2. Creates a message in that channel with `type = "member_join"` and `author_id` set to the joining user
3. Sets content to `"{display_name} joined the server."`
4. Broadcasts the message via the gateway `message.create` event

The shared helper `broadcast_member_join_message()` in `system_messages.rs` is called from all three join paths:
- `routes/invites.rs` — invite accept (line 77)
- `routes/spaces.rs` — public space join (line 414)
- `routes/auth.rs` — auto-join default space on registration (line 502)

The helper uses `db::messages::create_system_message()` which inserts with a custom `type` column value instead of the default `"default"`.

#### Client-Side: Surface `system_channel_id` in Space Dict (implemented)
`ClientModels.space_to_dict()` now includes `system_channel_id` (line 332), following the same nullable-to-string pattern as `rules_channel_id`.

#### Client-Side: System Channel Admin Setting (implemented)
`space_settings_dialog.gd` now has a "System Messages Channel" dropdown (lines 75-97) that:
- Lists all text channels in the space prefixed with `#`
- Shows the current `system_channel_id` selection (or "None")
- Sends a space update PATCH with the new `system_channel_id` (lines 208-212)
- Follows the same pattern as the existing "Rules Channel" dropdown

#### Client-Side: Rich `member_join` Formatting (implemented)
`message_content.gd` now differentiates `member_join` from other system messages via the `message_type` field (added to `message_to_dict()` at line 470). For `member_join` messages:
- Author display name rendered in bold accent color
- " joined the server. Welcome!" in muted italic
- A "Wave to welcome!" button is shown below the message (lines 199-231) that sends a wave emoji reaction with one click

#### Client-Side: Sound Effect (implemented)
`SoundManager` now has a `"member_join"` sound entry (line 18, reuses `message_received.wav`). The gateway handler passes `message.type` to `play_for_message()` (line 385 of `client_gateway.gd`), which routes `member_join` messages to the dedicated sound regardless of window focus or current channel.

## Implementation Status
- [x] `system_channel_id` field in AccordSpace model (client + server)
- [x] `system_channel_id` stored and updated in server database
- [x] Member join gateway event pipeline (`member_join` → `AppState.member_joined`)
- [x] System message rendering (italic, muted, BBCode-safe)
- [x] System message type detection (`type != "default"` → `system: true`)
- [x] Emoji reaction system (works on any message including system messages)
- [x] Member list real-time updates on join/leave
- [x] Server generates system message on member join in system channel
- [x] `system_channel_id` included in `space_to_dict()` output
- [x] System channel picker in space settings admin UI
- [x] Rich formatting for `member_join` system messages (bold username, localized text)
- [x] "Wave to welcome" button on join messages
- [x] Sound effect on member join announcement (via SoundManager)
- [x] Unread indicator on system channel for join messages (works via existing `message.create` gateway flow)
- [ ] Dedicated `member_join` audio file (currently reuses `message_received.wav`)
- [ ] Configurable system message types (join, leave, boost, etc.)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No dedicated `member_join` audio file | Low | `SoundManager` reuses `message_received.wav` for the `member_join` sound; a distinct chime would improve discoverability |
| No configurable system message types | Low | Discord supports toggling join messages, boost messages, etc. separately — no equivalent toggle exists |
| Message type enum not formalized | Low | `AccordMessage.type` is a free-form string; no enum or constant defines valid system message types like `"member_join"`, `"member_leave"` |
| No `member_leave` system message | Low | Server only generates `member_join` messages; no equivalent for when a member leaves |
