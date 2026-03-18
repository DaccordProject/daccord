# Gateway Events

Priority: 3
Depends on: Server Connection, Data Model

## Overview

daccord maintains real-time sync with accordserver via WebSocket gateway connections. AccordKit's GatewaySocket handles the WebSocket lifecycle (connect, heartbeat, reconnection, session resume). Gateway events are dispatched as typed signals on AccordClient, which ClientGateway listens to and translates into cache updates + AppState signal emissions. This creates a clean separation: AccordKit handles transport, ClientGateway handles state, AppState notifies the UI.

Gateway event handling is split across four classes:
- **ClientGateway** — lifecycle, messages, typing, presence, user, spaces, channels, roles
- **ClientGatewayEvents** — admin/entity events (bans, invites, emojis, soundboard, plugins, channel mutes, relationships, voice, anonymous count)
- **ClientGatewayMembers** — member join/leave/update/chunk
- **ClientGatewayReactions** — reaction add/remove/clear/clear_emoji

## Event Flow

```
accordserver
    -> WebSocket JSON frame: {op: 0, type: "event.type", data: {...}}
    -> GatewaySocket._dispatch_event(event_type, data)
        -> Parses data into typed model (AccordMessage, AccordChannel, etc.)
        -> Emits typed signal (e.g., message_create(message: AccordMessage))
    -> AccordClient re-emits signal (proxied from GatewaySocket)
    -> ClientGateway.on_[event_handler](model, conn_index)
        -> Updates appropriate cache (_message_cache, _channel_cache, etc.)
        -> Emits AppState signal (messages_updated, channels_updated, etc.)
    -> UI components react to AppState signals
        -> Re-render affected views
```

## Signal Flow

Event-to-Signal Mapping:

```
Gateway Event              -> Handler Class / Method          -> AppState Signal
─────────────────────────────────────────────────────────────────────────────────
ready                      -> CG.on_gateway_ready()           -> (refetch all data + server_reconnected if was down)
message.create             -> CG.on_message_create()          -> messages_updated(channel_id)
message.update             -> CG.on_message_update()          -> messages_updated(channel_id)
message.delete             -> CG.on_message_delete()          -> messages_updated(channel_id)
message.delete_bulk        -> CG.on_message_delete_bulk()     -> messages_updated(channel_id)
typing.start               -> CG.on_typing_start()            -> typing_started + typing_stopped (10s) or thread_typing_*
presence.update            -> CG.on_presence_update()         -> user_updated + members_updated + relationships_updated
user.update                -> CG.on_user_update()             -> user_updated(user_id) + members_updated(per space)
space.create               -> CG.on_space_create()            -> spaces_updated()
space.update               -> CG.on_space_update()            -> spaces_updated()
space.delete               -> CG.on_space_delete()            -> spaces_updated()
channel.create             -> CG.on_channel_create()          -> channels_updated(space_id) or dm_channels_updated()
channel.update             -> CG.on_channel_update()          -> channels_updated(space_id) or dm_channels_updated()
channel.delete             -> CG.on_channel_delete()          -> channels_updated(space_id) or dm_channels_updated()
channel.reorder            -> CG.on_channel_reorder()         -> channels_updated(space_id)
channel.pins_update        -> CG.on_channel_pins_update()     -> messages_updated(channel_id)
channel_mute.create        -> CGE.on_channel_mute_create()    -> channel_mutes_updated()
channel_mute.delete        -> CGE.on_channel_mute_delete()    -> channel_mutes_updated()
member.join                -> CGM.on_member_join()             -> members_updated(space_id)
member.leave               -> CGM.on_member_leave()            -> members_updated(space_id)
member.update              -> CGM.on_member_update()           -> members_updated(space_id)
member.chunk               -> CGM.on_member_chunk()            -> members_updated(space_id)
role.create                -> CG.on_role_create()              -> roles_updated(space_id)
role.update                -> CG.on_role_update()              -> roles_updated(space_id)
role.delete                -> CG.on_role_delete()              -> roles_updated(space_id)
reaction.add               -> CGR.on_reaction_add()            -> messages_updated(channel_id)
reaction.remove            -> CGR.on_reaction_remove()         -> messages_updated(channel_id)
reaction.clear             -> CGR.on_reaction_clear()          -> messages_updated(channel_id)
reaction.clear_emoji       -> CGR.on_reaction_clear_emoji()    -> messages_updated(channel_id)
voice.state_update         -> CGE.on_voice_state_update()      -> voice_state_updated(channel_id)
voice.server_update        -> CGE.on_voice_server_update()     -> (stores info + reconnects backend)
voice.signal               -> CGE.on_voice_signal()            -> (no-op, LiveKit handles signaling)
ban.create                 -> CGE.on_ban_create()              -> bans_updated(space_id)
ban.delete                 -> CGE.on_ban_delete()              -> bans_updated(space_id)
report.create              -> CGE.on_report_create()           -> reports_updated(space_id)
invite.create              -> CGE.on_invite_create()           -> invites_updated(space_id)
invite.delete              -> CGE.on_invite_delete()           -> invites_updated(space_id)
emoji.create               -> CGE.on_emoji_create()            -> emojis_updated(space_id)
emoji.update               -> CGE.on_emoji_update()            -> emojis_updated(space_id)
emoji.delete               -> CGE.on_emoji_delete()            -> emojis_updated(space_id)
interaction.create         -> CGE.on_interaction_create()      -> (no-op, no interaction UI)
soundboard.create          -> CGE.on_soundboard_create()       -> soundboard_updated(space_id)
soundboard.update          -> CGE.on_soundboard_update()       -> soundboard_updated(space_id)
soundboard.delete          -> CGE.on_soundboard_delete()       -> soundboard_updated(space_id)
soundboard.play            -> CGE.on_soundboard_play()         -> soundboard_played(space_id, sound_id, user_id)
plugin.installed           -> CGE.on_plugin_installed()        -> (delegates to ClientPlugins)
plugin.uninstalled         -> CGE.on_plugin_uninstalled()      -> (delegates to ClientPlugins)
plugin.event               -> CGE.on_plugin_event()            -> (delegates to ClientPlugins)
plugin.session_state       -> CGE.on_plugin_session_state()    -> (delegates to ClientPlugins)
plugin.role_changed        -> CGE.on_plugin_role_changed()     -> (delegates to ClientPlugins)
anonymous_count.update     -> CGE.on_anonymous_count_updated() -> anonymous_count_updated(space_id, count)
relationship.add           -> CGE.on_relationship_add()        -> relationships_updated() + friend_request_received
relationship.update        -> CGE.on_relationship_update()     -> relationships_updated()
relationship.remove        -> CGE.on_relationship_remove()     -> relationships_updated()
─────────────────────────────────────────────────────────────────────────────────
(disconnected)             -> CG.on_gateway_disconnected()     -> server_disconnected(space_id, code, reason)
(reconnecting)             -> CG.on_gateway_reconnecting()     -> server_reconnecting(space_id, attempt, max)
(resumed)                  -> CG.on_gateway_reconnected()      -> server_reconnected(space_id)
(raw_event)                -> CG.on_gateway_raw_event()        -> server_reconnected (silent reconnect detection)
```

