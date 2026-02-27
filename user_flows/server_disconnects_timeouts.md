# Server Disconnects & Timeouts


## Overview

This flow documents what happens when a server connection is lost during a live session -- covering WebSocket gateway disconnects, REST API timeouts, automatic reconnection with exponential backoff, and session resume capabilities. The UI provides connection banners (yellow/green/red), space icon status dots, composer state changes, inline error feedback for failed edits/deletes, and an offline message queue that auto-sends on reconnect.

## User Steps

### Gateway Disconnect (Server Goes Down)

1. User is chatting normally (gateway connected, `Client.mode == LIVE`).
2. Server becomes unreachable (crash, network drop, maintenance).
3. WebSocket enters `STATE_CLOSED`. Gateway emits `disconnected(code, reason)`.
4. `ClientGateway.on_gateway_disconnected()` updates `conn["status"]` to `"disconnected"`, emits `AppState.server_disconnected`.
5. **User sees:** Yellow connection banner: "Connection lost. Reconnecting..." Space icon shows yellow status dot. Composer is disabled with "Cannot send messages -- disconnected" placeholder.
6. New messages stop arriving. Typing indicators stop. Presence updates stop.
7. Gateway automatically begins reconnection attempts (up to 10, exponential backoff). Gateway emits `reconnecting(attempt, max_attempts)`.
8. **User sees:** Banner updates: "Reconnecting... (attempt 2/10)".
9. If reconnection succeeds: gateway resumes session or receives fresh `ready`. `ClientGateway.on_gateway_reconnected()` updates status to `"connected"`, emits `AppState.server_reconnected`.
10. **User sees:** Green "Reconnected!" banner (auto-hides after 3s). Composer re-enables. Space icon dot disappears. Messages arrive via gateway replay.
11. If all 10 gateway reconnection attempts fail: `ClientGateway.on_gateway_reconnecting()` escalates to `_handle_gateway_reconnect_failed()`.
12. First time: Client performs a full `reconnect_server()` with re-authentication (token refresh via stored credentials). If re-auth succeeds, a fresh connection is established.
13. If re-auth also fails: **User sees:** Red banner: "Connection failed: Reconnection failed" with "Reconnect" button. Space icon shows red dot. Right-click space icon for "Reconnect" option.

### REST API Timeout (Message Fails to Send)

1. User types a message and presses Enter.
2. `Client.send_message_to_channel()` makes HTTP request to server.
3. Server is unreachable -- request times out.
4. `RestResult.ok == false`. `send_message_to_channel()` emits `AppState.message_send_failed(channel_id, content, error)` and returns `false`.
5. **User sees:** Failed message text restored in composer. Red error label below reply bar: "Failed to send: [error message]".

### REST API Timeout (Fetching Data)

1. User selects a channel, triggering `Client.fetch_messages()`.
2. "Loading messages..." label appears. A 15-second timeout timer starts.
3. Server is unreachable -- request times out.
4. `fetch_messages()` emits `AppState.message_fetch_failed(channel_id, error)`.
5. **User sees:** Loading label turns red: "Failed to load messages: [error]. Click to retry". Clicking the label re-fetches.
6. If the request hangs beyond 15s without failure or success: timeout fires, label turns red: "Loading timed out. Click to retry".

### Heartbeat Timeout

1. Client sends heartbeat every `heartbeat_interval_ms` (default 45000ms / 45 seconds).
2. Server fails to ACK the heartbeat before the next interval.
3. Gateway logs warning: "Heartbeat ACK not received, reconnecting".
4. Socket force-closed with code 4000, reason "heartbeat timeout".
5. Triggers automatic reconnection flow (same as Gateway Disconnect above).
6. **User sees:** Same disconnect/reconnect UI flow as Gateway Disconnect.

### Fatal Disconnect (Authentication Revoked / Token Expired)

