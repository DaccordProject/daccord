# Read Only Mode

## Overview

Read only mode allows anonymous (unregistered) users to browse public channels on an accordserver instance without creating an account. Anonymous viewers can read message history and see the member list, but cannot perform any actions. Multiple anonymous viewers are aggregated into a single "N anonymous users" entry in the member list rather than appearing as individual accounts.

## Why Read Only Mode Matters

### The core idea

Most chat platforms are walled gardens -- you must create an account before you can see anything. Read only mode flips this: server admins can make selected channels publicly viewable so anyone with a link can read them instantly, no sign-up required. This is especially powerful when combined with the [Web Export](web_export.md), which lets daccord run directly in a browser.

### Shareable URLs for the web

The web export produces a hosted version of daccord that runs in any modern browser. Read only mode means a server admin can share a URL like `https://chat.example.com/#general` and anyone who clicks it lands directly in the channel, reading messages immediately. No download, no account, no friction. This turns every public channel into a webpage anyone can visit.

### Forums and SEO

Forum channels (see [Forums](forums.md)) benefit the most from read only mode. Forum posts have titles, threaded replies, and long-form content -- exactly the kind of structured text that search engines index well. When a forum channel is marked as publicly readable:

- **Search engines can crawl it.** Google, Bing, and others can index post titles, content, and replies. A question asked in your forum can appear in search results, bringing new visitors directly to your server's web client.
- **Organic discovery.** Someone searching "how to configure X" might land on a forum post in your community. They see the answer, browse other posts, and eventually sign up. This is the same growth loop that made platforms like Reddit, Stack Overflow, and Discourse successful.
- **Link sharing works.** Members can share links to specific forum posts on social media, blogs, or other chat platforms. Recipients see the full content immediately without hitting a login wall.

### For server admins (non-technical summary)

Read only mode lets you open your community's doors to the public internet. You choose which channels are visible to anonymous visitors -- typically announcement channels, forums, and help channels. Visitors can browse freely and sign up when they're ready to participate. It's the difference between a locked clubhouse and a shop with an open front door.

### For developers (technical summary)

The client authenticates with a short-lived guest token from `POST /auth/guest`, scoped to channels with `allow_anonymous_read: true`. The guest connection is transient (not persisted to Config), uses a reduced gateway intent set, and all write operations are blocked both client-side (UI disabled) and server-side (token lacks write permissions). Upgrading to a full account replaces the guest token in-place without reconnecting from scratch. The web export serves the client as static WASM/HTML that connects to the same accordserver REST + WebSocket APIs as the desktop client.

## User Steps

### Entering Read Only Mode (Desktop)

1. User opens daccord (fresh install or via deep link)
2. On the Add Server dialog or auth dialog the user clicks **"Browse without account"**
3. daccord connects to the server without credentials via `GET /auth/guest` to receive a short-lived guest token
4. Server returns a guest token scoped to public-readable channels only
5. Client enters **Guest mode**: connects with a transient token, no Config entry saved, no profile created
6. Channel list loads showing only channels the server has marked as readable by guests (`allow_anonymous_read: true`)
7. A persistent **"You're browsing anonymously"** banner appears above the message view with a **"Sign In"** and **"Register"** button

### Entering Read Only Mode (Web)

1. Someone shares a link to the hosted web client, e.g. `https://chat.example.com/#general` or `https://chat.example.com/forum/post-title`
2. The browser loads the daccord WASM app (see [Web Export](web_export.md))
3. The web client detects no stored credentials and the URL contains a server + channel/post target
4. The client automatically requests a guest token from the server (`POST /auth/guest`) -- no dialog needed
5. The target channel or forum post loads directly in read-only view
6. The anonymous banner and sign-up CTAs appear as in the desktop flow

### Browsing as an Anonymous User

8. User clicks a public channel -- messages load in read-only view
9. Composer area is replaced by a call-to-action: **"Sign in to join the conversation"** with Sign In / Register buttons
10. Right-click context menu on messages shows no options (empty / "No actions available")
11. Member list shows authenticated members grouped by role/status as normal, plus a single aggregated entry at the bottom: **"N anonymous users"** (N = server-reported count, updated periodically)
12. Reaction pills are visible but clicking them shows a tooltip: "Sign in to react"
13. Voice channel items are visible but clicking shows: "Sign in to join voice"
14. No DM button or DM list is accessible

### Browsing a Forum as an Anonymous User

15. User navigates to a forum channel (or arrives via a direct link to a forum post)
16. The forum post list loads showing titles, authors, reply counts, and content previews -- all read-only
17. Clicking a post opens the thread panel with full replies visible
18. The thread composer is replaced with the same sign-up CTA as the main composer
19. "New Post" button is hidden or replaced with: **"Sign in to start a discussion"**