Handler class abbreviations: CG = ClientGateway, CGE = ClientGatewayEvents, CGM = ClientGatewayMembers, CGR = ClientGatewayReactions

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket connection, heartbeat, reconnection, event dispatch (508 lines) |
| `addons/accordkit/gateway/gateway_opcodes.gd` | Opcode constants: EVENT(0), HEARTBEAT(1), IDENTIFY(2), RESUME(3), HEARTBEAT_ACK(4), HELLO(5), RECONNECT(6), INVALID_SESSION(7), PRESENCE_UPDATE(8), VOICE_STATE_UPDATE(9), REQUEST_MEMBERS(10), VOICE_SIGNAL(11) |
| `addons/accordkit/gateway/gateway_intents.gd` | Intent flags: SPACES, MODERATION, EMOJIS, VOICE_STATES, MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING, DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING, SCHEDULED_EVENTS, plus privileged: MEMBERS, PRESENCES, MESSAGE_CONTENT |
| `addons/accordkit/core/accord_client.gd` | Proxies all gateway signals, provides public API |
| `scripts/autoload/client_gateway.gd` | Core gateway handlers: lifecycle, messages, typing, presence, user, spaces, channels, roles (761 lines) |
| `scripts/autoload/client_gateway_events.gd` | Admin/entity/voice/plugin/relationship event handlers (329 lines) |
| `scripts/autoload/client_gateway_members.gd` | Member join/leave/update/chunk handlers (113 lines) |
| `scripts/autoload/client_gateway_reactions.gd` | Reaction add/remove/clear handlers |
| `scripts/autoload/client_voice.gd` | Voice channel join/leave, video/screen tracks, voice session callbacks |
| `scripts/autoload/client.gd` | Signal wiring via `ClientGateway.connect_signals()`, caches, routing |
| `scripts/autoload/client_admin.gd` | Admin REST API + populates ban/invite caches on fetch |
| `scripts/autoload/app_state.gd` | UI-facing signals |

## Implementation Details

### Gateway Connection Lifecycle (gateway_socket.gd)

State enum: `{ DISCONNECTED, CONNECTING, CONNECTED, RESUMING }`

Connection sequence:
1. `connect_to_gateway(url)` -> WebSocket connects to `gateway_url?v=1&encoding=json`
2. Server sends HELLO (op 5) with `heartbeat_interval`
3. Client sends IDENTIFY (op 2) with token, intents, properties
4. Server sends READY (op 0, type: "ready") with session_id and user data
5. Heartbeat loop: sends HEARTBEAT (op 1) at server-specified interval
6. Server responds with HEARTBEAT_ACK (op 4)

Reconnection:
- Automatic on unexpected disconnect
- Exponential backoff with jitter: `delay = 1.0 * 2^attempt + random(0..1)`, capped at `2^5`
- Max attempts: 10 (`_max_reconnect_attempts`)
- Session resume: sends RESUME (op 3) with session_id and last sequence number
- Non-reconnectable close codes: 4003, 4004, 4012, 4013, 4014 (invalid session, auth failure, etc.)
- After exhausting gateway reconnects, `ClientGateway.on_gateway_reconnecting()` escalates to `Client._handle_gateway_reconnect_failed()`, which attempts a full reconnect with re-authentication (once per disconnect cycle)

Additional server-requested opcodes:
- RECONNECT (op 6): server requests reconnect; client closes with code 4000 and triggers `_attempt_reconnect()`
- INVALID_SESSION (op 7): if not resumable, clears session_id; waits 1-5s random then reconnects; gives up after max attempts

Heartbeat:
- Interval from HELLO payload (default 45000ms if not provided)
- If HEARTBEAT_ACK not received before next heartbeat -> reconnect (close with code 4000)
- `_heartbeat_ack_received` flag tracks acknowledgement

### Intents (gateway_intents.gd)

Client.gd configures intents on connect:
- Uses `GatewayIntents.all()` which includes all unprivileged + privileged intents

Unprivileged: SPACES, MODERATION, EMOJIS, VOICE_STATES, MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING, DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING, SCHEDULED_EVENTS

Privileged: MEMBERS, PRESENCES, MESSAGE_CONTENT

### Event Dispatch (gateway_socket.gd)

`_dispatch_event(event_type, data)` (line 307) matches event type string and:
1. Parses raw Dictionary into typed model (e.g., `AccordMessage.from_dict(data)`)
2. Emits the typed signal (e.g., `message_create.emit(message)`)
3. Always emits `raw_event(event_type, data)` as a catch-all (line 425)

