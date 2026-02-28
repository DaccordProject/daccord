# Gateway Events


## Overview

daccord maintains real-time sync with accordserver via WebSocket gateway connections. AccordKit's GatewaySocket handles the WebSocket lifecycle (connect, heartbeat, reconnection, session resume). Gateway events are dispatched as typed signals on AccordClient, which ClientGateway listens to and translates into cache updates + AppState signal emissions. This creates a clean separation: AccordKit handles transport, ClientGateway handles state, AppState notifies the UI.

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
Gateway Event              -> ClientGateway Handler          -> AppState Signal
─────────────────────────────────────────────────────────────────────────────────
ready                      -> on_gateway_ready()             -> (fetch channels, members, roles, DMs)
message.create             -> on_message_create()            -> messages_updated(channel_id)
message.update             -> on_message_update()            -> messages_updated(channel_id)
message.delete             -> on_message_delete()            -> messages_updated(channel_id)
message.delete_bulk        -> on_message_delete_bulk()       -> messages_updated(channel_id)
typing.start               -> on_typing_start()              -> typing_started(channel_id, username) + typing_stopped (10s timeout)
presence.update            -> on_presence_update()           -> user_updated(user_id) + members_updated(space_id)
user.update                -> on_user_update()               -> user_updated(user_id)
space.create               -> on_space_create()              -> spaces_updated()
space.update               -> on_space_update()              -> spaces_updated()
space.delete               -> on_space_delete()              -> spaces_updated()
channel.create             -> on_channel_create()            -> channels_updated(space_id) or dm_channels_updated()
channel.update             -> on_channel_update()            -> channels_updated(space_id) or dm_channels_updated()
channel.delete             -> on_channel_delete()            -> channels_updated(space_id) or dm_channels_updated()
channel.pins_update        -> on_channel_pins_update()       -> messages_updated(channel_id)
member.join                -> on_member_join()               -> members_updated(space_id)
member.leave               -> on_member_leave()              -> members_updated(space_id)
member.update              -> on_member_update()             -> members_updated(space_id)
member.chunk               -> on_member_chunk()              -> members_updated(space_id)
role.create                -> on_role_create()               -> roles_updated(space_id)
role.update                -> on_role_update()               -> roles_updated(space_id)
role.delete                -> on_role_delete()               -> roles_updated(space_id)
reaction.add               -> on_reaction_add()              -> messages_updated(channel_id)
reaction.remove            -> on_reaction_remove()           -> messages_updated(channel_id)
reaction.clear             -> on_reaction_clear()            -> messages_updated(channel_id)
reaction.clear_emoji       -> on_reaction_clear_emoji()      -> messages_updated(channel_id)
voice.state_update         -> on_voice_state_update()        -> voice_state_updated(channel_id)
voice.server_update        -> on_voice_server_update()       -> (stores voice server info)
voice.signal               -> on_voice_signal()              -> (forwards to AccordVoiceSession)
ban.create                 -> on_ban_create()                -> bans_updated(space_id)
ban.delete                 -> on_ban_delete()                -> bans_updated(space_id)
invite.create              -> on_invite_create()             -> invites_updated(space_id)
invite.delete              -> on_invite_delete()             -> invites_updated(space_id)
emoji.update               -> on_emoji_update()              -> emojis_updated(space_id)
interaction.create         -> on_interaction_create()        -> (no-op, no interaction UI)
soundboard.create          -> on_soundboard_create()         -> soundboard_updated(space_id)
soundboard.update          -> on_soundboard_update()         -> soundboard_updated(space_id)
soundboard.delete          -> on_soundboard_delete()         -> soundboard_updated(space_id)
soundboard.play            -> on_soundboard_play()           -> soundboard_played(space_id, sound_id, user_id)
─────────────────────────────────────────────────────────────────────────────────
(disconnected)             -> on_gateway_disconnected()      -> server_disconnected(space_id, code, reason)
(reconnecting)             -> on_gateway_reconnecting()      -> server_reconnecting(space_id, attempt, max)
(resumed)                  -> on_gateway_reconnected()       -> server_reconnected(space_id)
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket connection, heartbeat, reconnection, event dispatch (440 lines) |
| `addons/accordkit/gateway/gateway_opcodes.gd` | Opcode constants: EVENT(0), HEARTBEAT(1), IDENTIFY(2), RESUME(3), HEARTBEAT_ACK(4), HELLO(5), RECONNECT(6), INVALID_SESSION(7), PRESENCE_UPDATE(8), VOICE_STATE_UPDATE(9), REQUEST_MEMBERS(10), VOICE_SIGNAL(11) |
| `addons/accordkit/gateway/gateway_intents.gd` | Intent flags: SPACES, MODERATION, EMOJIS, VOICE_STATES, MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING, DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING, SCHEDULED_EVENTS, plus privileged: MEMBERS, PRESENCES, MESSAGE_CONTENT |
| `addons/accordkit/core/accord_client.gd` | Proxies all gateway signals, provides public API |
| `scripts/autoload/client_gateway.gd` | Gateway event handlers, cache mutation, AppState signal emission (524 lines) |
| `scripts/autoload/client_voice.gd` | Voice channel join/leave, video/screen tracks, voice session callbacks |
| `scripts/autoload/client.gd` | Signal wiring (`_connect_gateway_signals`, lines 297-375), caches, routing |
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