1. Server closes WebSocket with a fatal close code: 4003, 4004, 4012, 4013, or 4014.
2. Gateway emits `disconnected(code, reason)`.
3. `_should_reconnect()` returns `false` -- no gateway-level reconnection attempted.
4. `ClientGateway.on_gateway_disconnected()` detects fatal code, calls `_handle_gateway_reconnect_failed()` (deferred).
5. First time: Client performs a full `reconnect_server()` which tears down the old connection, re-authenticates using stored credentials (`_try_reauth()`), obtains a fresh token, and reconnects from scratch. Banner stays yellow ("Reconnecting...").
6. If re-auth succeeds: normal "Reconnected!" flow (green banner, composer re-enables).
7. If re-auth fails (bad credentials / server still down): `conn["status"]` set to `"error"`, emits `AppState.server_connection_failed`.
8. **User sees:** Red banner with "Reconnect" button. Space icon shows red dot. Composer disabled.

### Manual Server Removal

1. User right-clicks a space icon in the space bar.
2. Selects "Remove Server" from the context menu.
3. `Client.disconnect_server(space_id)` calls `client.logout()`, cleans all caches.
4. Config removed via `Config.remove_server()`. Space icon disappears.
5. If no connected servers remain, `mode` reverts to `CONNECTING` (empty UI).

## Signal Flow

```
Gateway Disconnect:
  WebSocketPeer.STATE_CLOSED
    -> GatewaySocket._process() detects closed state
    -> _state = DISCONNECTED, set_process(false)
    -> disconnected.emit(code, reason)
    -> AccordClient.disconnected.emit(code, reason) (forwarded)
    -> ClientGateway.on_gateway_disconnected(code, reason, conn_index)
      -> Non-fatal: Updates conn["status"] to "disconnected", emits AppState.server_disconnected
      -> Fatal auth code: Escalates to _handle_gateway_reconnect_failed() (full reconnect with re-auth)
      -> UI components react:
        - message_view: shows yellow/red connection banner
        - composer: disables input
        - guild_icon: shows yellow/red space status dot
    -> _should_reconnect(code) checked
      -> If true: _attempt_reconnect()
        -> _reconnect_attempts++
        -> reconnecting.emit(attempt, max_attempts)
        -> AccordClient.reconnecting.emit(attempt, max_attempts) (forwarded)
        -> ClientGateway.on_gateway_reconnecting(attempt, max_attempts, conn_index)
          -> Updates conn["status"] to "reconnecting"
          -> Emits AppState.server_reconnecting
          -> If attempt >= max_attempts: escalates to _handle_gateway_reconnect_failed() (full reconnect with re-auth)
        -> Exponential backoff: 1.0 * 2^(attempt-1) + random(0,1) seconds
        -> New WebSocketPeer created, connect_to_url() called
        -> On reconnect success:
          -> RESUME: resumed.emit()
            -> ClientGateway.on_gateway_reconnected(conn_index)
              -> Updates conn["status"] to "connected"
              -> Emits AppState.server_reconnected
          -> Fresh connect: ready_received.emit()
            -> ClientGateway.on_gateway_ready() detects _was_disconnected
              -> Emits AppState.server_reconnected
              -> Refetches channels/members/roles
      -> If false (fatal code): no reconnection, stays DISCONNECTED

REST API Failure (Message Send):
  Client.send_message_to_channel()
    -> _client_for_channel() routes to correct AccordClient
      -> Returns null if no connection -> emits AppState.message_send_failed, returns false
    -> client.messages.create() -> AccordRest.make_request()
    -> result.ok == false -> push_error() + AppState.message_send_failed.emit() + returns false
    -> composer._on_message_send_failed() restores text and shows error label

REST API Failure (Message Fetch):
  Client.fetch_messages()
    -> No client -> emits AppState.message_fetch_failed, returns
    -> result.ok == false -> push_error() + AppState.message_fetch_failed.emit()
    -> message_view._on_message_fetch_failed() shows red error with click-to-retry

Heartbeat Timeout:
  GatewaySocket._process() -> _send_heartbeat()
    -> _heartbeat_ack_received == false
    -> push_warning()
    -> _socket.close(4000, "heartbeat timeout")
    -> STATE_CLOSED detected next frame -> disconnect/reconnect flow triggers
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/gateway/gateway_socket.gd` | WebSocket lifecycle, heartbeat, auto-reconnect with exponential backoff |
| `addons/accordkit/core/accord_client.gd` | Wraps gateway + REST, forwards all gateway signals to consumers |
| `addons/accordkit/rest/accord_rest.gd` | HTTP request execution, rate-limit retry, timeout/network error messages |
| `scripts/autoload/client.gd` | Multi-server connection manager, data caching, mutation API, routing |
| `scripts/autoload/client_gateway.gd` | Gateway event handlers, cache updates, AppState signal emission |
| `scripts/autoload/app_state.gd` | Central signal bus with connection lifecycle signals (`server_disconnected`, `server_reconnecting`, `server_reconnected`, `server_connection_failed`, `message_send_failed`, `message_edit_failed`, `message_delete_failed`, `message_fetch_failed`) |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | Only UI with connection error display (probe + connect flow) |
| `scenes/sidebar/guild_bar/guild_icon.gd` | Context menu with "Remove Server" action |
| `scenes/messages/message_view.gd` | Connection banner, fetch failure/timeout handling, click-to-retry loading |
| `scenes/messages/composer/composer.gd` | Send failure restore, disabled state when disconnected |