Supported event types (50 total from gateway_socket.gd dispatch):
- Lifecycle: ready, resumed
- Spaces: space.create, space.update, space.delete
- Channels: channel.create, channel.update, channel.delete, channel.reorder, channel.pins_update, channel_mute.create, channel_mute.delete
- Members: member.join, member.leave, member.update, member.chunk
- Roles: role.create, role.update, role.delete
- Messages: message.create, message.update, message.delete, message.delete_bulk
- Reactions: reaction.add, reaction.remove, reaction.clear, reaction.clear_emoji
- Presence: presence.update, typing.start
- User: user.update
- Voice: voice.state_update, voice.server_update, voice.signal
- Bans: ban.create, ban.delete
- Reports: report.create
- Invites: invite.create, invite.delete
- Interactions: interaction.create
- Plugins: plugin.installed, plugin.uninstalled, plugin.event, plugin.session_state, plugin.role_changed
- Anonymous: anonymous_count.update
- Emojis: emoji.create, emoji.update, emoji.delete
- Soundboard: soundboard.create, soundboard.update, soundboard.delete, soundboard.play
- Relationships: relationship.add, relationship.update, relationship.remove

### ClientGateway Event Handlers (client_gateway.gd)

Each handler follows the pattern: receive typed model -> update cache -> emit AppState signal.

**Lifecycle:**

`on_gateway_ready(data, conn_index)` (line 130):
- Clears `_auto_reconnect_attempted` for this connection
- If reconnecting after disconnect, emits `server_reconnected`
- Calls `_refetch_data()` to fetch roles, members, channels, DMs, relationships, mutes, unread
- Applies initial presences from READY payload via `_apply_presences()`

`on_gateway_disconnected(code, reason, conn_index)` (line 178):
- On fatal close codes (4003, 4004, 4012, 4013, 4014): escalates to `_handle_gateway_reconnect_failed()` for full reconnect with re-auth
- On other codes: sets status to "disconnected", emits `server_disconnected`

`on_gateway_reconnecting(attempt, max_attempts, conn_index)` (line 201):
- Sets connection status to "reconnecting", emits `server_reconnecting`
- If attempts exhausted, escalates to `_handle_gateway_reconnect_failed()`

`on_gateway_reconnected(conn_index)` (line 218):
- Sets status to "connected", emits `server_reconnected`
- Also calls `_refetch_data()` since RESUME path needs to re-sync after server restart

`on_gateway_raw_event(event_type, data, conn_index)` (line 229):
- Silent reconnect detector: if connection status is not "connected", marks it connected and emits `server_reconnected`

**Messages:**

`on_message_create(message, conn_index)` (line 261):
- Fetches unknown author from REST if not in `_user_cache`
- Handles thread replies: routes to `_thread_message_cache`, updates parent `reply_count`, updates forum post cache
- Handles forum posts: top-level message in forum channel goes to `_forum_post_cache`
- Converts to dict, appends to `_message_cache[channel_id]`
- Updates `_message_id_index` for O(1) lookup
- Enforces MESSAGE_CAP (50) via `pop_front()`, cleaning up index for evicted messages
- Tracks unread + mentions for non-current channels (skips own messages, respects DND, channel/server mute, default_notifications setting)
- Plays notification sound via SoundManager
- Updates DM channel `last_message` preview if applicable
- Emits `messages_updated`

`on_message_update(message, conn_index)` (line 398):
- Handles thread replies: updates in `_thread_message_cache`
- Updates forum post cache if applicable
- Finds message in `_message_cache` by ID, replaces dict
- Emits `messages_updated`

`on_message_delete(data)` (line 435):
- Receives raw Dictionary (by design — gateway only sends id and channel_id for deletes)
- Checks thread message cache first, decrements parent `reply_count`
- Checks forum post cache
- Falls back to main `_message_cache` removal
- Cleans up `_message_id_index`
- Emits `messages_updated`

`on_message_delete_bulk(data)` (line 477):
- Extracts channel_id and ids array from raw dict
- Builds an ID set for O(n) removal, iterates messages in reverse
- Removes matching messages from `_message_cache`, cleans up `_message_id_index`
- Emits `messages_updated` once after all removals

**Typing:**

`on_typing_start(data)` (line 495):
- Extracts user_id and channel_id
- Skips if typing user is current user
- Looks up display_name from `_user_cache` (falls back to "Someone")
- Thread-scoped typing: if `thread_id` present, emits `thread_typing_started/stopped` instead
- Emits `typing_started(channel_id, username)`
- Creates/resets a 10-second one-shot Timer that emits `typing_stopped(channel_id)` on expiry
- Timers are tracked per channel in `_typing_timers` dict and added to the Client node (since ClientGateway is RefCounted)

