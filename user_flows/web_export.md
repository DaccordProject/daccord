# Web Export

## Overview

This flow covers exporting daccord to the web (Godot Web / WASM). The web build produces static files (HTML/JS/WASM/PCK) that can be served from any static web host. Voice and video use the LiveKit JS SDK (`livekit-client`) via a custom JavaScript wrapper (`godot-livekit-web.js`) that mirrors the GDExtension API surface, bridged to GDScript through `WebVoiceSession` and `JavaScriptBridge`.

Beyond a functional chat client, the web export serves as a **public-facing front door** for accordserver communities. Shareable URLs link directly to channels, forums, and forum topics. Servers that allow guests render content in a read-only view with grayed-out inputs that prompt visitors to register when clicked. Server-side HTML snapshots make public content crawlable by search engines, turning forum posts into indexable web pages.

## User Steps

### Export & deploy (developer)

1. Developer runs `./web-export.sh` which:
   - Runs `godot --headless --export-release "Web"` producing output in `dist/web/`.
   - Downloads the `livekit-client` UMD bundle into `dist/web/`.
   - Copies `godot-livekit-web.js` from the addon into `dist/web/`.
2. Developer hosts `dist/web/` on a static web server (must serve with COOP/COEP headers or use the bundled `coop_coep.js` service worker for cross-origin isolation).
3. User opens the web URL in a browser; daccord boots into the same empty-state experience as desktop when no servers are configured.

### Text chat (user)

4. User adds a server via "Add Server" and connects (same flow as desktop).
5. User navigates channels and sends/receives messages (same flow as desktop).

### Voice (web)

6. User clicks a voice channel to join.
7. Browser prompts for microphone permission (first use).
8. `ClientVoice` calls REST `VoiceApi.join()` and receives voice server credentials.
9. `WebVoiceSession` creates a LiveKit room via `JavaScriptBridge.eval("GodotLiveKit.createRoom()")` and calls `connectToRoom(url, token)`.
10. The `livekit-client` JS SDK handles WebRTC transport, ICE negotiation, and media.
11. Voice bar appears; mute/deafen toggles call `setMicrophoneEnabled()` on the local participant.

### Video (web)

12. While in voice, user clicks "Cam" to enable camera.
13. Browser prompts for camera permission (first use).
14. `WebVoiceSession.publish_camera()` calls `setCameraEnabled(true)` on the local participant. Returns a `WebVideoStub` (no local preview on web).
15. Remote video tracks arrive via `trackSubscribed` events and are forwarded through `track_received` signals.

### Shareable links

16. User navigates to a channel or forum post on the web client.
17. The browser URL updates in real time to reflect the current view (e.g. `https://chat.example.com/#community/general`).
18. User copies the URL from the browser address bar and shares it (chat, social media, email, etc.).
19. Recipient clicks the link; the web client loads and navigates directly to that channel or post.

**URL format:** `https://<host>/#<space-slug>/<channel-slug>[/<post-id>]`

| URL | Target |
|-----|--------|
| `https://chat.example.com/#general` | The "general" channel (default space) |
| `https://chat.example.com/#community/announcements` | The "announcements" channel in the "community" space |
| `https://chat.example.com/#community/help-forum` | The "help-forum" forum channel (shows post list) |
| `https://chat.example.com/#community/help-forum/1234567890` | A specific forum post and its thread |

### Guest browsing (server allows guests)

20. A visitor clicks a shared link to a server that has `allow_guest_access` enabled.
21. The web client detects no stored credentials and the URL contains a target.
22. The client automatically requests a guest token from the server via `POST /auth/guest`.
23. Content loads in **read-only mode**: all interactive inputs (composer, reaction buttons, "New Post" button, context menu actions) are **grayed out** (visible but visually disabled).
24. When the visitor **clicks any grayed-out input**, a prompt appears: **"Create an account to join the conversation"** with **Register** and **Sign In** buttons.
25. The visitor can freely browse public channels, read forum posts and replies, and scroll message history -- all without an account.
26. A persistent banner above the message view reads: **"You're browsing as a guest"** with **Sign In** / **Register** buttons.

### Guest browsing a forum