Client.gd configures intents on connect (line 293):
- Uses `GatewayIntents.all()` which includes all unprivileged + privileged intents

Unprivileged: SPACES, MODERATION, EMOJIS, VOICE_STATES, MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING, DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING, SCHEDULED_EVENTS

Privileged: MEMBERS, PRESENCES, MESSAGE_CONTENT

### Event Dispatch (gateway_socket.gd)

`_dispatch_event(event_type, data)` matches event type string and:
1. Parses raw Dictionary into typed model (e.g., `AccordMessage.from_dict(data)`)
2. Emits the typed signal (e.g., `message_create.emit(message)`)
3. Always emits `raw_event(event_type, data)` as a catch-all

Supported event types (all from gateway_socket.gd signals):
- Lifecycle: ready, resumed
- Spaces: space.create, space.update, space.delete
- Channels: channel.create, channel.update, channel.delete, channel.pins_update
- Members: member.join, member.leave, member.update, member.chunk
- Roles: role.create, role.update, role.delete
- Messages: message.create, message.update, message.delete, message.delete_bulk
- Reactions: reaction.add, reaction.remove, reaction.clear, reaction.clear_emoji
- Presence: presence.update, typing.start
- User: user.update
- Voice: voice.state_update, voice.server_update, voice.signal
- Bans: ban.create, ban.delete
- Invites: invite.create, invite.delete
- Interactions: interaction.create
- Emojis: emoji.update
- Soundboard: soundboard.create, soundboard.update, soundboard.delete, soundboard.play

### ClientGateway Event Handlers (client_gateway.gd)

Each handler follows the pattern: receive typed model -> update cache -> emit AppState signal.

**Lifecycle:**

`on_gateway_ready(data, conn_index)` (line 13):
- Clears `_auto_reconnect_attempted` for this connection
- If reconnecting after disconnect, emits `server_reconnected`
- Fetches channels, members, and roles for the connection's space
- Fetches DM channels

`on_gateway_disconnected(code, reason, conn_index)` (line 30):
- On fatal close codes (4003, 4004, 4012, 4013, 4014): escalates to `_handle_gateway_reconnect_failed()` for full reconnect with re-auth
- On other codes: sets status to "disconnected", emits `server_disconnected`

`on_gateway_reconnecting(attempt, max_attempts, conn_index)` (line 49):
- Sets connection status to "reconnecting", emits `server_reconnecting`
- If attempts exhausted, escalates to `_handle_gateway_reconnect_failed()`

`on_gateway_reconnected(conn_index)` (line 64):
- Sets status to "connected", emits `server_reconnected`

**Messages:**

`on_message_create(message, conn_index)` (line 73):
- Fetches unknown author from REST if not in `_user_cache`
- Converts to dict, appends to `_message_cache[channel_id]`
- Updates `_message_id_index` for O(1) lookup
- Enforces MESSAGE_CAP (50) via `pop_front()`, cleaning up index for evicted messages
- Tracks unread + mentions for non-current channels (skips own messages)
- Updates DM channel `last_message` preview if applicable
- Emits `messages_updated`

