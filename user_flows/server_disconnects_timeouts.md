# Server Disconnects & Timeouts

Priority: 14
Depends on: Server Connection, Gateway Events
Status: Complete

Gateway disconnect handling with auto-reconnect (exponential backoff, session resume), REST timeouts, heartbeat failures, connection banners, composer disabled state, offline message queue, and per-server status indicators.

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
