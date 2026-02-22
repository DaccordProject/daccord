# Server Update

## Overview
When an accordserver instance restarts or updates (e.g., deploying a new version), the WebSocket gateway drops and the client must reconnect and resync all cached data. This flow documents the reconnection lifecycle and identifies scenarios where stale data — especially permissions, roles, and channel configurations — may persist after a server update.

## User Steps
1. Server admin deploys a new version of accordserver (the process restarts).
2. The WebSocket closes with code `1001` ("going away") or the connection drops unexpectedly.
3. The client detects the disconnect and shows a warning banner in the message view.
4. The gateway socket automatically attempts reconnection with exponential backoff.
5. If a resumable session exists, the client sends RESUME; otherwise it re-IDENTIFYs.
6. On successful reconnection, the client refetches channels, members, and roles.
7. The banner shows "Reconnected!" and auto-hides after a timer.
8. The user continues using the client, which should now reflect the server's updated state.

## Signal Flow
```
Server restarts
  └─> WebSocket closes (code 1001 / connection drop)
        └─> GatewaySocket._process() detects STATE_CLOSED
              ├─> GatewaySocket.disconnected signal emitted
              │     └─> ClientGateway.on_gateway_disconnected()
              │           ├─> conn["status"] = "disconnected"
              │           ├─> conn["_was_disconnected"] = true
              │           └─> AppState.server_disconnected emitted
              │                 ├─> MessageViewBanner shows warning
              │                 ├─> Composer disables input
              │                 └─> GuildIcon shows disconnected state
              └─> GatewaySocket._attempt_reconnect()
                    ├─> reconnecting signal (attempt N/10)
                    │     └─> ClientGateway.on_gateway_reconnecting()
                    │           └─> AppState.server_reconnecting emitted
                    │                 └─> Banner: "Reconnecting... (attempt N/10)"
                    └─> [On success, one of two paths]:
                          ├─> RESUME accepted:
                          │     └─> GatewaySocket.resumed signal
                          │           └─> ClientGateway.on_gateway_reconnected()
                          │                 ├─> conn["status"] = "connected"
                          │                 ├─> AppState.server_reconnected emitted
                          │                 └─> _refetch_data() (same as IDENTIFY)
                          └─> IDENTIFY (fresh session):
                                └─> GatewaySocket.ready_received signal
                                      └─> ClientGateway.on_gateway_ready()
                                            ├─> Parse server_version / api_version from READY
                                            ├─> conn["status"] = "connected"
                                            ├─> AppState.server_reconnected emitted
                                            └─> _refetch_data():
                                                  ├─> conn["_syncing"] = true
                                                  ├─> await fetch_channels()
                                                  ├─> await fetch_members()
                                                  ├─> await fetch_roles()
                                                  ├─> resync_voice_states()
                                                  ├─> await refresh_current_user()
                                                  ├─> await fetch_dm_channels()
                                                  ├─> conn["_syncing"] = false
                                                  └─> AppState.server_synced emitted
```

## Key Files
| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket connection, reconnect logic, RESUME/IDENTIFY |
| `addons/accordkit/core/accord_config.gd` | API version, client version constants |
| `scripts/autoload/client_gateway.gd` | Gateway event handlers, reconnect orchestration |
| `scripts/autoload/client_connection.gd` | Server connection lifecycle, full reconnect with re-auth |
| `scripts/autoload/client_fetch.gd` | Data fetching (channels, members, roles, messages) |
| `scripts/autoload/client_permissions.gd` | Permission evaluation from cached role/member data |
| `scripts/autoload/client.gd` | Cache structures, message queue, flush on reconnect |
| `scripts/autoload/client_mutations.gd` | Message queueing during disconnection |
| `scripts/autoload/app_state.gd` | Connection signals (`server_disconnected`, `server_reconnected`, etc.) |
| `scenes/messages/message_view_banner.gd` | Connection status banner UI |
| `scenes/messages/composer/composer.gd` | Composer enable/disable based on connection status |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Guild icon disconnected state indicator |

## Implementation Details

### Gateway Reconnection
- `GatewaySocket._attempt_reconnect()` (line 389) uses exponential backoff: `1s * 2^(attempt-1) + random(0-1)s`, capped at attempt 5 for delay calculation.
- Maximum 10 reconnect attempts (`_max_reconnect_attempts = 10`, line 96).
- If a `_session_id` exists, the socket enters `State.RESUMING` (line 404) and sends a RESUME payload. A server restart typically invalidates sessions, so RESUME will fail.
- When RESUME fails mid-connection (socket closes while `_resume_pending` is true), `_session_id` and `_sequence` are cleared (lines 177-180), forcing a full IDENTIFY on the next attempt.
- The RECONNECT opcode from the server (opcode mapping in `_handle_message`, line 259) causes an immediate close with code 4000, triggering reconnection.
- INVALID_SESSION with `resumable=false` clears the session (lines 262-280) and waits 1-5s before reconnecting.

