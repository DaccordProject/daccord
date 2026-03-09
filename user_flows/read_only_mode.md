# Read Only Mode

## Overview

Read only mode allows anonymous (unregistered) users to browse public channels on an accordserver instance without creating an account. Anonymous viewers can read message history and see the member list, but cannot perform any actions. Multiple anonymous viewers are aggregated into a single "N anonymous users" entry in the member list rather than appearing as individual accounts.

## User Steps

### Entering Read Only Mode

1. User opens daccord (fresh install or via deep link / URL)
2. On the Add Server dialog or auth dialog the user clicks **"Browse without account"**
3. daccord connects to the server without credentials via `GET /auth/guest` to receive a short-lived guest token
4. Server returns a guest token scoped to public-readable channels only
5. Client enters **Guest mode**: connects with a transient token, no Config entry saved, no profile created
6. Channel list loads showing only channels the server has marked as readable by guests (`allow_anonymous_read: true`)
7. A persistent **"You're browsing anonymously"** banner appears above the message view with a **"Sign In"** and **"Register"** button

### Browsing as an Anonymous User

8. User clicks a public channel — messages load in read-only view
9. Composer area is replaced by a call-to-action: **"Sign in to join the conversation"** with Sign In / Register buttons
10. Right-click context menu on messages shows no options (empty / "No actions available")
11. Member list shows authenticated members grouped by role/status as normal, plus a single aggregated entry at the bottom: **"N anonymous users"** (N = server-reported count, updated periodically)
12. Reaction pills are visible but clicking them shows a tooltip: "Sign in to react"
13. Voice channel items are visible but clicking shows: "Sign in to join voice"
14. No DM button or DM list is accessible

### Upgrading from Anonymous to Authenticated

15. User clicks "Sign In" or "Register" from the banner or composer CTA
16. Auth dialog opens in Sign In / Register mode (same as normal server connection flow)
17. On successful auth, the guest token is discarded, a real token is saved to Config, and the client reconnects as an authenticated user
18. `AppState.guest_mode_changed` fires (`false`), UI re-enables all interactive elements
19. The anonymous banner disappears; composer re-enables

### Server Discovery Integration

- The master server discovery panel (`scenes/sidebar/guild_bar/discovery_panel.gd`) adds a **"Preview"** button next to "Join" for public spaces
- Clicking "Preview" opens an add-server-like dialog that connects in guest mode without prompting for credentials

## Signal Flow