**Presence:**

`on_presence_update(presence, conn_index)` (line 539):
- Updates `_user_cache[user_id].status`, `client_status`, and `activities`
- Emits `user_updated(user_id)`
- Updates matching relationship cache entry, emits `relationships_updated` if found
- Updates matching member dict in `_member_cache`, emits `member_status_changed` on status change, emits `members_updated(space_id)`

**User:**

`on_user_update(user, conn_index)` (line 576):
- Preserves existing status from `_user_cache` (defaults to OFFLINE)
- Updates `_user_cache[user_id]` with fresh dict via `ClientModels.user_to_dict()`
- Updates `current_user` if the updated user is the logged-in user
- Propagates display_name/avatar/username changes to all `_member_cache` entries
- Emits `user_updated(user_id)` and `members_updated` per affected space

**Members (ClientGatewayMembers):**

`on_member_join(member, conn_index)`:
- Fetches unknown user from REST if not in `_user_cache`
- Converts to dict via `ClientModels.member_to_dict()`, appends to `_member_cache[space_id]`
- Updates `_member_id_index`
- Emits `member_joined(space_id, member_dict)` and `members_updated(space_id)`

`on_member_leave(data, conn_index)`:
- Extracts user_id (tries `user_id` field, then `user.id` nested field)
- Removes from `_member_cache[space_id]` by user_id, rebuilds `_member_id_index`
- Emits `members_updated(space_id)`

`on_member_update(member, conn_index)`:
- Converts to dict, finds and replaces in `_member_cache[space_id]`
- If not found, appends (handles late-arriving member data)
- Updates `_member_id_index`
- Emits `members_updated(space_id)`

`on_member_chunk(data, conn_index)`:
- Processes bulk member data from `request_members()` responses
- Extracts embedded user dicts and populates `_user_cache` via `AccordUser.from_dict()`
- Deduplicates against existing members using an ID index
- Updates or appends each member in `_member_cache[space_id]`
- Emits `members_updated(space_id)`

**Spaces:**

`on_space_create(space, conn_index)` (line 605):
- Only processes if space.id matches connection's space_id
- Updates `_space_cache` with folder from Config, emits `spaces_updated`

`on_space_update(space)` (line 615):
- Preserves unread/mentions/folder from old cache entry
- Updates `_space_cache` if space exists, emits `spaces_updated`

`on_space_delete(data)` (line 626):
- Erases from `_space_cache` and `_space_to_conn`, emits `spaces_updated`

**Channels:**

`on_channel_create(channel, conn_index)` (line 632):
- If DM/group_dm: caches recipients, adds to `_dm_channel_cache`, emits `dm_channels_updated`
- Else: adds to `_channel_cache` and `_channel_to_space`, emits `channels_updated(space_id)`

`on_channel_update(channel, conn_index)` (line 654):
- Same DM vs space channel logic as create, preserves unread and voice_users counts

`on_channel_delete(channel)` (line 682):
- If DM/group_dm: erases from `_dm_channel_cache`, emits `dm_channels_updated`
- Else: erases from `_channel_cache` and `_channel_to_space`, emits `channels_updated(space_id)`

`on_channel_reorder(data, conn_index)` (line 692):
- Processes bulk channel position updates
- Updates `_channel_cache` entries preserving unread and voice_users
- Emits `channels_updated(space_id)`

`on_channel_pins_update(data)` (line 597):
- Extracts channel_id from raw dict
- Emits `messages_updated(channel_id)` so UI can refresh pinned messages

**Roles:**

`on_role_create(data, conn_index)` (line 712):
- Parses `AccordRole` from data (tries `data.role` then `data` itself)
- Converts via `ClientModels.role_to_dict()`, appends to `_role_cache[space_id]`
- Emits `roles_updated(space_id)`

`on_role_update(data, conn_index)` (line 723):
- Parses role, finds and replaces in `_role_cache[space_id]` by ID
- Emits `roles_updated(space_id)`