27. Visitor navigates to a forum channel (or arrives via a direct link to a forum post).
28. The forum post list loads with titles, authors, reply counts, and content previews -- all readable.
29. Clicking a post opens the thread panel with full replies visible.
30. The thread composer at the bottom is grayed out. Clicking it shows the registration prompt.
31. The "New Post" button is grayed out. Clicking it shows the registration prompt.
32. Sort/filter controls remain fully interactive (they are read-only operations).

### Upgrading from guest to authenticated

33. Visitor clicks "Register" or "Sign In" from the banner, the composer prompt, or any grayed-out input prompt.
34. Auth dialog opens (same as normal server connection flow).
35. On successful auth, the guest token is replaced with a real token, the client reconnects as an authenticated user, and all inputs re-enable.
36. On web, a `localStorage` token persists the session for future visits.

### SEO (server-side)

37. A search engine crawler (Googlebot, Bingbot, etc.) requests a public URL like `https://chat.example.com/#community/help-forum/1234567890`.
38. The web server detects the crawler user agent and serves a **static HTML snapshot** instead of the WASM app.
39. The HTML snapshot contains the forum post content as semantic HTML (`<article>`, `<h1>`, `<p>`, `<time>`) with Open Graph and Twitter Card `<meta>` tags.
40. The search engine indexes the content. The post appears in search results with the title and a content snippet.
41. A human clicks the search result and lands on the web client, which loads the WASM app and navigates to the post.

## Signal Flow

```
=== VOICE (WEB) ===

voice_channel_item.gd            AppState                 Client / ClientVoice
     |                              |                              |
     |-- channel_pressed(id) ------>|                              |
     |                              |-- join_voice_channel(id) --->|
     |                              |                              |-- VoiceApi.join(id)
     |                              |                              |
     |                              |-- (Desktop) LiveKitAdapter.connect_to_room()
     |                              |-- (Web)     WebVoiceSession.connect_to_room()
     |                              |                              |
     |<-- voice_joined(id) ---------|                              |

WebVoiceSession (GDScript)   <-->   JavaScriptBridge   <-->   godot-livekit-web.js
     |                                                              |
     | createRoom() -------------------------------------------------|
     | connectToRoom(url, token) ------------------------------------|
     | on("connected", cb) <---- room events ------------------------|
     | on("participantConnected", cb) <-----------------------------|
     | on("trackSubscribed", cb) <----------------------------------|
     | on("activeSpeakersChanged", cb) <----------------------------|

=== SHAREABLE LINKS & URL ROUTING ===

browser loads https://chat.example.com/#community/help
    -> index.html parses URL fragment -> { space: "community", channel: "help" }
    -> Godot engine starts
    -> Client._ready() detects web deep link args
        -> [no credentials] POST /auth/guest -> { token, expires_at, space_id }
        -> Client.connect_guest(base_url, guest_token, space_id)
        -> AppState.guest_mode_changed.emit(true)
        -> [has credentials] Client.connect_server() (normal auth flow)
    -> AppState.select_channel_by_name("help")
        -> channel navigates to target

user navigates between channels
    -> AppState.channel_selected
    -> [web] JavaScriptBridge.eval("history.replaceState(null, '', '#community/general')")
        -> browser URL updates without page reload
        -> URL is always copy-pasteable and shareable

=== GUEST MODE — GRAYED-OUT INPUTS ===

guest clicks grayed-out composer / reaction / New Post button
    -> _on_disabled_input_clicked()
    -> _show_registration_prompt()
        -> prompt dialog: "Create an account to join the conversation"
            -> [Register] auth_dialog.open(base_url, mode=REGISTER)
            -> [Sign In]  auth_dialog.open(base_url, mode=SIGN_IN)

guest clicks "Register" on banner
    -> auth_dialog.open(base_url, mode=REGISTER)
        -> auth_completed(base_url, token, username, password)
            -> Client.upgrade_guest_connection(idx, token, username, password)
                -> Config.add_server(base_url, token, space_name, username, password)
                -> Client.connect_server(idx) (re-connects as real user)
                -> AppState.guest_mode_changed.emit(false)
                    -> all grayed-out inputs re-enable
                    -> banner disappears
                -> [web] localStorage.setItem("auth_token", token)

=== SEO (SERVER-SIDE) ===

crawler requests https://chat.example.com/#community/help-forum/1234567890
    -> reverse proxy / accordserver detects crawler User-Agent
    -> serves static HTML snapshot:
        <html>
          <head>
            <meta property="og:title" content="Post Title — Community Forum">
            <meta property="og:description" content="First 200 chars of post...">
            <meta property="og:image" content="https://chat.example.com/cdn/space-icon.png">
            <link rel="canonical" href="https://chat.example.com/#community/help-forum/1234567890">
          </head>
          <body>
            <article>
              <h1>Post Title</h1>
              <p>Post content...</p>
              <section class="replies">...</section>
            </article>
          </body>
        </html>
    -> search engine indexes title, content, replies
    -> human clicks search result -> loads WASM app -> navigates to post
```