### RESUME vs IDENTIFY: Unified Refetch
- Both **RESUME** and **IDENTIFY** paths now call `_refetch_data()`, which sets `conn["_syncing"] = true`, awaits all fetches (channels, members, roles, voice states, current user, DMs), then sets `conn["_syncing"] = false` and emits `server_synced`.
- **RESUME** (`on_gateway_reconnected()`): Marks connected, emits `server_reconnected`, then calls `_refetch_data()`.
- **IDENTIFY** (`on_gateway_ready()`): Parses `server_version`/`api_version` from READY payload, marks connected, emits `server_reconnected` if was disconnected, then calls `_refetch_data()`.
- The composer is disabled during the syncing window to prevent permission-dependent actions with stale data.

### What Gets Refetched on Reconnect (both IDENTIFY and RESUME)
Both paths now call `_refetch_data()` which awaits all fetches before emitting `server_synced`.

| Data | Refetched? | Method | Cache Strategy |
|------|-----------|--------|----------------|
| Channels | Yes | `fetch_channels()` (client_fetch.gd) | Full replacement — old channels for guild erased, new ones written |
| Members | Yes | `fetch_members()` (client_fetch.gd) | Full replacement — paginated 1000/page, complete cache swap |
| Roles | Yes | `fetch_roles()` (client_fetch.gd) | Full replacement — entire array replaced |
| DM channels | Yes | `fetch_dm_channels()` (client_fetch.gd) | Full refresh with unread/preview state preservation |
| Messages | Yes | `fetch_messages()` (message_view.gd) | Current channel refetched on `server_reconnected`; forum/thread caches cleared |
| Voice states | Yes | `resync_voice_states()` (client_fetch.gd) | Refetches all cached voice channels for the guild |
| Current user | Yes | `refresh_current_user()` (client_fetch.gd) | Re-calls `GET /users/@me` and updates user cache + conn |
| Forum posts | Cleared | — | Stale cache cleared on reconnect; refetched when user navigates to forum channel |
| Thread messages | Cleared | — | Stale cache cleared on reconnect; refetched when user opens thread panel |
| Guild info | **No** | — | Updated only via space.update gateway event |

### Permission Evaluation After Reconnect
- `client_permissions.gd` computes permissions **on-demand** from `_role_cache` and `_member_cache` (no separate permission cache).
- `has_permission()` (line 10) checks: imposter mode → is_admin → space owner → @everyone + assigned roles.
- `has_channel_permission()` (line 34) additionally applies channel permission overwrites.
- After reconnect, all fetches are now **awaited** before `server_synced` is emitted. The `conn["_syncing"]` flag is true during this window.
- The composer is disabled while syncing, preventing users from taking permission-dependent actions with stale data.
- The banner shows "Reconnected — syncing data..." during this window, switching to "Reconnected!" once `server_synced` fires.

### Message Queue During Disconnection
- When a server is disconnected, `send_message_to_channel()` (client_mutations.gd:70) queues messages in `_message_queue` (up to `MESSAGE_QUEUE_CAP = 20`).
- On `server_reconnected`, `_flush_message_queue()` (client.gd:704) sends queued messages.
- **Risk:** If the server updated its message validation (e.g., new content restrictions), queued messages may fail silently.

### Connection Banner UI
- `MessageViewBanner` (message_view_banner.gd) shows five states:
  - **Warning** (amber): "Reconnecting..." or "Reconnecting... (attempt N/M)"
  - **Syncing** (amber): "Reconnected — syncing data..." (shown between `server_reconnected` and `server_synced`)
  - **Success** (green): "Reconnected!" — auto-hides after timer (shown on `server_synced`)
  - **Error** (red): "Connection failed: {reason}" with a Retry button
  - **Version warning** (amber, persistent): "Server version mismatch (server vX.Y.Z, client vA.B.C). Some features may not work correctly."
- `sync_to_connection()` syncs banner state when switching channels.
- Composer disables input during disconnection and during syncing (`Client.is_guild_syncing()`). Placeholder shows "Syncing..." while syncing.

### Escalation: Full Reconnect with Re-auth
- When gateway reconnection exhausts all 10 attempts, `on_gateway_reconnecting()` (line 153) calls `_handle_gateway_reconnect_failed()`.
- Fatal close codes `[4003, 4004, 4012, 4013, 4014]` also trigger immediate escalation (line 130-138).
- `handle_gateway_reconnect_failed()` (client_connection.gd:328) performs a full `reconnect_server()` with token re-authentication, but only **once per disconnect cycle** to prevent infinite loops.
- If already attempted, the connection enters "error" state (line 338) and `server_connection_failed` is emitted.