### Upgrading from Anonymous to Authenticated

20. User clicks "Sign In" or "Register" from the banner or composer CTA
21. Auth dialog opens in Sign In / Register mode (same as normal server connection flow)
22. On successful auth, the guest token is discarded, a real token is saved to Config, and the client reconnects as an authenticated user
23. `AppState.guest_mode_changed` fires (`false`), UI re-enables all interactive elements
24. The anonymous banner disappears; composer re-enables
25. On web, the browser URL updates to remove any guest-mode query params; a cookie or `localStorage` token persists the session

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

=== ANONYMOUS ENTRY (WEB — DEEP LINK) ===

browser loads https://chat.example.com/#community/help
    -> index.html parses URL fragment -> { space: "community", channel: "help" }
    -> Godot engine starts, Client._ready() detects web deep link args
        -> base_url = window.location.origin (same origin as web host)
        -> POST /auth/guest -> { token, expires_at, space_id }
        -> Client.connect_guest(base_url, guest_token, space_id)
            -> (same flow as desktop guest entry above)
        -> AppState.select_channel_by_name("help")
            -> channel_list auto-navigates to target channel
        -> sessionStorage.setItem("guest_token", token)

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
| `scenes/messages/composer/composer.gd` | Read-only CTA state replacing input area |
| `scenes/messages/forum_view.gd` | Hide "New Post" button in guest mode; thread composer CTA |
| `scenes/members/member_list.gd` | `anonymous_entry_item` aggregated count row |
| `scenes/members/anonymous_entry_item.gd` | New scene: renders "N anonymous users" row |
| `scenes/sidebar/guild_bar/discovery_panel.gd` | "Preview" button for guest-mode entry from directory |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `guest()` method: `POST /auth/guest` |
| `addons/accordkit/models/user.gd` | `is_guest: bool` field on `AccordUser` |
| `export/web/index.html` | Web HTML shell; handles URL fragment parsing for deep links |

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

### Web Deep Links and URL Routing

The web export needs URL-based routing so that shared links open the correct channel or forum post. The HTML shell (`export/web/index.html`) parses the URL fragment on load and passes it to the Godot engine as a command-line argument or via `JavaScriptBridge`.

**URL format:** `https://chat.example.com/#<space>/<channel>[/<post-id>]`

Examples:
- `https://chat.example.com/#general` -- opens the "general" channel in guest mode
- `https://chat.example.com/#community/help` -- opens the "help" channel in the "community" space
- `https://chat.example.com/#community/forum/1234567890` -- opens a specific forum post

On load, the web client:
1. Parses the URL fragment to extract space name, channel name, and optional post ID
2. Requests a guest token from the server embedded in the URL's origin
3. Connects in guest mode and navigates directly to the target channel/post
4. Updates the URL fragment as the user navigates between public channels (so the browser URL always reflects the current view and can be copied/shared)

If the user signs in, the fragment routing continues to work but with full permissions. The server base URL is implicit from the hosting origin (the web client is served from the same domain as the accordserver, or a configured API base URL).

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
| New Post button | Visible, opens creation form | Replaced with "Sign in to start a discussion" |
| Thread replies | Full composer at bottom | Composer replaced with sign-up CTA |
| Post context menu | Open Thread, Edit, Delete | Open Thread only (read actions) |
| Sort/filter bar | Fully interactive | Fully interactive (read-only operation) |
| Reply count / activity | Visible | Visible |

### Guest Token Lifecycle

Guest tokens are intentionally short-lived (server-configurable, suggested default: 1 hour). This limits the window for abuse and reduces the server's obligation to track anonymous sessions.

**Token refresh:** When a guest token approaches expiry, the client silently requests a new one via `POST /auth/guest`. This is invisible to the user -- browsing continues uninterrupted. If the refresh fails (server down, rate limited), the client shows a non-blocking notice: "Connection lost. Refresh the page to continue browsing."

**Rate limiting:** The server should rate-limit `POST /auth/guest` by IP address to prevent abuse (e.g., max 10 guest tokens per IP per hour). Excessive requests return `429 Too Many Requests`.

**Web session persistence:** On web, the guest token is stored in `sessionStorage` (not `localStorage`) so it is automatically cleared when the browser tab closes. This ensures anonymous sessions are truly transient.

## Implementation Status

### Core guest mode
- [ ] `POST /auth/guest` server endpoint
- [ ] `AuthApi.guest()` client method
- [ ] `AccordUser.is_guest` field
- [ ] `AccordChannel.allow_anonymous_read` field
- [ ] `Client.connect_guest()` / `Client.upgrade_guest_connection()`
- [ ] `AppState.guest_mode_changed` signal and `is_guest_mode` state
- [ ] `GatewayIntents.GUEST` constant
- [ ] Guest token refresh on expiry
- [ ] Guest token rate limiting (server-side)