## Key Files

| File | Role |
|------|------|
| `web-export.sh` | One-step export script: runs Godot web export, downloads `livekit-client` UMD, copies `godot-livekit-web.js` into `dist/web/`. |
| `export/web/index.html` | Custom HTML shell template. Uses `$GODOT_CONFIG` (Godot 4.5 consolidated placeholder). Loads `livekit-client.umd.min.js` and `godot-livekit-web.js` before the engine. Registers the `coop_coep.js` service worker for cross-origin isolation. Parses URL fragment on load for deep link routing. |
| `export/web/coop_coep.js` | Service worker that adds `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers (required for `SharedArrayBuffer` / WASM threads in Chrome). |
| `export/web/godot-livekit-web.js` | JavaScript wrapper around `livekit-client.js` that mirrors the godot-livekit GDExtension API surface. Exposes `GodotLiveKit.createRoom()` globally. |
| `export_presets.cfg` (preset `Web`) | Web export preset. `export_path="dist/web/Daccord.html"`, `custom_html_shell="res://export/web/index.html"`. Excludes `addons/godot-livekit/*` (GDExtension not used on web). |
| `scripts/autoload/web_voice_session.gd` | `WebVoiceSession` — web-only voice session using `JavaScriptBridge` to call into `godot-livekit-web.js`. Mirrors `LiveKitAdapter` signal/API surface. No-ops on non-web builds. |
| `scripts/autoload/client_voice.gd` | Voice join pipeline: calls REST join, then routes to `LiveKitAdapter` (desktop) or `WebVoiceSession` (web). |
| `scripts/autoload/app_state.gd` | `guest_mode_changed` signal, `is_guest_mode` state for toggling read-only UI. |
| `scripts/autoload/client.gd` | `connect_guest()`, `upgrade_guest_connection()`, `guest_mode` flag; URL fragment navigation on web. |
| `scenes/messages/composer/composer.gd` | Grayed-out state in guest mode; click triggers registration prompt. |
| `scenes/messages/forum_view.gd` | Forum post list; grayed-out "New Post" button in guest mode. |
| `addons/accordkit/rest/endpoints/auth_api.gd` | `guest()` method: `POST /auth/guest`. |
| `.github/workflows/ci.yml` (`web-export` job) | CI web export: builds to `dist/build/web/`, validates artifacts, copies `coop_coep.js`, runs Chrome headless smoke test. |
| `.github/workflows/release.yml` (`web` matrix entry) | Release build: exports web, downloads `livekit-client` UMD bundle, copies `godot-livekit-web.js` and `coop_coep.js`, packages everything into `daccord-web.zip` for the GitHub release. |

## Implementation Details

### HTML shell template (Godot 4.5)

The custom HTML shell at `export/web/index.html` uses Godot 4.5's `$GODOT_CONFIG` placeholder — a single JSON object that Godot substitutes at export time containing `canvasResizePolicy`, `experimentalVK`, `focusCanvas`, `executable`, `gdextensionLibs`, etc. The template assigns the `canvas` element after substitution:

```js
const GODOT_CONFIG = $GODOT_CONFIG;
GODOT_CONFIG.canvas = document.getElementById("canvas");
```

Other valid Godot 4.5 placeholders used: `$GODOT_PROJECT_NAME`, `$GODOT_HEAD_INCLUDE`, `$GODOT_URL`, `$GODOT_SPLASH`.

### Cross-origin isolation

Chrome requires `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers for `SharedArrayBuffer` (used by WASM threads). The `coop_coep.js` service worker intercepts fetch events and adds these headers. On first visit the worker installs and the page reloads; subsequent loads are isolated.

### LiveKit JS SDK integration

The web voice pipeline bypasses the native GDExtension entirely:

1. `livekit-client.umd.min.js` — the official LiveKit JS SDK, loaded as a UMD bundle exposing `window.LivekitClient`.
2. `godot-livekit-web.js` — a thin wrapper that creates room objects matching the GDExtension method names (`connectToRoom`, `disconnectFromRoom`, `getLocalParticipant`, `setMicrophoneEnabled`, `setCameraEnabled`, etc.) and converts LiveKit events into a shape GDScript can consume via `JavaScriptBridge`.
3. `WebVoiceSession` (GDScript) — creates rooms via `JavaScriptBridge.eval("GodotLiveKit.createRoom()")`, wires JS event callbacks (`connected`, `disconnected`, `participantConnected`, `trackSubscribed`, `activeSpeakersChanged`, etc.), and emits the same signals as `LiveKitAdapter`.

Audio playback is handled automatically by the `livekit-client` SDK (no GDScript involvement). Video tracks arrive as `trackSubscribed` events and are forwarded via `track_received` signals. A `_process()` poll checks connection state as a safety net for missed JS events.

### WebVoiceSession limitations

- **No local video preview:** `publish_camera()` returns a `WebVideoStub` (no actual video texture).
- **No screen sharing:** `publish_screen()` returns `null`.
- **No per-device selection:** Device enumeration in settings depends on the LiveKit GDExtension.
- **Deafen is local only:** `set_deafened()` stores state but does not suppress remote audio playback (requires JS-side gain control).
- **Connect timeout:** 15-second timer; emits `FAILED` state if room doesn't connect.

### Shareable URLs and deep link routing

The web export uses URL fragment routing so that every view has a shareable URL. The HTML shell (`export/web/index.html`) parses the URL fragment on load and passes it to the Godot engine via `JavaScriptBridge`.

**URL format:** `https://<host>/#<space-slug>/<channel-slug>[/<post-id>]`

**On page load:**
1. `index.html` extracts the URL fragment and sets `window.daccordDeepLink = { space, channel, postId }`.
2. `Client._ready()` reads the deep link via `JavaScriptBridge.eval("window.daccordDeepLink")`.
3. If no stored credentials exist and the server allows guests, the client auto-requests a guest token and enters guest mode.
4. If credentials exist (returning user), the client connects normally.
5. In either case, the client navigates to the target channel/post after connecting.

**During navigation:**
- Every `AppState.channel_selected` emission triggers a `history.replaceState()` call via `JavaScriptBridge` to update the browser URL without reloading.
- Forum post selection updates the fragment to include the post ID.
- Back/forward browser buttons trigger `popstate` events, which the HTML shell forwards to the Godot engine to navigate accordingly.

**Link types:**

| Link target | Fragment format | Example |
|-------------|----------------|---------|
| Text channel | `#space/channel` | `#community/general` |
| Forum channel (post list) | `#space/forum-channel` | `#community/help-forum` |
| Forum topic (specific post) | `#space/forum-channel/post-id` | `#community/help-forum/1234567890` |
| Voice channel | `#space/voice-channel` | `#community/lounge` (opens channel view; joining voice still requires auth) |

### Guest mode — grayed-out inputs

When the server has `allow_guest_access` enabled and the user is browsing without an account, all interactive inputs are rendered in a **grayed-out disabled state** rather than hidden. This lets visitors see what they *could* do if they had an account, creating a natural upgrade path.

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

**Implementation approach:**
- `AppState.is_guest_mode` drives a global check.
- Interactive components check `AppState.is_guest_mode` and apply a `modulate` alpha (e.g. 0.5) + set `mouse_filter = MOUSE_FILTER_STOP` so clicks are caught.
- A shared `GuestPrompt` utility shows the registration dialog from any component: `GuestPrompt.show_if_guest() -> bool` returns `true` (and shows the dialog) if in guest mode, `false` if authenticated.
- After successful registration/sign-in, `AppState.guest_mode_changed.emit(false)` causes all components to re-enable.

### SEO and server-side rendering

WASM apps are not natively crawlable by search engines — the content is rendered client-side in a canvas element. To make public channels and forum posts indexable, the accordserver (or a reverse proxy) serves **HTML snapshots** for crawler user agents.

**How it works:**

1. The web server detects crawler user agents (Googlebot, Bingbot, etc.) via the `User-Agent` header.
2. Instead of serving the WASM app, it returns a lightweight HTML page with the channel or forum post content rendered as semantic HTML (`<article>`, `<h1>`, `<p>`, `<time>`, etc.).
3. The HTML includes `<meta>` tags for Open Graph and Twitter Card previews (title, description, image) so that links shared on social media display rich previews.
4. A `<link rel="canonical">` points to the clean URL.
5. A `<noscript>` fallback in the main HTML shell provides a link to the server-rendered version for clients without JavaScript/WASM support.

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

**Open Graph previews:** When someone shares a link on social media, the server-rendered HTML includes:

```html
<meta property="og:title" content="How to configure widgets — Community Forum">
<meta property="og:description" content="Step-by-step guide to setting up widgets...">
<meta property="og:type" content="article">
<meta property="og:url" content="https://chat.example.com/#community/help-forum/1234567890">
<meta property="og:site_name" content="Community Server">
<meta property="og:image" content="https://chat.example.com/cdn/space-icon.png">
<meta name="twitter:card" content="summary_large_image">
```

This is implemented **server-side** (in accordserver or as a reverse proxy middleware), not in the Godot client. The client's role is limited to URL routing so that linked pages load the correct content when a human visitor arrives.

### Export output paths

- **Local:** `dist/web/Daccord.html` (from `export_presets.cfg`).
- **CI:** `dist/build/web/index.html` (CI overrides the output name for consistency).

## Implementation Status

### Web export pipeline
- [x] Web export preset exists in `export_presets.cfg`
- [x] Custom HTML shell uses Godot 4.5 `$GODOT_CONFIG` placeholder
- [x] `web-export.sh` script handles full export + JS bundle setup
- [x] `coop_coep.js` service worker for cross-origin isolation
- [x] CI web export job with Chrome headless smoke test
- [x] Release CI bundles web JS dependencies (livekit-client, godot-livekit-web.js, coop_coep.js) into the web release artifact

### Voice & video on web
- [x] `godot-livekit-web.js` wrapper mirrors GDExtension API
- [x] `WebVoiceSession` bridges JS room events to GDScript signals
- [x] Voice on web uses LiveKit JS SDK via `WebVoiceSession`
- [x] Video on web (camera publish, remote track receive)
- [ ] Local video preview on web
- [ ] Screen share on web
- [ ] Per-device audio/video selection on web
- [ ] Deafen suppresses remote audio playback

### Shareable links
- [ ] URL fragment routing in HTML shell (`#space/channel/post-id`)
- [ ] `Client._ready()` reads `window.daccordDeepLink` on web for initial navigation
- [ ] `history.replaceState()` updates browser URL on channel/post navigation
- [ ] Browser back/forward (`popstate`) triggers in-app navigation
- [ ] Forum post links include post ID in fragment

### Guest mode (grayed-out inputs)
- [ ] `POST /auth/guest` server endpoint (accordserver)
- [ ] `AuthApi.guest()` client method
- [ ] `Client.connect_guest()` / `Client.upgrade_guest_connection()`
- [ ] `AppState.guest_mode_changed` signal and `is_guest_mode` state
- [ ] Auto-guest-connect on web when URL contains a target and no credentials
- [ ] Guest token stored in `sessionStorage` on web
- [ ] Guest token silent refresh on expiry
- [ ] Composer grayed out with "Sign in to send a message" placeholder; click shows registration prompt
- [ ] Reaction buttons grayed out; click shows registration prompt
- [ ] Forum "New Post" button grayed out; click shows registration prompt
- [ ] Thread composer grayed out; click shows registration prompt
- [ ] Voice channel join grayed out; click shows registration prompt
- [ ] Context menu actions grayed out; click shows registration prompt
- [ ] DM button grayed out; click shows registration prompt
- [ ] `GuestPrompt` shared utility for registration dialog
- [ ] Persistent "You're browsing as a guest" banner with Sign In / Register buttons
- [ ] Guest connections excluded from Config persistence

### SEO and link previews
- [ ] Server-side HTML snapshots for crawler user agents (accordserver)
- [ ] Open Graph / Twitter Card `<meta>` tags on HTML snapshots
- [ ] `<link rel="canonical">` on server-rendered pages
- [ ] Forum post content rendered as semantic HTML for crawlers
- [ ] `rel="next"` pagination for threaded forum replies
- [ ] `<noscript>` fallback link to server-rendered content in HTML shell

### Known rendering issues
- [ ] Icons not rendering (displays garbled ASCII instead of SVG/theme icons)
- [ ] Initial layout is squashed into the lower half of the screen (requires a window resize to correct)
- [ ] Mic test audio plays back at a higher pitch than expected

## Tasks

### WEB-1: Local video preview unavailable on web
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui, video
- **Notes:** `publish_camera()` returns a `WebVideoStub`; no local video texture is rendered. Would need to attach a `<video>` element via JS and overlay or pipe frames back to Godot.

### WEB-2: Screen share not supported on web
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui, video
- **Notes:** `publish_screen()` returns `null`. Browser `getDisplayMedia()` API is available but needs JS wrapper + GDScript integration.

### WEB-3: Deafen does not suppress remote audio
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** voice
- **Notes:** `set_deafened()` stores the flag but doesn't mute incoming audio. Needs JS-side gain control or `AudioContext` manipulation.

### WEB-4: No per-device selection on web
- **Status:** open
- **Impact:** 1
- **Effort:** 2
- **Tags:** ui, voice, video
- **Notes:** Settings UI device enumeration depends on LiveKit GDExtension. Web could use `navigator.mediaDevices.enumerateDevices()` via `JavaScriptBridge`.

### WEB-5: Icons not rendering on web
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** ui, rendering
- **Notes:** Theme icons (SVGs) display as garbled ASCII characters instead of rendering correctly. Does not affect the desktop client. Likely a font/icon fallback or SVG import issue specific to the web export pipeline.

### WEB-6: Initial layout squashed on load
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** ui, rendering
- **Notes:** On first load, the entire UI appears squashed into the lower half of the screen. Resizing the browser window corrects the layout. Likely a canvas/viewport sizing race condition during initialization — the viewport dimensions may not be correctly reported until after a resize event fires.

### WEB-7: Mic test audio plays back at high pitch
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** voice, audio
- **Notes:** Mic test playback sounds higher-pitched than expected on web. Does not affect the desktop client. Likely a sample rate mismatch between the browser's `AudioContext` and the playback pipeline (e.g., recording at 48 kHz but playing back assuming 44.1 kHz, or vice versa).

### WEB-8: URL fragment routing for shareable links
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** ui, web
- **Notes:** The HTML shell needs to parse `#space/channel/post-id` fragments, pass them to the Godot engine on startup, and update the URL as the user navigates. Browser back/forward should trigger in-app navigation via `popstate` events.

### WEB-9: Guest mode with grayed-out inputs
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** ui, web, auth
- **Notes:** Requires `POST /auth/guest` on the server. Client-side: all interactive inputs render grayed-out (modulate alpha + click intercept) and show a shared registration prompt dialog on click. `GuestPrompt.show_if_guest()` utility to standardize the pattern across components. Blocked on accordserver guest endpoint.

### WEB-10: SEO — server-side HTML snapshots
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** seo, web
- **Notes:** Entirely server-side (accordserver or reverse proxy). Detect crawler user agents and serve semantic HTML with Open Graph meta tags instead of the WASM app. Primary target is forum posts (titles, content, replies). No client-side work needed beyond URL routing (WEB-8).

## Related User Flows

| Flow | Relationship |
|------|-------------|
| [Read Only Mode](read_only_mode.md) | Full specification of guest mode: auth, token lifecycle, UI states, member list, server-side requirements |
| [Forums](forums.md) | Forum channels are the primary SEO target; post titles and threaded replies become indexable web content |
| [URL Protocol](url_protocol.md) | Desktop deep links (`daccord://navigate/...`) complement web URLs (`#space/channel`) for the native client |
| [Server Connection](server_connection.md) | Guest mode is a variant of the server connection flow, skipping credentials |
| [User Onboarding](user_onboarding.md) | Guest-to-authenticated upgrade is an onboarding path; grayed-out inputs guide conversion |
| [Master Server Discovery](master_server_discovery.md) | Discovery panel "Preview" button connects in guest mode for browsing before joining |
