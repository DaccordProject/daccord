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
| `scripts/autoload/client_models.gd` | `space_to_dict()` (lines 283-311) — currently omits `system_channel_id`; `message_to_dict()` system flag (line 448) |
| `scenes/messages/message_content.gd` | System message rendering: italic + muted color (lines 59-68, 163-169) |
| `scenes/members/member_list.gd` | `_on_member_joined()` handler for member list UI updates |
| `scenes/admin/space_settings_dialog.gd` | Space settings UI — no system channel picker yet |
| `../accordserver/src/models/space.rs` | `system_channel_id: Option<String>` field |
| `../accordserver/src/db/spaces.rs` | System channel ID stored/updated in DB |
| `../accordserver/migrations/002_expand_schema.sql` | `system_channel_id TEXT` column on spaces table |
| `../accordserver/src/db/messages.rs` | `create_message()` — no system message generation on join |

## Implementation Details

### Existing Infrastructure

#### System Channel ID (model layer — exists but unused)
The `AccordSpace` model already has a `system_channel_id` field (line 28 of `space.gd`), parsed from the server response at lines 74-77. The accordserver stores this field in the `spaces` table (`002_expand_schema.sql` line 17) and handles updates via the space update endpoint.

However, `ClientModels.space_to_dict()` (lines 283-311) does **not** include `system_channel_id` in the returned dictionary — it's parsed but never surfaced to UI code.

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

#### Server-Side: System Message Generation
When a member joins a space, if `system_channel_id` is set, the server should:
1. Create a message in that channel with `type = "member_join"` and `author_id` set to the joining user
2. Set content to a localizable string like `"{username} joined the server."`
3. Broadcast the message via the gateway `message.create` event

This logic belongs in the member join handler in `accordserver/src/routes/auth.rs` (register + join) and `accordserver/src/routes/invites.rs` (invite accept).

#### Client-Side: Surface `system_channel_id` in Space Dict
Add `system_channel_id` to the dictionary returned by `ClientModels.space_to_dict()` so UI code can reference it.

#### Client-Side: System Channel Admin Setting
Add a "System Messages Channel" dropdown to `space_settings_dialog.gd` that:
- Lists all text channels in the space
- Shows the current `system_channel_id` selection (or "None")
- Sends a space update PATCH with the new `system_channel_id`

#### Client-Side: System Message Content Formatting
Currently system messages render raw content. For `member_join` type messages, the client should format the content with the member's display name bolded and a localized welcome string, e.g.:
> _**Alice** joined the server. Welcome!_

A wave emoji reaction button could be shown inline on join messages to encourage greeting.

#### Client-Side: Welcome Prompt (Optional Enhancement)
When the system channel is selected and a member join message appears, show a subtle prompt like "Wave to welcome them!" with a one-click wave reaction button.

## Implementation Status
- [x] `system_channel_id` field in AccordSpace model (client + server)
- [x] `system_channel_id` stored and updated in server database
- [x] Member join gateway event pipeline (`member_join` → `AppState.member_joined`)
- [x] System message rendering (italic, muted, BBCode-safe)
- [x] System message type detection (`type != "default"` → `system: true`)
- [x] Emoji reaction system (works on any message including system messages)
- [x] Member list real-time updates on join/leave
- [ ] Server generates system message on member join in system channel
- [ ] `system_channel_id` included in `space_to_dict()` output
- [ ] System channel picker in space settings admin UI
- [ ] Rich formatting for `member_join` system messages (bold username, localized text)
- [ ] "Wave to welcome" prompt on join messages
- [ ] Sound effect on member join announcement (via SoundManager)
- [ ] Unread indicator on system channel for join messages
- [ ] Configurable system message types (join, leave, boost, etc.)

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Server does not generate system messages on member join | High | `accordserver/src/routes/auth.rs` and `invites.rs` broadcast `member.join` gateway events but never create a message in `system_channel_id` |
| `system_channel_id` not in `space_to_dict()` | High | `client_models.gd` line 293-311 — field is parsed (space.gd line 28) but omitted from the dict, so no UI can reference it |
| No system channel picker in admin UI | High | `space_settings_dialog.gd` has no dropdown for selecting the system messages channel |
| No rich formatting for system messages | Medium | `message_content.gd` renders system messages as plain italic text; `member_join` type should show bold username + localized welcome string |
| No "wave to welcome" affordance | Medium | No UI prompt or shortcut to add a wave reaction to join messages; users must use the standard reaction flow |
| No join/leave sound effect | Low | `SoundManager` plays sounds for voice join/leave but not for text channel member join announcements |
| No configurable system message types | Low | Discord supports toggling join messages, boost messages, etc. separately — no equivalent toggle exists |
| Message type enum not formalized | Low | `AccordMessage.type` is a free-form string; no enum or constant defines valid system message types like `"member_join"`, `"member_leave"` |