### API Version Compatibility
- `AccordConfig.API_VERSION = "v1"` and `API_BASE_PATH = "/api/v1"` (accord_config.gd:3-4).
- Gateway connects with `?v=1&encoding=json` (line 22).
- `CLIENT_VERSION = "2.0.0"` sent in IDENTIFY properties (gateway_socket.gd:211).
- On initial connect, `connect_server()` calls `GET /api/v1/version` and stores `server_version` and `server_git_sha` in the connection dict. If the major version differs, `server_version_warning` is emitted.
- On reconnect (IDENTIFY), the `READY` payload now includes `api_version` and `server_version`. If `api_version` differs from `AccordConfig.API_VERSION`, `server_version_warning` is emitted.
- The banner shows a persistent amber warning on version mismatch: "Server version mismatch (server vX.Y.Z, client vA.B.C). Some features may not work correctly."

### Role and Permission Update via Gateway Events
- `role.create` (client_gateway.gd:561): appends new role to `_role_cache[guild_id]`.
- `role.update` (client_gateway.gd:572): finds and replaces role in cache by ID.
- `role.delete` (client_gateway.gd:586): removes role from cache by ID.
- `member.update` (client_gateway_members.gd:87): replaces member dict in cache (includes role assignments).
- All emit `AppState.roles_updated` or `AppState.members_updated`, which triggers UI rebuilds.
- **During normal operation**, role/permission changes propagate in real-time via these events. The risk is only during the reconnection window.

### Channel Permission Overwrite Updates
- Channel overwrites are stored inline in the channel dict: `d["permission_overwrites"]` (client_models.gd).
- Updated via `channel.update` gateway event (client_gateway.gd:541-549), which replaces the entire channel dict.
- `fetch_channels()` during reconnect also replaces all channel data including overwrites.
- **Gap:** There is no dedicated `permission_overwrite.update` event — overwrites only update when the entire channel updates.

## Implementation Status
- [x] Automatic gateway reconnection with exponential backoff
- [x] RESUME for quick reconnects, IDENTIFY for fresh sessions
- [x] Session invalidation when RESUME fails mid-connection
- [x] Full data refetch (channels, members, roles, DMs) on IDENTIFY reconnect
- [x] Connection status banner with disconnect/reconnecting/reconnected states
- [x] Composer disable during disconnection
- [x] Guild icon disconnected state indicator
- [x] Message queueing during disconnection (cap 20)
- [x] Message queue flush on reconnect
- [x] Escalation to full reconnect with re-auth on gateway exhaustion
- [x] Single-attempt guard on escalation to prevent infinite loops
- [x] Fatal close code detection and escalation
- [x] Role/member/channel updates via gateway events during normal operation
- [x] Message cache refresh on reconnect
- [x] Voice state resync on reconnect
- [x] User profile/avatar refresh on reconnect
- [x] API version compatibility check on connect and via READY payload
- [x] Server-side version announcement via gateway READY event
- [x] Syncing state with `server_synced` signal (stale permission window addressed)

## Gaps / TODO
| Gap | Severity | Status | Notes |
|-----|----------|--------|-------|
| Messages not refetched on reconnect | Medium | **Fixed** | `message_view.gd` connects to `server_reconnected` and calls `fetch_messages()` for the current channel. Forum/thread caches are cleared for the reconnected guild. |
| Permission race window after reconnect | Medium | **Fixed** | All fetches are now awaited via `_refetch_data()`. The `conn["_syncing"]` flag + `server_synced` signal prevent permission-dependent actions during the refetch window. Composer is disabled while syncing. |
| RESUME path skips all data refetch | Medium | **Fixed** | `on_gateway_reconnected()` now calls `_refetch_data()`, same as the IDENTIFY path. |
| No API version negotiation | High | **Fixed** | `connect_server()` calls `GET /api/v1/version` and compares major versions. READY payload includes `api_version` and `server_version`. Mismatches trigger a persistent amber banner warning. |
| Voice states not resynced on reconnect | Medium | **Fixed** | `resync_voice_states()` iterates cached voice channels for the guild and refetches each via `fetch_voice_states()`. Called from `_refetch_data()`. |
| User cache never bulk-refreshed | Low | **Fixed** | `refresh_current_user()` re-calls `GET /users/@me` on reconnect and updates user cache + connection dict. Other users still rely on gateway events. |
| No server-side version/capability announcement | Medium | **Fixed** | READY payload now includes `api_version` and `server_version` (accordserver change). Client parses and stores them in the connection dict. |
| Forum/thread caches not refreshed on reconnect | Low | **Fixed** | Forum post and thread message caches are cleared for the reconnected guild's channels on `server_reconnected`. |
| Guild info not refetched on reconnect | Low | Open | Guild metadata is only updated via `space.update` gateway events, not refetched on reconnect. |
| Queued messages may fail after server update | Low | Open | Messages queued during disconnection are flushed on reconnect without re-validating against the updated server. |
| Channel permission overwrites only update via full channel update | Low | Open | There is no granular `permission_overwrite.update` event. Overwrites change only when the entire channel is updated. |
| No "server updated, please restart" notification | Medium | Open | The version warning banner addresses version mismatches, but there is no mechanism to prompt the user to update the client application itself. |
