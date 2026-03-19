# Read Only Mode

Priority: 63
Depends on: Web Export
Status: Complete

Anonymous guest browsing of public channels without an account. Desktop entry via "Browse without account" button, web auto-guest via preset server (`window.daccordPresetServer`). Guest tokens are short-lived (1hr), silently refreshed. All interactive inputs grayed out with `GuestPrompt.show_if_guest()` gating. Lazy auth: visitors are never prompted until they click a disabled element. Upgrade replaces guest connection in-place without reconnecting from scratch. Web tokens split between `sessionStorage` (guest, transient) and `localStorage` (auth, persistent).

## Key Files

| File | Role |
|------|------|
| `scripts/client/client_connection.gd` | `connect_guest()`, `upgrade_guest_connection()`, guest token refresh timer |
| `scripts/autoload/client.gd` | Delegates guest methods; guards all mutations with `is_guest_mode` |
| `scripts/autoload/app_state.gd` | `is_guest_mode`, `guest_base_url`, `enter/exit_guest_mode()`, `guest_mode_changed` signal |
| `scripts/helpers/guest_prompt.gd` | `GuestPrompt.show_if_guest()` static utility — registration modal for all grayed-out inputs |
| `scripts/autoload/client_web_links.gd` | Web auto-guest via preset server, `localStorage`/`sessionStorage` management, deep link routing |
| `scenes/sidebar/guild_bar/auth_dialog.gd` | "Browse without account" button, `guest_requested` signal |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `_connect_as_guest()` — fetches guest token, calls `Client.connect_guest()` |
| `scenes/messages/message_view.gd` | Guest banner ("You're browsing as a guest") with Sign In / Register buttons |
| `scenes/messages/composer/composer.gd` | Grayed-out in guest mode; click triggers `GuestPrompt.show_if_guest()` |
| `scenes/messages/thread_panel.gd` | Thread composer disabled, "Sign in to reply" placeholder |
| `scenes/messages/forum_view.gd` | "New Post" grayed out in guest mode |
| `scenes/messages/reaction_pill.gd` | Reaction pills grayed out; click triggers `GuestPrompt.show_if_guest()` |
| `scenes/messages/message_view_actions.gd` | Context menu actions gated by `GuestPrompt.show_if_guest()` |
| `scenes/members/member_list.gd` | Fetches anonymous count, renders `anonymous_entry_item` |
| `scenes/members/anonymous_entry_item.gd` | Non-interactive row: "N anonymous users" |
| `scenes/members/anonymous_entry_item.tscn` | Scene resource for anonymous entry row |
| `scenes/discovery/discovery_panel.gd` | "Preview" button wiring for guest-mode entry from discovery |
| `scenes/discovery/discovery_detail.gd` | `preview_pressed` signal for guest preview before joining |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `guest()` method: `POST /auth/guest` |
| `addons/accordkit/models/user.gd` | `is_guest: bool` field on `AccordUser` |
| `addons/accordkit/models/channel.gd` | `allow_anonymous_read: bool` field on `AccordChannel` |
| `addons/accordkit/gateway/gateway_intents.gd` | `GatewayIntents.guest()` — reduced intent set |
| `dist/web/index.html` | HTML shell with `window.daccordPresetServer` config and URL fragment parsing |
