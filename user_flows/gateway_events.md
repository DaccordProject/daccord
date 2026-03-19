# Gateway Events

Priority: 3
Depends on: Server Connection, Data Model
Status: Complete

Real-time sync via WebSocket: GatewaySocket handles transport (connect, heartbeat, reconnect, resume, event dispatch for 50 event types), AccordClient proxies signals, and ClientGateway + sub-handlers (CGE, CGM, CGR) translate events into cache updates + AppState signal emissions across four handler classes.

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket connection, heartbeat, reconnection with exponential backoff, event dispatch (50 event types) |
| `addons/accordkit/gateway/gateway_opcodes.gd` | Opcode constants: EVENT(0), HEARTBEAT(1), IDENTIFY(2), RESUME(3), HEARTBEAT_ACK(4), HELLO(5), RECONNECT(6), INVALID_SESSION(7), PRESENCE_UPDATE(8), VOICE_STATE_UPDATE(9), REQUEST_MEMBERS(10), VOICE_SIGNAL(11) |
| `addons/accordkit/gateway/gateway_intents.gd` | Intent flags: unprivileged (SPACES, MESSAGES, etc.) + privileged (MEMBERS, PRESENCES, MESSAGE_CONTENT) |
| `addons/accordkit/core/accord_client.gd` | Proxies all gateway signals, provides public API |
| `scripts/client/client_gateway.gd` | Core gateway handlers: lifecycle, messages, typing, presence, user, spaces, channels, roles, signal wiring via `connect_signals()` |
| `scripts/client/client_gateway_events.gd` | Admin/entity/voice/plugin/relationship event handlers (bans, invites, emojis, soundboard, channel mutes, voice state, relationships) |
| `scripts/client/client_gateway_members.gd` | Member join/leave/update/chunk handlers with member_id_index maintenance |
| `scripts/client/client_gateway_reactions.gd` | Reaction add/remove/clear handlers with optimistic update deduplication |
| `scripts/client/client_voice.gd` | Voice channel join/leave, video/screen tracks, voice session callbacks |
| `scripts/autoload/client.gd` | Signal wiring via `ClientGateway.connect_signals()`, caches, routing |
| `scripts/client/client_admin.gd` | Admin REST API + populates ban/invite caches on fetch |
| `scripts/autoload/app_state.gd` | UI-facing signals |