`on_role_delete(data, conn_index)` (line 737):
- Extracts role_id (tries `role_id` then `id`), removes from `_role_cache[space_id]`
- Emits `roles_updated(space_id)`

### ClientGatewayEvents Handlers (client_gateway_events.gd)

**Bans:**

`on_ban_create(data, conn_index)` (line 14):
- Appends ban data to `_ban_cache[space_id]` (deduplicates by user_id)
- Emits `bans_updated(space_id)`

`on_ban_delete(data, conn_index)` (line 31):
- Removes matching ban from `_ban_cache[space_id]` by user_id
- Emits `bans_updated(space_id)`

**Reports:**

`on_report_create(data, conn_index)` (line 26):
- Emits `reports_updated(space_id)`

**Invites:**

`on_invite_create(invite, conn_index)` (line 45):
- Converts `AccordInvite` to dict via `ClientModels.invite_to_dict()`
- Appends to `_invite_cache[space_id]` (deduplicates by code)
- Emits `invites_updated(space_id)`

`on_invite_delete(data, conn_index)` (line 63):
- Removes matching invite from `_invite_cache[space_id]` by code
- Emits `invites_updated(space_id)`

**Channel Mutes:**

`on_channel_mute_create(data)` (line 89):
- Adds channel_id to `_muted_channels` dict
- Emits `channel_mutes_updated()`

`on_channel_mute_delete(data)` (line 95):
- Removes channel_id from `_muted_channels` dict
- Emits `channel_mutes_updated()`

**Emojis:**

`on_emoji_create/update/delete(data, conn_index)` (lines 71-87):
- Emits `emojis_updated(space_id)` (triggers re-fetch)

**Soundboard:**

`on_soundboard_create/update(sound, conn_index)` (lines 44-54):
- Emits `soundboard_updated(space_id)` (triggers re-fetch)

`on_soundboard_delete(data, conn_index)` (line 56):
- Emits `soundboard_updated(space_id)` (triggers re-fetch)

`on_soundboard_play(data, conn_index)` (line 62):
- Extracts sound_id and user_id, emits `soundboard_played(space_id, sound_id, user_id)`

**Interactions:**

`on_interaction_create(interaction, conn_index)` (line 101):
- No-op handler; wired to prevent silent signal drop

**Plugins:**

`on_plugin_installed/uninstalled/event/session_state/role_changed(data, conn_index)` (lines 108-131):
- Delegates to `ClientPlugins` methods after connection validation

**Anonymous Count:**

`on_anonymous_count_updated(data, conn_index)` (line 135):
- Extracts count, emits `anonymous_count_updated(space_id, count)`

**Voice:**

`on_voice_state_update(state, conn_index)` (line 144):
- Ensures user is cached (fetches from REST if missing)
- Ensures user is in member cache for the space (creates stub entry if missing)
- Converts to dict via `ClientModels.voice_state_to_dict()`
- Ignores self updates without backend credentials (prevents phantom self-connection)
- Removes user from any previous channel in `_voice_state_cache`
- Adds user to new channel if non-empty
- Updates `voice_users` count in `_channel_cache` for affected channels
- Emits `voice_state_updated` for both old and new channels
- Plays peer join/leave sound via SoundManager
- Detects force-disconnect: if own user's channel becomes empty while in voice, calls `AppState.leave_voice()`

`on_voice_server_update(info, conn_index)` (line 227):
- Stores voice server info dict in `_voice_server_info`
- If already in a voice channel, (re)connects the backend with new credentials

`on_voice_signal(data, conn_index)` (line 245):
- No-op (LiveKit handles signaling internally)

**Relationships:**

`on_relationship_add(rel, conn_index)` (line 250):
- Converts to dict, stores in `_relationship_cache` keyed by `"{conn_index}:{user_id}"`
- Emits `relationships_updated()`
- Auto-declines friend requests from blocked users
- Emits `friend_request_received(user_id)` for pending incoming requests

`on_relationship_update(rel, conn_index)` (line 265):
- Updates relationship in cache, emits `relationships_updated()`

