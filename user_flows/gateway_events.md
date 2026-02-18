# Gateway Events

## Overview

daccord maintains real-time sync with accordserver via WebSocket gateway connections. AccordKit's GatewaySocket handles the WebSocket lifecycle (connect, heartbeat, reconnection, session resume). Gateway events are dispatched as typed signals on AccordClient, which Client.gd listens to and translates into cache updates + AppState signal emissions. This creates a clean separation: AccordKit handles transport, Client handles state, AppState notifies the UI.

## Event Flow

```
accordserver
    -> WebSocket JSON frame: {op: 0, t: "event.type", d: {...}}
    -> GatewaySocket._dispatch_event(event_type, data)
        -> Parses data into typed model (AccordMessage, AccordChannel, etc.)
        -> Emits typed signal (e.g., message_create(message: AccordMessage))
    -> AccordClient re-emits signal (proxied from GatewaySocket)
    -> Client._on_[event_handler](model, conn_index)
        -> Updates appropriate cache (_message_cache, _channel_cache, etc.)
        -> Emits AppState signal (messages_updated, channels_updated, etc.)
    -> UI components react to AppState signals
        -> Re-render affected views
```

## Signal Flow

Event-to-Signal Mapping:

```
Gateway Event              -> Client Handler                -> AppState Signal
─────────────────────────────────────────────────────────────────────────────
ready                      -> _on_gateway_ready()           -> (fetch_channels, fetch_dm_channels)
message.create             -> _on_message_create()          -> messages_updated(channel_id)
message.update             -> _on_message_update()          -> messages_updated(channel_id)
message.delete             -> _on_message_delete()          -> messages_updated(channel_id)
typing.start               -> _on_typing_start()            -> typing_started(channel_id, username)
presence.update            -> _on_presence_update()         -> user_updated(user_id)
space.create               -> _on_space_create()            -> guilds_updated()
space.update               -> _on_space_update()            -> guilds_updated()
space.delete               -> _on_space_delete()            -> guilds_updated()
channel.create             -> _on_channel_create()          -> channels_updated(guild_id) or dm_channels_updated()
channel.update             -> _on_channel_update()          -> channels_updated(guild_id) or dm_channels_updated()
channel.delete             -> _on_channel_delete()          -> channels_updated(guild_id) or dm_channels_updated()
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket connection, heartbeat, reconnection, event dispatch (385 lines) |
| `addons/accordkit/gateway/gateway_opcodes.gd` | Opcode constants: EVENT(0), HEARTBEAT(1), IDENTIFY(2), RESUME(3), etc. |
| `addons/accordkit/gateway/gateway_intents.gd` | Intent flags: SPACES, MESSAGES, MESSAGE_CONTENT, MESSAGE_TYPING, etc. |
| `addons/accordkit/core/accord_client.gd` | Proxies all gateway signals, provides public API |
| `scripts/autoload/client.gd` | Gateway event handlers (lines 517-660), cache mutation |
| `scripts/autoload/app_state.gd` | UI-facing signals |

## Implementation Details

### Gateway Connection Lifecycle (gateway_socket.gd)

State enum: `{ DISCONNECTED, CONNECTING, CONNECTED, RESUMING }`

Connection sequence:
1. `connect_to_gateway(url)` -> WebSocket connects to `gateway_url?v=1&encoding=json`
2. Server sends HELLO (op 5) with `heartbeat_interval`
3. Client sends IDENTIFY (op 2) with token, intents, properties
4. Server sends READY (op 0, t: "ready") with session_id and user data
5. Heartbeat loop: sends HEARTBEAT (op 1) at server-specified interval
6. Server responds with HEARTBEAT_ACK (op 4)

Reconnection:
- Automatic on unexpected disconnect
- Exponential backoff with jitter: `delay = 1.0 * 2^attempt + random(0..1)`
- Max attempts: 10 (`_max_reconnect_attempts`)
- Session resume: sends RESUME (op 3) with session_id and last sequence number
- Non-reconnectable close codes: 4003, 4004, 4012, 4013, 4014 (invalid session, auth failure, etc.)

Heartbeat:
- Interval from HELLO payload (default 45000ms if not provided)
- If HEARTBEAT_ACK not received before next heartbeat -> reconnect
- `_heartbeat_ack_received` flag tracks acknowledgement

### Intents (gateway_intents.gd)

Client.gd configures intents on connect (client.gd lines 109-113, 133-137):
- Default intents from `GatewayIntents.default()`: SPACES, MESSAGES, MESSAGE_CONTENT
- Additional: MESSAGE_TYPING, DIRECT_MESSAGES, DM_TYPING

Available intents:
- Unprivileged: SPACES, MODERATION, EMOJIS, VOICE_STATES, MESSAGES, MESSAGE_REACTIONS, MESSAGE_TYPING, DIRECT_MESSAGES, DM_REACTIONS, DM_TYPING, SCHEDULED_EVENTS
- Privileged: MEMBERS, PRESENCES, MESSAGE_CONTENT

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

### Client Event Handlers (client.gd:517-660)

Each handler follows the pattern: receive typed model -> update cache -> emit AppState signal.

`_on_gateway_ready(data, conn_index)` (line 519):
- Fetches channels for the connection's guild
- Fetches DM channels

`_on_message_create(message, conn_index)` (line 528):
- Fetches unknown author from REST if not in _user_cache
- Converts to dict, appends to _message_cache[channel_id]
- Enforces MESSAGE_CAP (50) via pop_front()
- Emits messages_updated

`_on_message_update(message, conn_index)` (line 556):
- Finds message in _message_cache by ID, replaces dict
- Emits messages_updated

`_on_message_delete(data)` (line 566):
- Extracts id and channel_id from raw dict (not typed model)
- Finds and removes from _message_cache
- Emits messages_updated

`_on_typing_start(data)` (line 578):
- Extracts user_id and channel_id
- Skips if typing user is current user
- Looks up username from _user_cache
- Emits typing_started(channel_id, username)

`_on_presence_update(presence)` (line 587):
- Updates _user_cache[user_id].status via _status_string_to_enum()
- Emits user_updated(user_id)

`_on_space_create(space, conn_index)` (line 592):
- Only processes if space.id matches connection's guild_id
- Updates _guild_cache, emits guilds_updated

`_on_space_update(space)` (line 599):
- Updates _guild_cache if space exists, emits guilds_updated

`_on_space_delete(data)` (line 604):
- Erases from _guild_cache and _guild_to_conn, emits guilds_updated

`_on_channel_create(channel, conn_index)` (line 610):
- If DM/group_dm: caches recipients, adds to _dm_channel_cache, emits dm_channels_updated
- Else: adds to _channel_cache and _channel_to_guild, emits channels_updated(guild_id)

`_on_channel_update(channel, conn_index)` (line 631):
- Same DM vs guild channel logic as create

`_on_channel_delete(channel)` (line 652):
- If DM/group_dm: erases from _dm_channel_cache, emits dm_channels_updated
- Else: erases from _channel_cache and _channel_to_guild, emits channels_updated(guild_id)

### Gateway Signal Wiring (client.gd:76-222, inside connect_server)

When connecting a server, Client wires AccordClient signals to its handlers. Multi-server support uses `bind(conn_index)` to pass the connection index to handlers that need it:
- `client.message_create.connect(_on_message_create.bind(i))`
- `client.message_update.connect(_on_message_update.bind(i))`
- `client.message_delete.connect(_on_message_delete)` (no bind, uses raw dict)
- etc.

## Implementation Status

- [x] WebSocket gateway connection with IDENTIFY handshake
- [x] Heartbeat loop with ACK tracking
- [x] Automatic reconnection with exponential backoff
- [x] Session resume on reconnect
- [x] Non-reconnectable close code handling
- [x] Intent-based event filtering
- [x] All 30+ event types parsed and dispatched
- [x] Message create/update/delete -> cache + signal
- [x] Typing start -> signal (skips own user)
- [x] Presence update -> user cache + signal
- [x] Space create/update/delete -> cache + signal
- [x] Channel create/update/delete -> cache + signal (DM vs guild routing)
- [x] Multi-server event routing via conn_index binding
- [x] raw_event catch-all signal for unhandled events

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No voice event handlers | Medium | Gateway dispatches voice.state_update, voice.server_update, voice.signal but Client has no `_on_voice_*` handlers |
| No member event handlers | Low | member.join, member.leave, member.update dispatched but Client doesn't handle them (no member list UI) |
| No role event handlers | Low | role.create/update/delete dispatched but not handled |
| No reaction event handlers | Medium | reaction.add/remove/clear/clear_emoji dispatched but Client doesn't update message reaction data in cache |
| No ban/invite/emoji event handlers | Low | Events dispatched but not handled (no corresponding UI) |
| No typing_stopped timeout | Medium | typing_started is emitted but there's no timer to emit typing_stopped after a timeout; relies on server sending stop event which may not happen |
| message_delete receives raw dict | Low | Unlike other handlers that receive typed models, _on_message_delete receives a raw Dictionary (data with id and channel_id) |
| No channel_pins_update handler | Low | Event dispatched but not handled |
| No message_delete_bulk handler | Low | Bulk delete event dispatched but Client only handles single message delete |