`on_message_update(message, conn_index)` (line 117):
- Finds message in `_message_cache` by ID, replaces dict
- Emits `messages_updated`

`on_message_delete(data)` (line 130):
- Extracts id and channel_id from raw dict (not typed model)
- Finds and removes from `_message_cache`, cleans up `_message_id_index`
- Emits `messages_updated`

`on_message_delete_bulk(data)`:
- Extracts channel_id and ids array from raw dict
- Builds an ID set for O(n) removal, iterates messages in reverse
- Removes matching messages from `_message_cache`, cleans up `_message_id_index`
- Emits `messages_updated` once after all removals

**Typing:**

`on_typing_start(data)` (line 143):
- Extracts user_id and channel_id
- Skips if typing user is current user
- Looks up username from `_user_cache` (falls back to "Someone")
- Emits `typing_started(channel_id, username)`
- Creates/resets a 10-second one-shot Timer that emits `typing_stopped(channel_id)` on expiry
- Timers are tracked per channel in `_typing_timers` dict and added to the Client node (since ClientGateway is RefCounted)

**Presence:**

`on_presence_update(presence, conn_index)` (line 152):
- Updates `_user_cache[user_id].status` via `_status_string_to_enum()`
- Emits `user_updated(user_id)`
- Also updates matching member dict in `_member_cache` and emits `members_updated(space_id)`

**User:**

`on_user_update(user, conn_index)`:
- Preserves existing status from `_user_cache` (defaults to OFFLINE)
- Updates `_user_cache[user_id]` with fresh dict via `ClientModels.user_to_dict()`
- Updates `current_user` if the updated user is the logged-in user
- Emits `user_updated(user_id)`

**Members:**

`on_member_join(member, conn_index)` (line 165):
- Fetches unknown user from REST if not in `_user_cache`
- Converts to dict via `ClientModels.member_to_dict()`, appends to `_member_cache[space_id]`
- Emits `members_updated(space_id)`

`on_member_leave(data, conn_index)` (line 187):
- Extracts user_id (tries `user_id` field, then `user.id` nested field)
- Removes from `_member_cache[space_id]` by user_id
- Emits `members_updated(space_id)`

`on_member_update(member, conn_index)` (line 204):
- Converts to dict, finds and replaces in `_member_cache[space_id]`
- If not found, appends (handles late-arriving member data)
- Emits `members_updated(space_id)`

`on_member_chunk(data, conn_index)`:
- Processes bulk member data from `request_members()` responses
- Extracts embedded user dicts and populates `_user_cache` via `AccordUser.from_dict()`
- Deduplicates against existing members using an ID index
- Updates or appends each member in `_member_cache[space_id]`
- Emits `members_updated(space_id)`

**Spaces:**

`on_space_create(space, conn_index)` (line 221):
- Only processes if space.id matches connection's space_id
- Updates `_space_cache`, emits `spaces_updated`

`on_space_update(space)` (line 229):
- Updates `_space_cache` if space exists, emits `spaces_updated`

`on_space_delete(data)` (line 235):
- Erases from `_space_cache` and `_space_to_conn`, emits `spaces_updated`

**Channels:**

`on_channel_create(channel, conn_index)` (line 241):
- If DM/group_dm: caches recipients, adds to `_dm_channel_cache`, emits `dm_channels_updated`
- Else: adds to `_channel_cache` and `_channel_to_space`, emits `channels_updated(space_id)`

`on_channel_update(channel, conn_index)` (line 262):
- Same DM vs space channel logic as create

`on_channel_delete(channel)` (line 283):
- If DM/group_dm: erases from `_dm_channel_cache`, emits `dm_channels_updated`
- Else: erases from `_channel_cache` and `_channel_to_space`, emits `channels_updated(space_id)`

`on_channel_pins_update(data)`:
- Extracts channel_id from raw dict
- Emits `messages_updated(channel_id)` so UI can refresh pinned messages

**Interactions:**

`on_interaction_create(interaction, conn_index)`:
- No-op handler; wired to prevent silent signal drop
- No interaction/slash-command UI exists yet

**Roles:**