`on_relationship_remove(data, conn_index)` (line 274):
- Erases from `_relationship_cache`, emits `relationships_updated()`

### Gateway Signal Wiring (client_gateway.gd:20-128)

When connecting a server, `ClientGateway.connect_signals()` wires AccordClient signals to handlers. Multi-server support uses `.bind(conn_index)` to pass the connection index. Handlers are distributed across CG (ClientGateway), CGE (_events), CGM (_members), CGR (_reactions):

```
client.ready_received       -> CG.on_gateway_ready.bind(idx)
client.message_create       -> CG.on_message_create.bind(idx)
client.message_update       -> CG.on_message_update.bind(idx)
client.message_delete       -> CG.on_message_delete          (no bind, raw dict)
client.message_delete_bulk  -> CG.on_message_delete_bulk     (no bind, raw dict)
client.typing_start         -> CG.on_typing_start             (no bind)
client.presence_update      -> CG.on_presence_update.bind(idx)
client.member_join          -> CGM.on_member_join.bind(idx)
client.member_leave         -> CGM.on_member_leave.bind(idx)
client.member_update        -> CGM.on_member_update.bind(idx)
client.member_chunk         -> CGM.on_member_chunk.bind(idx)
client.user_update          -> CG.on_user_update.bind(idx)
client.space_create         -> CG.on_space_create.bind(idx)
client.space_update         -> CG.on_space_update              (no bind)
client.space_delete         -> CG.on_space_delete              (no bind)
client.channel_create       -> CG.on_channel_create.bind(idx)
client.channel_update       -> CG.on_channel_update.bind(idx)
client.channel_delete       -> CG.on_channel_delete            (no bind)
client.channel_reorder      -> CG.on_channel_reorder.bind(idx)
client.channel_pins_update  -> CG.on_channel_pins_update      (no bind)
client.channel_mute_create  -> CGE.on_channel_mute_create     (no bind)
client.channel_mute_delete  -> CGE.on_channel_mute_delete     (no bind)
client.role_create          -> CG.on_role_create.bind(idx)
client.role_update          -> CG.on_role_update.bind(idx)
client.role_delete          -> CG.on_role_delete.bind(idx)
client.ban_create           -> CGE.on_ban_create.bind(idx)
client.ban_delete           -> CGE.on_ban_delete.bind(idx)
client.report_create        -> CGE.on_report_create.bind(idx)
client.invite_create        -> CGE.on_invite_create.bind(idx)
client.invite_delete        -> CGE.on_invite_delete.bind(idx)
client.anonymous_count_updated -> CGE.on_anonymous_count_updated.bind(idx)
client.emoji_create         -> CGE.on_emoji_create.bind(idx)
client.emoji_update         -> CGE.on_emoji_update.bind(idx)
client.emoji_delete         -> CGE.on_emoji_delete.bind(idx)
client.interaction_create   -> CGE.on_interaction_create.bind(idx)
client.plugin_installed     -> CGE.on_plugin_installed.bind(idx)
client.plugin_uninstalled   -> CGE.on_plugin_uninstalled.bind(idx)
client.plugin_event         -> CGE.on_plugin_event.bind(idx)
client.plugin_session_state -> CGE.on_plugin_session_state.bind(idx)
client.plugin_role_changed  -> CGE.on_plugin_role_changed.bind(idx)
client.soundboard_create    -> CGE.on_soundboard_create.bind(idx)
client.soundboard_update    -> CGE.on_soundboard_update.bind(idx)
client.soundboard_delete    -> CGE.on_soundboard_delete.bind(idx)
client.soundboard_play      -> CGE.on_soundboard_play.bind(idx)
client.reaction_add         -> CGR.on_reaction_add             (no bind)
client.reaction_remove      -> CGR.on_reaction_remove          (no bind)
client.reaction_clear       -> CGR.on_reaction_clear           (no bind)
client.reaction_clear_emoji -> CGR.on_reaction_clear_emoji    (no bind)
client.voice_state_update   -> CGE.on_voice_state_update.bind(idx)
client.voice_server_update  -> CGE.on_voice_server_update.bind(idx)
client.voice_signal         -> CGE.on_voice_signal.bind(idx)
client.relationship_add     -> CGE.on_relationship_add.bind(idx)
client.relationship_update  -> CGE.on_relationship_update.bind(idx)
client.relationship_remove  -> CGE.on_relationship_remove.bind(idx)
client.disconnected         -> CG.on_gateway_disconnected.bind(idx)
client.reconnecting         -> CG.on_gateway_reconnecting.bind(idx)
client.resumed              -> CG.on_gateway_reconnected.bind(idx)
client.raw_event            -> CG.on_gateway_raw_event.bind(idx)
```