### Client UI (desktop + web)
- [ ] "Browse without account" button in `auth_dialog.gd`
- [ ] `add_server_dialog._connect_as_guest()` method
- [ ] Anonymous banner in `message_view.gd`
- [ ] Composer CTA read-only state in `composer.gd`
- [ ] `anonymous_entry_item` scene + script
- [ ] Member list anonymous count fetch + gateway event
- [ ] Channel list guest filtering
- [ ] Message context menu suppression in guest mode
- [ ] Reaction bar guest-mode tooltip / hide `+` button
- [ ] Forum view guest mode (hide New Post, CTA in thread composer)
- [ ] Discovery panel "Preview" button for guest-mode entry
- [ ] Guest connections excluded from Config persistence / session restore

### Web-specific
- [ ] URL fragment routing in HTML shell (`#space/channel/post-id`)
- [ ] Auto-guest-connect on web when URL contains a channel target
- [ ] URL fragment updates as user navigates public channels
- [ ] Guest token stored in `sessionStorage` on web
- [ ] `<noscript>` fallback link to server-rendered content

### SEO and link previews
- [ ] Server-side HTML snapshots for crawler user agents (accordserver)
- [ ] Open Graph / Twitter Card `<meta>` tags on HTML snapshots
- [ ] `<link rel="canonical">` on server-rendered pages
- [ ] Forum post content rendered as semantic HTML for crawlers
- [ ] `rel="next"` pagination for threaded forum replies

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No `POST /auth/guest` server endpoint | High | Entire feature blocked on accordserver support; client changes are meaningless without it |
| No `allow_anonymous_read` channel flag | High | Server must expose per-channel guest visibility; currently no such field in `AccordChannel` model (`addons/accordkit/models/channel.gd`) |
| No `Client.connect_guest()` method | High | `client.gd` only supports authenticated connections; new code path required |
| No `AppState.guest_mode_changed` signal | High | All UI components rely on this for guest state transitions |
| No anonymous member count endpoint | High | `GET /spaces/{id}/anonymous-count` and corresponding gateway event don't exist in accordkit REST layer |
| No server-side HTML rendering for SEO | High | WASM content is invisible to search engines; requires accordserver-side work or a reverse proxy to serve HTML snapshots for crawlers |
| No web URL routing for deep links | High | Without URL fragment parsing, shared links just load the default empty state instead of the target channel/post |
| Composer has no CTA read-only state | Medium | `composer.gd` has disabled state but no "sign in" CTA panel |
| Auth dialog has no "Browse without account" button | Medium | `auth_dialog.gd` only has Sign In / Register tabs (line 9) |
| No `anonymous_entry_item` scene | Medium | Member list has no aggregated anonymous row; entirely new scene needed |
| Guest connections not excluded from Config persistence | Medium | `add_server_dialog.gd` always calls `Config.add_server()`; guest must skip this |
| Message context menu not suppressed in guest mode | Medium | `cozy_message.gd` builds context menu without checking guest mode |
| Forum view has no guest-mode adaptations | Medium | `forum_view.gd` shows "New Post" button and thread composer regardless of auth state |
| No Open Graph meta tags for link previews | Medium | Shared links on social media show no title/description/image preview |
| Reaction `+` button not hidden in guest mode | Low | `message_content.gd` reaction bar has no guest-mode branch |
| No `GatewayIntents.GUEST` constant | Low | `addons/accordkit/models/intents.gd` has no reduced-scope guest intent set |
| Discovery panel has no "Preview" (guest entry) button | Low | `scenes/sidebar/guild_bar/discovery_panel.gd` only has "Join" |
| Guest session not restored across launches | Low | By design: transient connections should not persist, but this should be documented in Config flow |
| Token expiry handling for guest tokens | Low | Short-lived guest tokens will expire; client needs silent refresh or re-guest logic |
| No `<noscript>` fallback | Low | Users with JS disabled see a blank page; a fallback link to server-rendered content improves accessibility |

## Related User Flows

| Flow | Relationship |
|------|-------------|
| [Web Export](web_export.md) | Read only mode is the primary use case for the web export -- shareable URLs that anyone can open in a browser |
| [Forums](forums.md) | Forum channels are the strongest SEO driver; public forum posts become indexable web content |
| [Master Server Discovery](master_server_discovery.md) | Discovery panel "Preview" button uses guest mode to let users browse before joining |
| [URL Protocol](url_protocol.md) | Desktop deep links (`daccord://`) complement web URLs for the native client |
| [User Onboarding](user_onboarding.md) | Guest-to-authenticated upgrade is an onboarding path; the CTA banners guide conversion |
| [Server Connection](server_connection.md) | Guest mode is a variant of the server connection flow, skipping credentials |