## Implementation Details

### Gateway Reconnection (gateway_socket.gd)

- **State machine** (line 72): `DISCONNECTED -> CONNECTING -> CONNECTED` (or `RESUMING` for reconnects).
- **Close detection** (line 158): `_process()` polls `_socket.get_ready_state()` every frame. When `STATE_CLOSED` detected, emits `disconnected(code, reason)` and checks `_should_reconnect()`.
- **Fatal close codes** (line 339): `[4003, 4004, 4012, 4013, 4014]` -- these indicate authentication failure, invalid session, etc. Reconnection is not attempted.
- **Reconnect strategy** (lines 345-365): Exponential backoff with jitter. Delay = `1.0 * 2^min(attempt-1, 5) + random(0.0, 1.0)`. Maximum 10 attempts (`_max_reconnect_attempts`, line 87). Creates a fresh `WebSocketPeer` each attempt (line 356).
- **Session resume** (lines 197-206): If `_session_id` is non-empty, sends `RESUME` opcode (op 3) with session_id and last sequence number. Server replays missed events. If session is invalid, server sends `INVALID_SESSION` opcode.
- **INVALID_SESSION handling** (lines 241-260): If not resumable, clears session_id. If max attempts exhausted, closes socket and emits `disconnected(4004, ...)` to escalate to Client-level re-auth. Otherwise waits 1-5 seconds (random) then calls `_attempt_reconnect()`.
- **Server-requested reconnect** (lines 238-239): `RECONNECT` opcode closes socket with code 4000, triggering the normal reconnect flow.
- **Heartbeat** (lines 82-84, 144-147): Server specifies interval via `HELLO` (default 45000ms). Timer increments each `_process()` frame. If `_heartbeat_ack_received` is false when the next heartbeat is due, socket is closed with code 4000 (line 176).

### REST Error Handling (accord_rest.gd)

- **Network-level errors** (lines 16-30): Maps `HTTPRequest.RESULT_*` constants to user-readable strings. Includes "Could not connect to server", "Request timed out", "No response from server", etc.
- **Rate limiting** (lines 87-97): HTTP 429 triggers automatic retry up to `_MAX_RETRIES` (3). Reads `Retry-After` header or body field. Falls back to 1.0 second.
- **Return type**: `RestResult` with `ok: bool`, `status_code: int`, `data`, `error: AccordError`. Callers check `result.ok` and log on failure.
- **No retry for non-429 errors**: Timeouts, connection errors, and server errors return immediately with a failure result. No automatic retry.

### Client Mutation Error Handling (client.gd)

- Core mutation methods (`send_message_to_channel`, `update_message_content`, `remove_message`) return `bool` and emit failure signals on error:
  1. Route to correct `AccordClient` via `_client_for_channel()` or `_client_for_space()`.
  2. If client is `null`: `push_error()`, emit failure signal (`message_send_failed`, `message_edit_failed`, `message_delete_failed`), return `false`.
  3. Await the REST call.
  4. If `result.ok == false`: `push_error()`, emit failure signal, return `false`.
  5. On success: return `true`.
- `fetch_messages()` emits `AppState.message_fetch_failed` on failure.
- Reaction methods (`add_reaction`, `remove_reaction`) still return `void` with `push_error()` only (reactions are less critical).
- Admin API wrappers return `RestResult`, so admin dialogs can check `result.ok` and show errors in their UI.

