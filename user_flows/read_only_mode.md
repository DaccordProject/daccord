# Read Only Mode

Priority: 63
Depends on: Web Export

## Overview

Read only mode allows anonymous (unregistered) users to browse public channels on an accordserver instance without creating an account. Anonymous viewers can read message history and see the member list, but cannot perform any actions. Multiple anonymous viewers are aggregated into a single "N anonymous users" entry in the member list rather than appearing as individual accounts.

## Why Read Only Mode Matters

### The core idea

Most chat platforms are walled gardens -- you must create an account before you can see anything. Read only mode flips this: server admins can make selected channels publicly viewable so anyone with a link can read them instantly, no sign-up required. This is especially powerful when combined with the [Web Export](web_export.md), which lets daccord run directly in a browser.

### Shareable URLs for the web

The web export produces a hosted version of daccord that runs in any modern browser, pre-configured with a [preset server](web_export.md#preset-servers) so visitors auto-connect as guests instantly. A server admin can share a URL like `https://chat.example.com/#general` and anyone who clicks it lands directly in the channel, reading messages immediately. No download, no account, no login dialog, no friction. This turns every public channel into a webpage anyone can visit.

### Forums and SEO

Forum channels (see [Forums](forums.md)) benefit the most from read only mode. Forum posts have titles, threaded replies, and long-form content -- exactly the kind of structured text that search engines index well. When a forum channel is marked as publicly readable:

- **Search engines can crawl it.** Google, Bing, and others can index post titles, content, and replies. A question asked in your forum can appear in search results, bringing new visitors directly to your server's web client.
- **Organic discovery.** Someone searching "how to configure X" might land on a forum post in your community. They see the answer, browse other posts, and eventually sign up. This is the same growth loop that made platforms like Reddit, Stack Overflow, and Discourse successful.
- **Link sharing works.** Members can share links to specific forum posts on social media, blogs, or other chat platforms. Recipients see the full content immediately without hitting a login wall.

### For server admins (non-technical summary)

Read only mode lets you open your community's doors to the public internet. You choose which channels are visible to anonymous visitors -- typically announcement channels, forums, and help channels. Visitors can browse freely and sign up when they're ready to participate. It's the difference between a locked clubhouse and a shop with an open front door.

### For developers (technical summary)

On web, each deployment is configured with a **preset server** (`window.daccordPresetServer` in the HTML shell) that the client auto-connects to as a guest. The client authenticates with a short-lived guest token from `POST /auth/guest`, scoped to channels with `allow_anonymous_read: true`. The guest connection is transient (not persisted to Config), uses a reduced gateway intent set, and all write operations are blocked both client-side (UI disabled) and server-side (token lacks write permissions). Authentication is **lazy**: visitors are never prompted until they attempt a write action (send, react, join voice), at which point a registration prompt appears. Upgrading to a full account replaces the guest token in-place without reconnecting from scratch. Auth tokens persist to `localStorage` so return visits connect as authenticated users immediately. The web export serves the client as static WASM/HTML that connects to the same accordserver REST + WebSocket APIs as the desktop client.

## User Steps

### Entering Read Only Mode (Desktop)

1. User opens daccord (fresh install or via deep link)
2. On the Add Server dialog or auth dialog the user clicks **"Browse without account"**
3. daccord connects to the server without credentials via `GET /auth/guest` to receive a short-lived guest token
4. Server returns a guest token scoped to public-readable channels only
5. Client enters **Guest mode**: connects with a transient token, no Config entry saved, no profile created
6. Channel list loads showing only channels the server has marked as readable by guests (`allow_anonymous_read: true`)
7. A persistent **"You're browsing anonymously"** banner appears above the message view with a **"Sign In"** and **"Register"** button

### Entering Read Only Mode (Web — auto-guest via preset server)

The web export is configured with a [preset server](web_export.md#preset-servers) baked into the HTML shell. This means visitors are **instantly** connected as guests with zero interaction required -- no login dialog, no server selection, no waiting.

1. Someone shares a link to the hosted web client, e.g. `https://chat.example.com/#general` or `https://chat.example.com/#community/help-forum/1234567890`
2. The browser loads the daccord WASM app (see [Web Export](web_export.md))
3. The web client reads the preset server config (`window.daccordPresetServer`) from the HTML shell
4. If the visitor has a stored auth token in `localStorage` (from a previous sign-in), the client connects as an authenticated user and skips guest mode entirely
5. If no auth token exists, the client silently requests a guest token from the preset server (`POST /auth/guest`) -- no dialog, no user interaction whatsoever
6. The client connects as an anonymous guest and navigates directly to the target channel or forum post (from the URL fragment), or the space's default channel if no fragment is present
7. Content appears instantly. The anonymous banner and sign-up CTAs appear as in the desktop flow

### Browsing as an Anonymous User (lazy auth)

All interactive inputs are rendered in a **grayed-out disabled state** rather than hidden. This lets visitors see what they *could* do if they had an account, creating a natural upgrade path. The key design principle is **lazy authentication**: visitors are never stopped or prompted until they attempt to perform an action. Browsing is completely frictionless.

8. User clicks a public channel -- messages load in read-only view
9. All interactive inputs are visible but grayed out (modulate alpha ~0.5); clicking any of them shows a registration prompt -- this is the **only** point where authentication is requested
10. Member list shows authenticated members grouped by role/status as normal, plus a single aggregated entry at the bottom: **"N anonymous users"** (N = server-reported count, updated periodically)
11. A persistent banner above the message view reads: **"You're browsing as a guest"** with **Sign In** / **Register** buttons
12. The visitor can freely browse public channels, read forum posts and replies, and scroll message history -- all without an account

**Grayed-out elements:**

| Element | Guest appearance | On click |
|---------|-----------------|----------|
| Message composer | Visible but grayed out, placeholder text: "Sign in to send a message" | Shows registration prompt |
| Reaction `+` button | Grayed out | Shows registration prompt |
| Existing reaction pills | Visible with counts, grayed out | Shows registration prompt |
| Forum "New Post" button | Grayed out | Shows registration prompt |
| Thread composer | Grayed out, placeholder: "Sign in to reply" | Shows registration prompt |
| Voice channel join | Channel visible in sidebar, grayed out join indicator | Shows registration prompt |
| Context menu actions | Reply/Edit/Delete items grayed out | Shows registration prompt |
| DM button | Grayed out | Shows registration prompt |

**Registration prompt:** A modal dialog that appears when any grayed-out input is clicked:

```
┌──────────────────────────────────────┐
│   Create an account to join the      │
│         conversation                 │
│                                      │
│   ┌────────────┐  ┌───────────────┐  │
│   │  Register  │  │   Sign In     │  │
│   └────────────┘  └───────────────┘  │
│                                      │
│              No thanks               │
└──────────────────────────────────────┘
```

### Browsing a Forum as an Anonymous User

13. User navigates to a forum channel (or arrives via a direct link to a forum post)
14. The forum post list loads showing titles, authors, reply counts, and content previews -- all readable
15. Clicking a post opens the thread panel with full replies visible
16. The thread composer at the bottom is grayed out; clicking it shows the registration prompt
17. The "New Post" button is grayed out; clicking it shows the registration prompt
18. Sort/filter controls remain fully interactive (they are read-only operations)

### Upgrading from Anonymous to Authenticated

19. User clicks "Sign In" or "Register" from the banner, the composer prompt, or any grayed-out input prompt -- this is the **first and only** point where credentials are requested
20. Auth dialog opens in Sign In / Register mode (same as normal server connection flow)
21. On successful auth, the guest token is replaced with a real token, the client reconnects as an authenticated user, and all inputs re-enable
22. `AppState.guest_mode_changed` fires (`false`), UI re-enables all interactive elements
23. The anonymous banner disappears
24. On web, the auth token persists to `localStorage` so future visits to the same URL connect as an authenticated user immediately (bypassing the auto-guest flow entirely)

### Server Discovery Integration

- The master server discovery panel (`scenes/sidebar/guild_bar/discovery_panel.gd`) adds a **"Preview"** button next to "Join" for public spaces
- Clicking "Preview" opens an add-server-like dialog that connects in guest mode without prompting for credentials

## Signal Flow

```
=== ANONYMOUS ENTRY (DESKTOP) ===

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
                -> forum_view._on_guest_mode_changed() -> hide New Post, CTA in thread

=== ANONYMOUS ENTRY (WEB — AUTO-GUEST VIA PRESET SERVER) ===

browser loads https://chat.example.com/#community/help
    -> index.html parses URL fragment -> window.daccordDeepLink = { space: "community", channel: "help" }
    -> index.html has window.daccordPresetServer = { base_url: "https://api.example.com", space_slug: "community" }
    -> Godot engine starts
    -> Client._ready() -> ClientWebLinks.setup()
        -> _read_deep_link(): reads hash from window.location.hash
        -> _read_preset_server(): reads window.daccordPresetServer
    -> ClientWebLinks checks localStorage for auth token:
        -> [has auth token] Client.connect_server() using stored credentials (skip guest entirely)
        -> [no auth token, preset server exists] auto-guest flow:
            -> base_url from preset server config (or window.location.origin if omitted)
            -> POST /auth/guest -> { token, expires_at, space_id }
            -> Client.connect_guest(base_url, guest_token, space_id, expires_at)
                -> (same flow as desktop guest entry above)
            -> sessionStorage.setItem("guest_token", token)
        -> [no auth token, no preset] empty state with Add Server prompt
    -> gateway READY -> AppState.channels_updated
        -> ClientWebLinks._on_channels_updated() -> _navigate_to_deep_link()
            -> finds space by slug, channel by name
            -> AppState.select_space() + AppState.select_channel()
            -> channel_list auto-navigates to target channel

=== ANONYMOUS MEMBER COUNT ===

member_list._ready()
    -> [guest_mode] GET /spaces/{id}/anonymous-count
        -> returns { count: 10 }
    -> _add_anonymous_entry(count)
        -> anonymous_entry_item.setup({ count: 10 })

Gateway event: anonymous_count_updated { count: 12 }
    -> member_list._on_anonymous_count_updated(12)
        -> anonymous_entry_item.update_count(12)

=== GUEST TOKEN REFRESH ===

Client._process() or timer detects token approaching expiry
    -> POST /auth/guest (silent refresh)
        -> returns { token, expires_at }
    -> AccordClient.update_token(new_token)
    -> [web] sessionStorage.setItem("guest_token", new_token)

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
                -> [web] localStorage.setItem("auth_token", token)
                -> [web] sessionStorage.removeItem("guest_token")
                -> [web] update URL fragment (remove guest params)

=== WEB URL NAVIGATION ===

user clicks a public channel in guest mode
    -> channel_list._on_channel_pressed(channel_id)
    -> AppState.select_channel(channel_id)
    -> [web] JavaScriptBridge.eval("history.replaceState(null, '', '#community/general')")
        -> browser URL updates without page reload
        -> URL can be copied/shared to link others to this channel
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/guild_bar/auth_dialog.gd` | Add "Browse without account" button; guest entry point |
| `scenes/sidebar/guild_bar/add_server_dialog.gd` | `_connect_as_guest()` method; skip token requirement |
| `scripts/autoload/client.gd` | `connect_guest()`, `upgrade_guest_connection()`, `guest_mode` flag |
| `scripts/autoload/app_state.gd` | `guest_mode_changed` signal, `is_guest_mode` state |
| `scenes/messages/message_view.gd` | Show/hide anonymous banner; disable composer in guest mode |
| `scenes/messages/composer/composer.gd` | Grayed-out state in guest mode; click triggers registration prompt |
| `scripts/autoload/guest_prompt.gd` | Shared `GuestPrompt` utility: `show_if_guest() -> bool` for all grayed-out inputs |
| `scenes/messages/forum_view.gd` | Grays out "New Post" button in guest mode; `GuestPrompt` on click |
| `scenes/messages/thread_panel.gd` | Grays out thread composer in guest mode; "Sign in to reply" placeholder |
| `scenes/members/member_list.gd` | Anonymous entry item at bottom; fetches `GET /spaces/{id}/anonymous-count` |
| `scenes/members/anonymous_entry_item.gd` | Scene: renders "N anonymous users" row |
| `scenes/members/anonymous_entry_item.tscn` | Scene resource for anonymous entry row |
| `scenes/discovery/discovery_panel.gd` | Wires "Preview" button to guest-mode entry from directory |
| `scenes/discovery/discovery_detail.gd` | "Preview" button + `preview_pressed` signal |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `guest()` method: `POST /auth/guest` |
| `addons/accordkit/models/user.gd` | `is_guest: bool` field on `AccordUser` |
| `dist/web/index.html` | Web HTML shell; handles URL fragment parsing for deep links; contains `window.daccordPresetServer` config for auto-guest |
| `scripts/autoload/client_web_links.gd` | `ClientWebLinks` — reads preset server config, triggers auto-guest connection, manages URL fragment routing |

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

### GuestPrompt Utility

A shared `GuestPrompt` utility standardizes the registration dialog across all components: `GuestPrompt.show_if_guest() -> bool` returns `true` (and shows the dialog) if in guest mode, `false` if authenticated. Every grayed-out interactive element calls this on click.

### Grayed-Out Input Implementation

Interactive components check `AppState.is_guest_mode` and apply a `modulate` alpha (e.g. 0.5) + set `mouse_filter = MOUSE_FILTER_STOP` so clicks are caught. After successful registration/sign-in, `AppState.guest_mode_changed.emit(false)` causes all components to re-enable.

### Composer Read-Only State

`composer.gd` shows a grayed-out state with placeholder text "Sign in to send a message". Clicking the grayed-out composer triggers `GuestPrompt.show_if_guest()` which shows the registration prompt dialog.

### Anonymous Member Count Entry

A new scene `anonymous_entry_item.gd` renders a non-interactive row in the member list. It shows a generic avatar (e.g., a ghost icon from `assets/theme/icons/`) and the label "N anonymous users". The count is fetched from `GET /spaces/{id}/anonymous-count` on member list load, and updated via a new `anonymous_count_updated` WebSocket gateway event. The entry is always pinned to the bottom of the member list, below all role-grouped members.

### Channel Visibility Filtering

The server marks individual channels with `allow_anonymous_read: true`. The `AccordChannel` model in `addons/accordkit/models/channel.gd` needs an `allow_anonymous_read: bool = false` field. In guest mode, `channel_list.gd` hides channels where this is `false`.

### Message Context Menu

`cozy_message.gd` and `collapsed_message.gd` right-click context menus are currently built with Reply / Edit / Delete items. In guest mode, all action items are grayed out. Clicking any grayed-out item triggers `GuestPrompt.show_if_guest()` which shows the registration prompt.

### Reaction Bar

`message_content.gd` reaction pills show count and emoji but are grayed out in guest mode. Clicking any reaction pill or the `+` button triggers `GuestPrompt.show_if_guest()` which shows the registration prompt.

### Gateway Subscription

In guest mode, the WebSocket gateway connection should subscribe only to public channel events. The `GatewayIntents` bitmask sent on login should use a new `GatewayIntents.GUEST` constant (messages + member count only, no presence, no DMs, no voice).

### Web Deep Links, Preset Servers, and Auto-Guest

The web export uses URL-based routing so that shared links open the correct channel or forum post. Each web deployment is configured with a **preset server** -- the accordserver instance baked into the HTML shell via `window.daccordPresetServer`. This eliminates all manual server configuration for visitors.

**URL format:** `https://chat.example.com/#<space>/<channel>[/<post-id>]`

Examples:
- `https://chat.example.com/` -- opens the preset server's default channel in guest mode
- `https://chat.example.com/#general` -- opens the "general" channel in guest mode
- `https://chat.example.com/#community/help` -- opens the "help" channel in the "community" space
- `https://chat.example.com/#community/forum/1234567890` -- opens a specific forum post

**Preset server configuration** (in `dist/web/index.html`):
```html
<script>
  window.daccordPresetServer = {
    base_url: "https://api.example.com",  // omit to use window.location.origin
    space_slug: "community"
  };
</script>
```

On load, the web client:
1. Reads the preset server config from `window.daccordPresetServer`
2. Checks `localStorage` for a stored auth token from a previous sign-in
3. If auth token exists: connects as authenticated user (normal flow, skip guest entirely)
4. If no auth token: silently requests a guest token from the preset server (`POST /auth/guest`) -- no dialog, no user interaction
5. Connects as guest and navigates directly to the target channel/post from the URL fragment
6. Updates the URL fragment as the user navigates between public channels (so the browser URL always reflects the current view and can be copied/shared)

**Lazy authentication:** The visitor is never stopped or prompted during browsing. Only when they click a grayed-out interactive element (composer, reaction button, etc.) does a registration prompt appear. After sign-in/register, the auth token is stored in `localStorage` so future visits connect as an authenticated user immediately.

If the user signs in, the fragment routing continues to work but with full permissions. The server base URL comes from the preset config (or defaults to `window.location.origin` when the web client is served from the same domain as the accordserver).

### SEO and Server-Side Rendering

WASM apps are not natively crawlable by search engines -- the content is rendered client-side in a canvas element. To make public channels and forum posts indexable, the accordserver (or a companion service) should serve **HTML snapshots** for crawler user agents.

**How it works:**

1. The web server detects crawler user agents (Googlebot, Bingbot, etc.) via the `User-Agent` header
2. Instead of serving the WASM app, it returns a lightweight HTML page with the channel or forum post content rendered as semantic HTML (`<article>`, `<h1>`, `<p>`, `<time>`, etc.)
3. The HTML includes `<meta>` tags for Open Graph and Twitter Card previews (title, description, image) so that links shared on social media display rich previews
4. A `<link rel="canonical">` points to the clean URL
5. A `<noscript>` fallback in the main HTML shell provides a link to the server-rendered version for clients without JavaScript/WASM support

**What gets indexed (forum channels are the primary target):**
- Forum post titles and body content
- Thread replies (paginated, with `rel="next"` links)
- Author names and timestamps
- Channel names and space descriptions

**What does NOT get indexed:**
- Channels without `allow_anonymous_read: true`
- DM content (never public)
- Voice channel state
- Member list details beyond public display names

This is implemented server-side (in accordserver or as a reverse proxy middleware), not in the Godot client. The client's role is limited to URL routing so that linked pages load the correct content when a human visitor arrives.

### Open Graph Previews

When someone shares a link to a public channel or forum post on social media, messaging apps, or other platforms, the link should display a rich preview. The server-side HTML snapshot includes:

```html
<meta property="og:title" content="How to configure widgets - Community Forum">
<meta property="og:description" content="Step-by-step guide to setting up widgets in your workspace...">
<meta property="og:type" content="article">
<meta property="og:url" content="https://chat.example.com/#community/forum/1234567890">
<meta property="og:site_name" content="Community Server">
<meta property="og:image" content="https://chat.example.com/cdn/space-icon.png">
```

This means a forum post link shared on Twitter, Slack, or Discord shows the post title, a content snippet, and the server icon -- significantly increasing click-through compared to a bare URL.

### Forum Guest Mode Behavior

Forum channels in guest mode have specific UI adaptations:

| Element | Authenticated | Guest Mode |
|---------|--------------|------------|
| Post list | Full post list with sort/filter | Same -- read-only browsing |
| New Post button | Visible, opens creation form | Grayed out; click shows registration prompt |
| Thread replies | Full composer at bottom | Composer grayed out; click shows registration prompt |
| Post context menu | Open Thread, Edit, Delete | Open Thread only (read actions) |
| Sort/filter bar | Fully interactive | Fully interactive (read-only operation) |
| Reply count / activity | Visible | Visible |

### Guest Token Lifecycle

Guest tokens are intentionally short-lived (server-configurable, suggested default: 1 hour). This limits the window for abuse and reduces the server's obligation to track anonymous sessions.

**Token refresh:** When a guest token approaches expiry, the client silently requests a new one via `POST /auth/guest`. This is invisible to the user -- browsing continues uninterrupted. If the refresh fails (server down, rate limited), the client shows a non-blocking notice: "Connection lost. Refresh the page to continue browsing."

**Rate limiting:** The server should rate-limit `POST /auth/guest` by IP address to prevent abuse (e.g., max 10 guest tokens per IP per hour). Excessive requests return `429 Too Many Requests`.

**Web session persistence:** Guest tokens are stored in `sessionStorage` (cleared when the tab closes -- anonymous sessions are truly transient). Authenticated tokens (after sign-in/register) are stored in `localStorage` (persists across sessions -- return visits connect as the authenticated user immediately, skipping the auto-guest flow). On startup, the client checks `localStorage` first; if an auth token exists for the preset server, it connects as an authenticated user. Otherwise, it falls through to the auto-guest path.

## Implementation Status

### Core guest mode
- [ ] `POST /auth/guest` server endpoint
- [x] `AuthApi.guest()` client method
- [x] `AccordUser.is_guest` field
- [x] `AccordChannel.allow_anonymous_read` field
- [x] `Client.connect_guest()` / `Client.upgrade_guest_connection()`
- [x] `AppState.guest_mode_changed` signal and `is_guest_mode` state
- [x] `GatewayIntents.guest()` static method (reduced intent set)
- [x] Guest token refresh on expiry
- [ ] Guest token rate limiting (server-side)
- [x] Client mutation methods guarded in guest mode (send, edit, delete, react, typing, DM)

### Client UI (desktop + web)
- [x] "Browse without account" button in `auth_dialog.gd`
- [x] `add_server_dialog._connect_as_guest()` method
- [x] `GuestPrompt` shared utility for registration dialog
- [x] Persistent "You're browsing as a guest" banner with Sign In / Register buttons
- [x] Composer grayed out with "Sign in to send a message" placeholder; click shows registration prompt
- [x] Reaction buttons grayed out; click shows registration prompt
- [x] Forum "New Post" button grayed out; click shows registration prompt
- [x] Thread composer grayed out; click shows registration prompt
- [x] Voice channel join grayed out; click shows registration prompt
- [x] Context menu actions grayed out; click shows registration prompt
- [x] DM button grayed out; click shows registration prompt
- [x] `anonymous_entry_item` scene + script
- [x] Member list anonymous count fetch + gateway event
- [x] Channel list guest filtering
- [x] Discovery panel "Preview" button for guest-mode entry
- [x] Guest connections excluded from Config persistence / session restore

### Web-specific (preset server & auto-guest)
- [x] URL fragment routing in HTML shell (`#space/channel/post-id`)
- [x] `window.daccordPresetServer` config block in HTML shell
- [x] `ClientWebLinks._read_preset_server()` reads preset config via JavaScriptBridge
- [x] Auto-guest-connect on web via preset server (no user interaction required)
- [x] `localStorage` auth token check: skip guest flow if authenticated session exists
- [x] Same-origin fallback for `base_url` when omitted from preset config
- [x] URL fragment updates as user navigates public channels
- [x] Guest token stored in `sessionStorage` on web
- [x] Auth token stored in `localStorage` on web after sign-in/register
- [x] `<noscript>` fallback link to server-rendered content

### SEO and link previews
- [x] Server-side HTML snapshots for crawler user agents (accordserver)
- [x] Open Graph / Twitter Card `<meta>` tags on HTML snapshots
- [x] `<link rel="canonical">` on server-rendered pages
- [x] Forum post content rendered as semantic HTML for crawlers
- [x] `rel="next"` pagination for threaded forum replies

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No `POST /auth/guest` server endpoint | High | Entire feature blocked on accordserver support; client-side code is ready but untestable without it |
| Guest token rate limiting (server-side) | Medium | Server should rate-limit `POST /auth/guest` by IP (e.g. 10 tokens/IP/hour) to prevent abuse |
| `try_auto_connect()` not wired in Client._ready | Medium | `ClientWebLinks.try_auto_connect()` exists but needs to be called from `Client._ready()` on web builds |

## Related User Flows

| Flow | Relationship |
|------|-------------|
| [Web Export](web_export.md) | Read only mode is the primary use case for the web export -- shareable URLs that anyone can open in a browser |
| [Forums](forums.md) | Forum channels are the strongest SEO driver; public forum posts become indexable web content |
| [Master Server Discovery](master_server_discovery.md) | Discovery panel "Preview" button uses guest mode to let users browse before joining |
| [URL Protocol](url_protocol.md) | Desktop deep links (`daccord://`) complement web URLs for the native client |
| [User Onboarding](user_onboarding.md) | Guest-to-authenticated upgrade is an onboarding path; the CTA banners guide conversion |
| [Server Connection](server_connection.md) | Guest mode is a variant of the server connection flow, skipping credentials |