```
=== ANONYMOUS ENTRY ===

auth_dialog: user clicks "Browse without account"
    -> add_server_dialog._connect_as_guest(base_url)
        -> GET /auth/guest  (no credentials)
            -> returns { token, expires_at, space_id }
        -> Client.connect_guest(base_url, guest_token, space_id)
            -> AccordClient created with guest_token
            -> GET /users/@me  (returns synthetic guest user)
            -> GET /users/@me/spaces -> match space (guest returns public spaces only)
            -> GET /spaces/{id} -> cache space (no Config.add_server() call)
            -> _connect_gateway_signals(client, idx)
            -> client.login() -> WebSocket (gateway sends only public channel events)
            -> mode = LIVE, guest_mode = true
            -> AppState.guest_mode_changed.emit(true)
                -> message_view._on_guest_mode_changed() -> show banner, disable composer
                -> channel_list._on_guest_mode_changed() -> filter to public channels
                -> member_list._on_guest_mode_changed() -> show anonymous count entry
                -> guild_bar._on_guest_mode_changed() -> hide DM button

=== ANONYMOUS MEMBER COUNT ===

member_list._ready()
    -> [guest_mode] GET /spaces/{id}/anonymous-count
        -> returns { count: 10 }
    -> _add_anonymous_entry(count)
        -> anonymous_entry_item.setup({ count: 10 })

Gateway event: anonymous_count_updated { count: 12 }
    -> member_list._on_anonymous_count_updated(12)
        -> anonymous_entry_item.update_count(12)

=== UPGRADE TO AUTHENTICATED ===

user clicks "Sign In" on banner
    -> auth_dialog.open(base_url, mode=SIGN_IN)
        -> auth_completed(base_url, token, username, password)
            -> Client.upgrade_guest_connection(idx, token, username, password)
                -> disconnect existing guest WebSocket
                -> Config.add_server(base_url, token, space_name, username, password)
                -> Client.connect_server(idx)  (re-connects as real user)
                -> AppState.guest_mode_changed.emit(false)
                    -> banner hidden, composer re-enabled
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Add "Browse without account" button; guest entry point |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `_connect_as_guest()` method; skip token requirement |
| `scripts/autoload/client.gd` | `connect_guest()`, `upgrade_guest_connection()`, `guest_mode` flag |
| `scripts/autoload/app_state.gd` | `guest_mode_changed` signal, `is_guest_mode` state |
| `scenes/messages/message_view.gd` | Show/hide anonymous banner; disable composer in guest mode |
| `scenes/messages/composer/composer.gd` | Read-only CTA state replacing input area |
| `scenes/members/member_list.gd` | `anonymous_entry_item` aggregated count row |
| `scenes/members/anonymous_entry_item.gd` | New scene: renders "N anonymous users" row |
| `scenes/sidebar/guild_bar/discovery_panel.gd` | "Preview" button for guest-mode entry from directory |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `guest()` method: `POST /auth/guest` |
| `addons/accordkit/models/user.gd` | `is_guest: bool` field on `AccordUser` |

## Implementation Details

### Guest Token Endpoint

The server must expose `POST /auth/guest` (or `GET /auth/guest`) returning a short-lived token scoped only to public-readable channels. The accordserver must enforce that guest tokens can only access channels where `allow_anonymous_read = true`. The client side calls this via a new `AuthApi.guest(base_url)` method in `addons/accordkit/rest/endpoints/auth_api.gd`.

### Client Guest Mode

`client.gd` needs a `guest_mode: bool` flag and a new `connect_guest(base_url, guest_token, space_id)` method. The key difference from `connect_server()` is:
- No `Config.add_server()` call — the connection is transient
- Guest connections are not restored on next launch
- `AccordClient` uses the guest token as Bearer auth
- Only channels with `allow_anonymous_read = true` are returned by the server; the client filters display accordingly

### AppState Signal

`app_state.gd` needs a new `signal guest_mode_changed(is_guest: bool)` and `var is_guest_mode: bool = false`. All interactive components connect to this signal to toggle their read-only state.

### Composer Read-Only State

`composer.gd` needs a third visual state alongside normal and disabled: a CTA panel showing "Sign in to join the conversation" with Sign In / Register buttons. This replaces the entire input area rather than just disabling it, providing a clearer affordance.

### Anonymous Member Count Entry

A new scene `anonymous_entry_item.gd` renders a non-interactive row in the member list. It shows a generic avatar (e.g., a ghost icon from `assets/theme/icons/`) and the label "N anonymous users". The count is fetched from `GET /spaces/{id}/anonymous-count` on member list load, and updated via a new `anonymous_count_updated` WebSocket gateway event. The entry is always pinned to the bottom of the member list, below all role-grouped members.

### Channel Visibility Filtering

The server marks individual channels with `allow_anonymous_read: true`. The `AccordChannel` model in `addons/accordkit/models/channel.gd` needs an `allow_anonymous_read: bool = false` field. In guest mode, `channel_list.gd` hides channels where this is `false`.

### Message Context Menu

`cozy_message.gd` and `collapsed_message.gd` right-click context menus are currently built with Reply / Edit / Delete items. In guest mode, all items must be suppressed. The context menu should either not open at all or show a single disabled item: "Sign in to interact".

### Reaction Bar

`message_content.gd` reaction pills show count and emoji but clicking them in guest mode shows an inline tooltip: "Sign in to react". The `+` reaction button is hidden entirely in guest mode.

### Gateway Subscription

In guest mode, the WebSocket gateway connection should subscribe only to public channel events. The `GatewayIntents` bitmask sent on login should use a new `GatewayIntents.GUEST` constant (messages + member count only, no presence, no DMs, no voice).

## Implementation Status

- [ ] `POST /auth/guest` server endpoint
- [ ] `AuthApi.guest()` client method
- [ ] `AccordUser.is_guest` field
- [ ] `AccordChannel.allow_anonymous_read` field
- [ ] `Client.connect_guest()` / `Client.upgrade_guest_connection()`
- [ ] `AppState.guest_mode_changed` signal and `is_guest_mode` state
- [ ] "Browse without account" button in `auth_dialog.gd`
- [ ] `add_server_dialog._connect_as_guest()` method
- [ ] Anonymous banner in `message_view.gd`
- [ ] Composer CTA read-only state in `composer.gd`
- [ ] `anonymous_entry_item` scene + script
- [ ] Member list anonymous count fetch + gateway event
- [ ] Channel list guest filtering
- [ ] Message context menu suppression in guest mode
- [ ] Reaction bar guest-mode tooltip / hide `+` button
- [ ] `GatewayIntents.GUEST` constant
- [ ] Discovery panel "Preview" button for guest-mode entry
- [ ] Guest connections excluded from Config persistence / session restore

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No `POST /auth/guest` server endpoint | High | Entire feature blocked on accordserver support; client changes are meaningless without it |
| No `allow_anonymous_read` channel flag | High | Server must expose per-channel guest visibility; currently no such field in `AccordChannel` model (`addons/accordkit/models/channel.gd`) |
| No `Client.connect_guest()` method | High | `client.gd` only supports authenticated connections; new code path required |
| No `AppState.guest_mode_changed` signal | High | All UI components rely on this for guest state transitions |
| No anonymous member count endpoint | High | `GET /spaces/{id}/anonymous-count` and corresponding gateway event don't exist in accordkit REST layer |
| Composer has no CTA read-only state | Medium | `composer.gd` has disabled state but no "sign in" CTA panel |
| Auth dialog has no "Browse without account" button | Medium | `auth_dialog.gd` only has Sign In / Register tabs (line 9) |
| No `anonymous_entry_item` scene | Medium | Member list has no aggregated anonymous row; entirely new scene needed |
| Guest connections not excluded from Config persistence | Medium | `add_server_dialog.gd` always calls `Config.add_server()`; guest must skip this |
| Message context menu not suppressed in guest mode | Medium | `cozy_message.gd` builds context menu without checking guest mode |
| Reaction `+` button not hidden in guest mode | Low | `message_content.gd` reaction bar has no guest-mode branch |
| No `GatewayIntents.GUEST` constant | Low | `addons/accordkit/models/intents.gd` has no reduced-scope guest intent set |
| Discovery panel has no "Preview" (guest entry) button | Low | `scenes/sidebar/guild_bar/discovery_panel.gd` only has "Join" |
| Guest session not restored across launches | Low | By design: transient connections should not persist, but this should be documented in Config flow |
| Token expiry handling for guest tokens | Low | Short-lived guest tokens will expire; client needs silent refresh or re-guest logic |