### Client Connection Status Tracking (client.gd)

- Each connection entry has a `"status"` field: `"connecting"`, `"connected"`, `"disconnected"`, `"reconnecting"`, or `"error"`.
- `_all_failed()`: Returns true if every connection has status `"error"`.
- `mode`: `CONNECTING` or `LIVE`. Set to `LIVE` on first successful connection. Reverted to `CONNECTING` on `disconnect_server()` if all connections are gone.
- `ClientGateway.on_gateway_disconnected()` updates `conn["status"]` on runtime disconnects, keeping status accurate.
- `is_space_connected(space_id)`: Returns true if the connection status is `"connected"`.
- `get_space_connection_status(space_id)`: Returns the current status string.
- `reconnect_server(index)`: Tears down and re-establishes a connection by index.

### HTTPS-Only Connections

- The client only connects over HTTPS. If TLS fails, the connection fails — there is no HTTP fallback.

### Existing Connection UX (add_server_dialog.gd)

- **Server probe** (lines 127-151): Before connecting, makes a lightweight GET to `/auth/login`. Shows errors in `_error_label` if unreachable.
- **Connection attempt UI** (lines 154-172): Button text changes to "Connecting...", disabled during attempt. On failure, rolls back config and shows error.
- Connection errors are also shown via message view banners, space icon status dots, and composer state.

### Gateway-to-UI Signal Chain

- `GatewaySocket` emits `connected`, `disconnected(code, reason)`, `reconnecting(attempt, max_attempts)`, `ready_received(data)`, `resumed`.
- `AccordClient` forwards all gateway signals including `reconnecting`.
- `Client.connect_server()` wires `disconnected`, `reconnecting`, and `resumed` to `ClientGateway` handlers (in addition to the existing `ready_received` and event signals).
- `ClientGateway` handlers update `conn["status"]` and emit `AppState` signals (`server_disconnected`, `server_reconnecting`, `server_reconnected`, `server_connection_failed`).
- UI components (`message_view`, `composer`, `guild_icon`) connect to `AppState` signals and react accordingly.

## Implementation Status

- [x] Automatic gateway reconnection with exponential backoff (up to 10 attempts)
- [x] Session resume on reconnect (RESUME opcode with session_id + sequence)
- [x] Heartbeat monitoring with ACK tracking
- [x] Fatal close code detection (escalates to full reconnect with re-auth for 4003, 4004, 4012, 4013, 4014)
- [x] INVALID_SESSION handling (1-5s random delay, then reconnect; max attempts guard prevents infinite loop)
- [x] Automatic re-authentication on gateway failure (Client._handle_gateway_reconnect_failed)
- [x] Server-requested reconnect (RECONNECT opcode)
- [x] REST rate-limit retry (429 with exponential backoff, up to 3 retries)
- [x] REST error message mapping (timeout, connection error, TLS failure, etc.)
- [x] HTTPS-only connections (no HTTP fallback)
- [x] Manual server removal via space icon context menu
- [x] Connection error display in Add Server dialog
- [x] Data re-fetch on gateway ready (channels, members, roles, DM channels)
- [x] Connection status banner in message view (yellow for disconnect/reconnecting, green for reconnected, red for failed)
- [x] "Reconnecting..." progress with attempt count in banner
- [x] Failed message sends restore text to composer with error label
- [x] Failed edits/deletes emit AppState signals (`message_edit_failed`, `message_delete_failed`)
- [x] Reconnect button in connection banner and space icon context menu
- [x] Per-server connection status indicator (colored dot on space icon)
- [x] "Loading messages..." 15s timeout with error state and click-to-retry
- [x] AppState signals for connection lifecycle (8 new signals)
- [x] Client handler for AccordClient.disconnected/reconnecting/resumed signals
- [x] conn["status"] updated on runtime disconnect/reconnect
- [x] Composer disabled state when disconnected (input disabled, placeholder changed)
- [x] Offline message queue (queued while disconnected, auto-sent on reconnect)
- [x] Fatal disconnect codes mapped to human-readable messages (4003, 4004, 4012, 4013, 4014)
- [x] Edit failure re-enters edit mode with error message
- [x] Delete failure shows inline error on the message

## Gaps / TODO

No known gaps.