`on_role_create(data, conn_index)` (line 293):
- Parses `AccordRole` from data (tries `data.role` then `data` itself)
- Converts via `ClientModels.role_to_dict()`, appends to `_role_cache[space_id]`
- Emits `roles_updated(space_id)`

`on_role_update(data, conn_index)` (line 304):
- Parses role, finds and replaces in `_role_cache[space_id]` by ID
- Emits `roles_updated(space_id)`

`on_role_delete(data, conn_index)` (line 318):
- Extracts role_id (tries `role_id` then `id`), removes from `_role_cache[space_id]`
- Emits `roles_updated(space_id)`

**Bans:**

`on_ban_create(data, conn_index)` (line 331):
- Emits `bans_updated(space_id)` (no local cache mutation)

`on_ban_delete(data, conn_index)` (line 337):
- Emits `bans_updated(space_id)` (no local cache mutation)

**Invites:**

`on_invite_create(invite, conn_index)` (line 343):
- Emits `invites_updated(space_id)` (no local cache mutation)

`on_invite_delete(data, conn_index)` (line 349):
- Emits `invites_updated(space_id)` (no local cache mutation)

**Soundboard:**

`on_soundboard_create(sound, conn_index)` (line 355):
- Emits `soundboard_updated(space_id)` (triggers re-fetch)

`on_soundboard_update(sound, conn_index)` (line 361):
- Emits `soundboard_updated(space_id)` (triggers re-fetch)

`on_soundboard_delete(data, conn_index)` (line 367):
- Emits `soundboard_updated(space_id)` (triggers re-fetch)

`on_soundboard_play(data, conn_index)` (line 373):
- Extracts sound_id and user_id, emits `soundboard_played(space_id, sound_id, user_id)`

**Emojis:**

`on_emoji_update(data, conn_index)` (line 381):
- Emits `emojis_updated(space_id)` (triggers re-fetch)

**Voice:**

`on_voice_state_update(state, conn_index)` (line 387):
- Converts to dict via `ClientModels.voice_state_to_dict()`
- Removes user from any previous channel in `_voice_state_cache`
- Adds user to new channel if non-empty
- Updates `voice_users` count in `_channel_cache` for affected channels
- Emits `voice_state_updated` for both old and new channels
- Detects force-disconnect: if own user's channel becomes empty while in voice, calls `AppState.leave_voice()`

`on_voice_server_update(info, conn_index)` (line 421):
- Stores voice server info dict in `_voice_server_info`

`on_voice_signal(data, conn_index)` (line 426):
- Forwards to `AccordVoiceSession.handle_voice_signal()` if the session exists
- Extracts user_id, signal_type, and payload from data

**Reactions:**

`on_reaction_add(data)` (line 443):
- Extracts channel_id, message_id, user_id, emoji_name (handles both string and dict emoji format)
- Finds message in `_message_cache`, increments reaction count or creates new reaction entry
- Sets `active` flag if reactor is current user
- Emits `messages_updated(channel_id)`

`on_reaction_remove(data)` (line 472):
- Decrements reaction count, clears `active` flag if current user
- Removes reaction entry if count reaches 0
- Emits `messages_updated(channel_id)`

`on_reaction_clear(data)` (line 495):
- Clears all reactions on the message
- Emits `messages_updated(channel_id)`

`on_reaction_clear_emoji(data)` (line 507):
- Removes all reactions with a specific emoji from the message
- Emits `messages_updated(channel_id)`

### Gateway Signal Wiring (client.gd:297-375)

When connecting a server, `_connect_gateway_signals()` wires AccordClient signals to ClientGateway handlers. Multi-server support uses `.bind(conn_index)` to pass the connection index to handlers that need it:

```
client.ready_received  -> _gw.on_gateway_ready.bind(idx)
client.message_create  -> _gw.on_message_create.bind(idx)
client.message_update  -> _gw.on_message_update.bind(idx)
client.message_delete  -> _gw.on_message_delete          (no bind, uses raw dict)
client.message_delete_bulk -> _gw.on_message_delete_bulk (no bind, uses raw dict)
client.typing_start    -> _gw.on_typing_start             (no bind)
client.presence_update -> _gw.on_presence_update.bind(idx)
client.member_join     -> _gw.on_member_join.bind(idx)
client.member_leave    -> _gw.on_member_leave.bind(idx)
client.member_update   -> _gw.on_member_update.bind(idx)
client.member_chunk    -> _gw.on_member_chunk.bind(idx)
client.user_update     -> _gw.on_user_update.bind(idx)
client.space_create    -> _gw.on_space_create.bind(idx)
client.space_update    -> _gw.on_space_update             (no bind)
client.space_delete    -> _gw.on_space_delete             (no bind)
client.channel_create  -> _gw.on_channel_create.bind(idx)
client.channel_update  -> _gw.on_channel_update.bind(idx)
client.channel_delete  -> _gw.on_channel_delete           (no bind)
client.channel_pins_update -> _gw.on_channel_pins_update (no bind)
client.role_create     -> _gw.on_role_create.bind(idx)
client.role_update     -> _gw.on_role_update.bind(idx)
client.role_delete     -> _gw.on_role_delete.bind(idx)
client.ban_create      -> _gw.on_ban_create.bind(idx)
client.ban_delete      -> _gw.on_ban_delete.bind(idx)
client.invite_create   -> _gw.on_invite_create.bind(idx)
client.invite_delete   -> _gw.on_invite_delete.bind(idx)
client.emoji_update    -> _gw.on_emoji_update.bind(idx)
client.interaction_create -> _gw.on_interaction_create.bind(idx)
client.soundboard_*    -> _gw.on_soundboard_*.bind(idx)
client.reaction_add    -> _gw.on_reaction_add             (no bind)
client.reaction_remove -> _gw.on_reaction_remove          (no bind)
client.reaction_clear  -> _gw.on_reaction_clear           (no bind)
client.reaction_clear_emoji -> _gw.on_reaction_clear_emoji (no bind)
client.voice_state_update   -> _gw.on_voice_state_update.bind(idx)
client.voice_server_update  -> _gw.on_voice_server_update.bind(idx)
client.voice_signal         -> _gw.on_voice_signal.bind(idx)
client.disconnected    -> _gw.on_gateway_disconnected.bind(idx)
client.reconnecting    -> _gw.on_gateway_reconnecting.bind(idx)
client.resumed         -> _gw.on_gateway_reconnected.bind(idx)
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
- [x] All 30+ event types parsed and dispatched
- [x] Message create/update/delete/delete_bulk -> cache + signal
- [x] Message ID index for O(1) lookup
- [x] Unread/mention tracking on message create
- [x] DM last_message preview on message create
- [x] Typing start -> signal (skips own user) + 10s timeout emits typing_stopped
- [x] Presence update -> user cache + member cache + signal
- [x] User update -> user cache + current_user + signal
- [x] Space create/update/delete -> cache + signal
- [x] Channel create/update/delete -> cache + signal (DM vs space routing)
- [x] Member join/leave/update/chunk -> member cache + signal
- [x] Role create/update/delete -> role cache + signal
- [x] Reaction add/remove/clear/clear_emoji -> message cache + signal
- [x] Voice state update -> voice state cache + channel voice_users count + signal
- [x] Voice server update -> stores server info
- [x] Voice signal -> forwards to AccordVoiceSession
- [x] Voice force-disconnect detection (server clears own user's channel)
- [x] Ban create/delete -> signal (no local cache)
- [x] Invite create/delete -> signal (no local cache)
- [x] Channel pins update -> signal (triggers message refresh)
- [x] Emoji update -> signal (triggers re-fetch)
- [x] Interaction create -> wired (no-op, no interaction UI)
- [x] Soundboard create/update/delete/play -> signal
- [x] Multi-server event routing via conn_index binding
- [x] raw_event catch-all signal for unhandled events
- [x] Gateway disconnect/reconnect/reconnected -> AppState signals for UI feedback

## Tasks

### GW-1: message_delete receives raw dict
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** gateway
- **Notes:** Unlike other handlers that receive typed models, `on_message_delete` receives a raw Dictionary (data with id and channel_id); this is by design since the gateway only sends IDs, not a full message

### GW-2: Ban/invite handlers don't cache
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** api, performance, ui
- **Notes:** `on_ban_create/delete` and `on_invite_create/delete` only emit signals without updating a local cache; UI must re-fetch from REST to reflect changes