## Implementation Status

- [x] WebSocket gateway connection with IDENTIFY handshake
- [x] Heartbeat loop with ACK tracking
- [x] Automatic reconnection with exponential backoff and jitter
- [x] Session resume on reconnect
- [x] Non-reconnectable close code handling
- [x] Escalation to full reconnect with re-auth after gateway reconnect exhaustion
- [x] Server-requested reconnect (RECONNECT opcode)
- [x] INVALID_SESSION handling (resumable vs non-resumable)
- [x] Intent-based event filtering (all intents enabled)
- [x] All 50 event types parsed and dispatched
- [x] Message create/update/delete/delete_bulk -> cache + signal
- [x] Message ID index for O(1) lookup
- [x] Thread reply routing (thread_message_cache, parent reply_count)
- [x] Forum post routing (forum_post_cache)
- [x] Unread/mention tracking on message create (respects DND, mute, notification level)
- [x] DM last_message preview on message create
- [x] Typing start -> signal (skips own user) + 10s timeout emits typing_stopped
- [x] Thread-scoped typing (thread_typing_started/stopped)
- [x] Presence update -> user cache + member cache + relationship cache + signal
- [x] User update -> user cache + current_user + member cache propagation + signal
- [x] Space create/update/delete -> cache + signal
- [x] Channel create/update/delete -> cache + signal (DM vs space routing)
- [x] Channel reorder -> bulk cache update + signal
- [x] Channel mute create/delete -> _muted_channels cache + signal
- [x] Member join/leave/update/chunk -> member cache + member_id_index + signal
- [x] Role create/update/delete -> role cache + signal
- [x] Reaction add/remove/clear/clear_emoji -> message cache + signal
- [x] Voice state update -> voice state cache + channel voice_users count + member cache + signal
- [x] Voice server update -> stores server info + reconnects backend if in voice
- [x] Voice signal -> no-op (LiveKit handles signaling)
- [x] Voice force-disconnect detection (server clears own user's channel)
- [x] Ban create/delete -> local ban cache + signal
- [x] Invite create/delete -> local invite cache + signal
- [x] Report create -> signal
- [x] Channel pins update -> signal (triggers message refresh)
- [x] Emoji create/update/delete -> signal (triggers re-fetch)
- [x] Interaction create -> wired (no-op, no interaction UI)
- [x] Soundboard create/update/delete/play -> signal
- [x] Plugin installed/uninstalled/event/session_state/role_changed -> delegates to ClientPlugins
- [x] Anonymous count update -> signal
- [x] Relationship add/update/remove -> relationship cache + signal
- [x] Multi-server event routing via conn_index binding
- [x] raw_event catch-all signal for unhandled events + silent reconnect detection
- [x] Gateway disconnect/reconnect/reconnected -> AppState signals for UI feedback
- [x] Notification sounds via SoundManager (message, voice join/leave)
- [x] REST fetch of ban/invite lists populates local caches (client_admin.gd)

## Tasks

### GW-2: Ban/invite handlers don't cache
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** api, performance, ui
- **Notes:** Added `_ban_cache` and `_invite_cache` dictionaries to `client.gd` (keyed by space_id → Array of dicts). Gateway handlers in `client_gateway_events.gd` now append/remove entries on `ban.create/delete` and `invite.create/delete`. `client_admin.gd` populates these caches when fetching ban/invite lists via REST. Admin dialogs still re-fetch on signal for authoritative data but the cache is available for instant reads.
