# Web Export

Priority: 62
Depends on: None

## Overview

This flow covers exporting daccord to the web (Godot Web / WASM). The web build produces static files (HTML/JS/WASM/PCK) that can be served from any static web host. Voice and video use the LiveKit JS SDK (`livekit-client`) via a custom JavaScript wrapper (`godot-livekit-web.js`) that mirrors the GDExtension API surface, bridged to GDScript through `WebVoiceSession` and `JavaScriptBridge`.

Beyond a functional chat client, the web export serves as a **public-facing front door** for accordserver communities. Each web deployment is tied to a specific accordserver instance via a **preset server** configuration baked into the HTML shell. Visitors who open the URL are instantly connected as anonymous guests -- no server selection, no login prompt, no friction. They see content immediately. Only when they attempt to perform an action (send a message, react, etc.) are they prompted to sign in. Shareable URLs link directly to channels, forums, and forum topics. Server-side HTML snapshots make public content crawlable by search engines, turning forum posts into indexable web pages.

## User Steps

### Export & deploy (developer)

1. Developer runs `./web-export.sh` which:
   - Runs `godot --headless --export-release "Web"` producing output in `dist/build/web/`.
   - Downloads the `livekit-client` UMD bundle into `dist/build/web/`.
   - Copies `godot-livekit-web.js` and `coop_coep.js` into `dist/build/web/`.
2. Developer edits `dist/web/index.html` (the template) to set the preset server configuration (see [Preset servers](#preset-servers) below). This tells the web client which accordserver to auto-connect to.
3. Developer hosts `dist/build/web/` on a static web server. The web export preset has `variant/thread_support=false` (single-threaded WASM), so COOP/COEP headers are **not strictly required**. The bundled `coop_coep.js` service worker is retained for forward compatibility but the HTML shell currently **unregisters** leftover service workers from older builds rather than registering new ones.

### Arriving on the web client (visitor)

4. Visitor opens a URL (e.g. `https://chat.example.com/` or `https://chat.example.com/#community/general`).
5. The web client reads the preset server config from the HTML shell and immediately requests a guest token (`POST /auth/guest`) -- no dialog, no user interaction.
6. The client connects as an anonymous guest and navigates directly to the target channel (from the URL fragment) or the space's default channel.
7. Content loads instantly. The visitor can browse public channels, read messages, scroll history, and view forum posts -- all without creating an account.

### Lazy authentication (action-triggered)

8. When the visitor attempts any write action (send a message, add a reaction, join voice, etc.), the grayed-out input intercepts the click and shows a registration prompt (see [Read Only Mode](read_only_mode.md)).
9. After signing in or registering, the guest connection upgrades to an authenticated one. All inputs re-enable and the visitor can now participate fully.
10. On web, `localStorage` persists the auth token so future visits to the same URL skip the guest flow and connect as the authenticated user directly.

### Text chat (authenticated user)

11. Authenticated user navigates channels and sends/receives messages (same flow as desktop).
12. Users can also add additional servers via "Add Server" if they want to connect to other accordserver instances beyond the preset.

### Voice (web)

13. User clicks a voice channel to join. (If guest, registration prompt appears first.)
14. Browser prompts for microphone permission (first use).
15. `ClientVoice` calls REST `VoiceApi.join()` and receives voice server credentials.
16. `WebVoiceSession` creates a LiveKit room via `JavaScriptBridge.eval("GodotLiveKit.createRoom()")` and calls `connectToRoom(url, token)`.
17. The `livekit-client` JS SDK handles WebRTC transport, ICE negotiation, and media.
18. Voice bar appears; mute/deafen toggles call `setMicrophoneEnabled()` on the local participant.

### Video (web)

19. While in voice, user clicks "Cam" to enable camera.
20. Browser prompts for camera permission (first use).
21. `WebVoiceSession.publish_camera()` calls `setCameraEnabled(true)` on the local participant. Returns a `WebVideoStub` (no local preview on web).
22. Remote video tracks arrive via `trackSubscribed` events and are forwarded through `track_received` signals.

### Shareable links

23. User navigates to a channel or forum post on the web client.
24. The browser URL updates in real time to reflect the current view (e.g. `https://chat.example.com/#community/general`).
25. User copies the URL from the browser address bar and shares it (chat, social media, email, etc.).
26. Recipient clicks the link; the web client loads and navigates directly to that channel or post (auto-guest if not authenticated).

**URL format:** `https://<host>/#<space-slug>/<channel-slug>[/<post-id>]`

| URL | Target |
|-----|--------|
| `https://chat.example.com/#general` | The "general" channel (default space) |
| `https://chat.example.com/#community/announcements` | The "announcements" channel in the "community" space |
| `https://chat.example.com/#community/help-forum` | The "help-forum" forum channel (shows post list) |
| `https://chat.example.com/#community/help-forum/1234567890` | A specific forum post and its thread |

### Guest browsing (auto-guest via preset server)

The web export's default experience **is** guest mode. Visitors arrive and are immediately connected as anonymous guests via the preset server -- there is no empty state, no "Add Server" prompt, and no login wall. All interactive inputs are visible but grayed out; clicking any of them triggers a registration prompt. See [Read Only Mode](read_only_mode.md) for the full specification (grayed-out inputs, registration prompts, forum browsing, upgrade flow, token lifecycle).

### SEO (server-side)

37. A search engine crawler (Googlebot, Bingbot, etc.) or social media link unfurler requests an SEO URL like `https://api.example.com/s/community/help-forum/1234567890`.
38. The accordserver detects the crawler user agent and serves a **static HTML snapshot** with the forum post content as semantic HTML (`<article>`, `<h1>`, `<p>`, `<time>`) plus Open Graph and Twitter Card `<meta>` tags.
39. The search engine indexes the content. The post appears in search results with the title and a content snippet.
40. A human clicks the search result; the SEO endpoint redirects them (via `<meta http-equiv="refresh">`) to the web client at `/#community/help-forum/1234567890`, which loads the WASM app and navigates to the post.
41. When a link is shared on social media (Slack, Discord, Twitter, etc.), the unfurler fetches the SEO URL and displays a rich preview with the OG title, description, and space icon.

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

=== PRESET SERVER & AUTO-GUEST (WEB) ===

browser loads https://chat.example.com/#community/help
    -> index.html <script> parses hash into window.daccordDeepLink
    -> index.html <script> reads window.daccordPresetServer = { base_url, space_slug }
    -> Godot engine starts
    -> Client._ready() creates ClientWebLinks, calls setup()
        -> _read_deep_link(): reads window.location.hash via JavaScriptBridge.eval()
        -> _read_preset_server(): reads window.daccordPresetServer via JavaScriptBridge.eval()
        -> _setup_popstate_listener(): registers popstate JS callback
        -> connects to AppState.channel_selected, thread_opened/closed, channels_updated
    -> [has localStorage auth token] Client.connect_server() (authenticated — skip guest)
    -> [no auth token, preset server exists] auto-guest flow:
        -> POST /auth/guest to preset server base_url
            -> returns { token, expires_at, space_id }
        -> Client.connect_guest(base_url, token, space_id, expires_at)
            -> AccordClient created with guest token + GatewayIntents.guest()
            -> GET /users/@me -> synthetic guest user
            -> GET /spaces/{space_id} -> cache space
            -> WebSocket gateway login (guest intents)
            -> mode = LIVE, AppState.enter_guest_mode(base_url)
            -> _start_guest_refresh_timer()
        -> sessionStorage.setItem("guest_token", token)
    -> [no preset, no auth] empty state with Add Server prompt (desktop-like)
    -> gateway READY populates channel cache -> AppState.channels_updated emits
        -> ClientWebLinks._on_channels_updated() -> _navigate_to_deep_link()
            -> finds space by slug in _space_cache -> AppState.select_space()
            -> finds channel by name in _channel_cache -> AppState.select_channel()
            -> if post_id present: AppState.open_thread(post_id)

=== SHAREABLE LINKS & URL ROUTING ===

user navigates between channels
    -> AppState.channel_selected(channel_id)
    -> ClientWebLinks._on_channel_selected()
        -> looks up channel name + space slug from caches
        -> JavaScriptBridge.eval("history.replaceState(null,'','#community/general')")
        -> browser URL updates without page reload

user opens/closes a forum post
    -> AppState.thread_opened(post_id) / thread_closed
    -> ClientWebLinks appends or removes post_id from URL fragment

user clicks browser back/forward
    -> popstate event fires -> JS parses hash -> calls _daccordPopStateCb(json)
    -> ClientWebLinks._on_popstate() -> _navigate_by_slug()
        -> resolves space/channel from caches -> AppState.select_space/channel/open_thread

=== SEO (SERVER-SIDE) ===

accordserver routes under /s/ (routes/seo.rs):
    GET /s/{space_slug}                              -> space index (channel list)
    GET /s/{space_slug}/{channel_name}               -> channel snapshot (recent messages)
    GET /s/{space_slug}/{channel_name}/{post_id}     -> post snapshot (post + paginated replies)

crawler or unfurler requests /s/community/help-forum/1234567890
    -> seo::post_snapshot() handler
    -> checks space.public == true (404 if private)
    -> looks up space by slug, channel by name, message by ID
    -> detects crawler User-Agent (Googlebot, Bingbot, facebookexternalhit, etc.)
        -> [crawler] serves semantic HTML snapshot:
            <html>
              <head>
                <meta property="og:title" content="Post Title — Community Forum">
                <meta property="og:description" content="First 200 chars of post...">
                <meta property="og:type" content="article">
                <meta property="og:image" content="/cdn/icons/{space-icon}">
                <meta name="twitter:card" content="summary_large_image">
                <link rel="canonical" href="/s/community/help-forum/1234567890">
                <link rel="next" href="/s/community/help-forum/1234567890?page=2">
              </head>
              <body>
                <article class="post"><h1>Post Title</h1><p>Content...</p></article>
                <section class="replies">
                  <article class="reply">...</article> (25 per page)
                  <nav class="pagination">Page 1 of 3 <a rel="next">Next</a></nav>
                </section>
              </body>
            </html>
        -> [human] redirects via <meta http-equiv="refresh"> to /#community/help-forum/1234567890
    -> search engine indexes title, content, replies
    -> human clicks search result -> redirect -> WASM app loads -> navigates to post
```

## Key Files

| File | Role |
|------|------|
| `web-export.sh` | One-step export script: runs Godot web export, downloads `livekit-client` UMD, copies `godot-livekit-web.js` into `dist/web/`. |
| `dist/web/index.html` | Custom HTML shell template. Uses `$GODOT_CONFIG` (Godot 4.5 consolidated placeholder). Loads `livekit-client.umd.min.js` and `godot-livekit-web.js` before the engine. **Unregisters** leftover COOP/COEP service workers from older builds. Parses URL fragment on load for deep link routing. Contains the `window.daccordPresetServer` configuration block for auto-guest. |
| `dist/web/coop_coep.js` | Service worker that adds `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers. Retained in the build for forward compatibility, but the HTML shell currently unregisters it. Only needed if thread support is re-enabled (`variant/thread_support=true`). |
| `dist/web/godot-livekit-web.js` | JavaScript wrapper around `livekit-client.js` that mirrors the godot-livekit GDExtension API surface. Exposes `GodotLiveKit.createRoom()` globally. |
| `export_presets.cfg` (preset.5 `Web`) | Web export preset. `export_path="dist/build/web/Daccord.html"`, `custom_html_shell="res://dist/web/index.html"`, `variant/thread_support=false`. Excludes `addons/godot-livekit/*`, `addons/godot_sandbox/*`, `addons/sentry/*`, `scripts/sentry_scene_tree.gd`. Sentry injection disabled. |
| `scripts/autoload/web_voice_session.gd` | `WebVoiceSession` — web-only voice session using `JavaScriptBridge` to call into `godot-livekit-web.js`. Mirrors `LiveKitAdapter` signal/API surface. No-ops on non-web builds. |
| `scripts/autoload/client_voice.gd` | Voice join pipeline: calls REST join, then routes to `LiveKitAdapter` (desktop) or `WebVoiceSession` (web). |
| `scripts/autoload/client.gd` | Server connections, URL fragment navigation on web. Guest mode: see [Read Only Mode](read_only_mode.md). |
| `accordserver/src/routes/seo.rs` | SEO HTML snapshot endpoints (`/s/{space}/{channel}[/{post_id}]`). Detects crawler user agents, serves semantic HTML with OG/Twitter meta tags, `<link rel="canonical">`, and `rel="next"` pagination. Redirects human visitors to the fragment-based web client. |
| `scripts/autoload/client_web_links.gd` | `ClientWebLinks` — web-only URL fragment routing. Parses deep links on startup, updates browser URL via `history.replaceState()` on navigation, handles `popstate` for back/forward. |
| `scenes/user/app_settings.gd` | Voice & Video settings. Mic test monitor routes through `WebMicAudio` on web (bypasses Godot audio bus to avoid sample-rate mismatch). |
| `scenes/user/web_mic_audio.gd` | `WebMicAudio` — Web Audio API bridge for mic test. Provides `start_analyser()`, `get_rms()`, `start_monitor()`, `stop_monitor()`, `set_monitor_gate()` via `JavaScriptBridge`. |
| `.github/workflows/ci.yml` (`web-export` job) | CI web export: builds to `dist/build/web/`, validates artifacts, copies `coop_coep.js`, runs Chrome headless smoke test. |
| `.github/workflows/release.yml` (`web` matrix entry) | Release build: exports web, downloads `livekit-client` UMD bundle, copies `godot-livekit-web.js` and `coop_coep.js`, packages everything into `daccord-web.zip` for the GitHub release. |

## Implementation Details

### HTML shell template (Godot 4.5)

The custom HTML shell at `dist/web/index.html` uses Godot 4.5's `$GODOT_CONFIG` placeholder — a single JSON object that Godot substitutes at export time containing `canvasResizePolicy`, `experimentalVK`, `focusCanvas`, `executable`, `gdextensionLibs`, etc. The template assigns the `canvas` element after substitution:

```js
const GODOT_CONFIG = $GODOT_CONFIG;
GODOT_CONFIG.canvas = document.getElementById("canvas");
```

Other valid Godot 4.5 placeholders used: `$GODOT_PROJECT_NAME`, `$GODOT_HEAD_INCLUDE`, `$GODOT_URL`, `$GODOT_SPLASH`.

### Preset servers

Each web deployment is configured with a **preset server** -- the accordserver instance that visitors connect to automatically. This is set in the HTML shell (`dist/web/index.html`) as a `window.daccordPresetServer` JavaScript object:

```html
<script>
  window.daccordPresetServer = {
    base_url: "https://api.example.com",
    space_slug: "community"
  };
</script>
```

**How it works:**

1. The developer sets `window.daccordPresetServer` in `dist/web/index.html` after export. This is the only manual configuration step.
2. On startup, `ClientWebLinks._read_preset_server()` reads this object via `JavaScriptBridge.eval()`.
3. If the visitor has no stored auth token in `localStorage`, the client automatically requests a guest token from the preset server (`POST /auth/guest`).
4. The guest connection is established silently -- no dialogs, no prompts. The visitor sees content immediately.
5. If the visitor has a stored auth token (from a previous sign-in), the client connects as an authenticated user instead, skipping the guest flow entirely.

**Preset vs. user-added servers:** The preset server is the default entry point for the web deployment. Users can still add additional servers via "Add Server" if they want to connect to other accordserver instances. The preset server is not persisted to Config (it's read from the HTML shell on every page load) and cannot be removed by the user.

**Same-origin shortcut:** If `base_url` is omitted from the preset config, the client defaults to `window.location.origin` -- useful when the web client is served from the same domain as the accordserver (e.g. behind a reverse proxy).

**Auto-guest connection priority:**

| State | Behavior |
|-------|----------|
| `localStorage` has auth token for preset server | Connect as authenticated user (skip guest) |
| No auth token, preset server configured | Auto-guest: `POST /auth/guest` silently |
| No auth token, no preset server | Empty state with "Add Server" prompt (desktop-like) |
| URL has `?token=` query param | Use provided token (invite link flow) |

### Cross-origin isolation

Chrome requires `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp` headers for `SharedArrayBuffer` (used by WASM threads). The `coop_coep.js` service worker can intercept fetch events and add these headers.

**Current state:** The web export preset has `variant/thread_support=false`, so the WASM runs single-threaded and `SharedArrayBuffer` is not needed. The HTML shell (line 160-167) **unregisters** any leftover service workers from older builds rather than registering new ones. The `coop_coep.js` file is retained in the build output for forward compatibility, and the CI smoke test still injects headers server-side. If thread support is re-enabled in the future, the HTML shell must be updated to register the service worker again.

The CI web export job (`ci.yml` lines 687-718) runs a Python HTTP server that injects COOP/COEP headers server-side for the Chrome headless smoke test, regardless of the service worker state.

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
- **Deafen mutes audio elements:** `set_deafened()` calls `r.setDeafened()` in `godot-livekit-web.js`, which sets `.muted` on all tracked `<audio>` elements.
- **Connect timeout:** 15-second timer; emits `FAILED` state if room doesn't connect.

### Mic test monitor on web

The Voice & Video settings page includes a mic test with a "Monitor output" checkbox that plays the user's microphone back through their speakers. On desktop, this works by unmuting the Godot `MicTest` audio bus. On web, Godot's `AudioStreamMicrophone` playback has a sample-rate mismatch with the browser's `AudioContext`, producing squeaky/high-pitched audio.

**Web-specific approach:** The Godot audio bus stays permanently muted on web. Instead, `app_settings.gd` uses `JavaScriptBridge` to create a Web Audio API loopback:

1. `_web_start_mic_monitor()` calls `navigator.mediaDevices.getUserMedia({ audio: true })` to get a mic stream.
2. The stream is connected through a `GainNode` to `AudioContext.destination` for direct browser-native playback.
3. `_web_set_mic_monitor_gate(open)` sets the gain node's value to `1.0` or `0.0`, implementing the same threshold-based gating as the desktop bus mute.
4. `_web_stop_mic_monitor()` disconnects all nodes, stops the stream tracks, and closes the `AudioContext`.

The level meter (progress bar) still uses Godot's `AudioEffectCapture` on both platforms — only the audible monitor playback is routed differently. The JS audio context and mic stream are stored on `window._daccordMicMonitor` and cleaned up when the test stops or the settings panel exits.

### Shareable URLs and deep link routing

The web export uses URL fragment routing so that every view has a shareable URL. The HTML shell (`dist/web/index.html`) parses the URL fragment on load and passes it to the Godot engine via `JavaScriptBridge`.

**URL format:** `https://<host>/#<space-slug>/<channel-slug>[/<post-id>]`

**On page load:**
1. A `<script>` block in `index.html` parses `window.location.hash` and stores the result in `window.daccordDeepLink = { space, channel, postId }` before the Godot engine starts.
2. `Client._ready()` creates a `ClientWebLinks` instance and calls `setup()`. On non-web builds, `setup()` is a no-op.
3. `ClientWebLinks._read_deep_link()` reads the hash fragment via `JavaScriptBridge.eval()` and stores the parsed space slug, channel name, and post ID.
4. `ClientWebLinks._read_preset_server()` reads `window.daccordPresetServer` and stores the preset server config.
5. `ClientWebLinks._setup_popstate_listener()` creates a GDScript callback via `JavaScriptBridge.create_callback()`, assigns it to `window._daccordPopStateCb`, and registers a `popstate` event listener that parses the new hash and invokes the callback.
6. The client checks for stored auth in `localStorage`. If found, connects as authenticated user. If not, auto-connects as guest via the preset server (see [Preset servers](#preset-servers)). If no preset server is configured, shows the empty state.
7. When `AppState.channels_updated` fires (after gateway READY populates the channel cache), `ClientWebLinks._on_channels_updated()` calls `_navigate_to_deep_link()`, which resolves the space slug and channel name to IDs via the caches and navigates using `AppState.select_space()`, `select_channel()`, and optionally `open_thread()`.

**During navigation:**
- `ClientWebLinks` listens to `AppState.channel_selected`, `thread_opened`, and `thread_closed`. Each handler calls `_update_url_for_channel()`, which looks up the channel name and space slug from `_channel_cache` / `_space_cache` and calls `history.replaceState()` via `JavaScriptBridge.eval()` to update the browser URL without reloading.
- Thread/forum post navigation appends or removes the post ID from the fragment (e.g. `#community/help-forum` ↔ `#community/help-forum/1234567890`).
- Browser back/forward buttons fire `popstate` events, which the JS listener parses and forwards to `ClientWebLinks._on_popstate()`. This calls `_navigate_by_slug()`, which resolves the fragment components to IDs and navigates in-app.

**Link types:**

| Link target | Fragment format | Example |
|-------------|----------------|---------|
| Text channel | `#space/channel` | `#community/general` |
| Forum channel (post list) | `#space/forum-channel` | `#community/help-forum` |
| Forum topic (specific post) | `#space/forum-channel/post-id` | `#community/help-forum/1234567890` |
| Voice channel | `#space/voice-channel` | `#community/lounge` (opens channel view; joining voice still requires auth) |

### SEO and server-side rendering

WASM apps are not natively crawlable by search engines — the content is rendered client-side in a canvas element. To make public channels and forum posts indexable, the accordserver serves **HTML snapshots** at path-based SEO URLs under `/s/`.

**SEO URL scheme:** `https://<accordserver>/s/<space-slug>/<channel-name>[/<post-id>][?page=N]`

Since URL fragments (`#`) are never sent to the server, the SEO endpoints use a separate path-based namespace (`/s/`) that mirrors the fragment structure. The `<link rel="canonical">` on each page points back to the `/s/` URL.

**How it works:**

The accordserver exposes three endpoints in `routes/seo.rs`, mounted under `/s/`:

| Route | Purpose |
|-------|---------|
| `GET /s/{space_slug}` | Space index — lists channels as links |
| `GET /s/{space_slug}/{channel_name}` | Channel snapshot — up to 50 recent messages as semantic HTML |
| `GET /s/{space_slug}/{channel_name}/{post_id}?page=N` | Post snapshot — forum post with paginated thread replies (25 per page) |

1. Each handler first checks `space.public == true`; private spaces return 404.
2. The handler checks the `User-Agent` header against a list of known crawlers (Googlebot, Bingbot, facebookexternalhit, Twitterbot, Discordbot, etc.).
3. **Crawlers** receive semantic HTML with `<article>`, `<h1>`, `<p>`, `<time>` elements, plus Open Graph and Twitter Card `<meta>` tags, and `<link rel="canonical">`.
4. **Human visitors** receive a `<meta http-equiv="refresh">` redirect to the fragment-based web client URL (e.g. `/s/community/general` redirects to `/#community/general`).
5. Post pages include `<link rel="prev">` and `<link rel="next">` for paginated thread replies.
6. A `<noscript>` block in the HTML shell (`dist/web/index.html`) links to `/s/` for clients without JavaScript/WASM support.

**What gets indexed (forum channels are the primary target):**
- Forum post titles (first line of content) and body content
- Thread replies (paginated at 25 per page, with `rel="next"` links)
- Author display names and timestamps
- Channel names and space descriptions

**What does NOT get indexed:**
- Spaces with `public: false`
- DM content (never public)
- Voice channel state
- Member list details beyond public display names

**Open Graph previews:** When someone shares an SEO link on social media, the server-rendered HTML includes:

```html
<meta property="og:title" content="How to configure widgets — Community Forum">
<meta property="og:description" content="Step-by-step guide to setting up widgets...">
<meta property="og:type" content="article">
<meta property="og:url" content="/s/community/help-forum/1234567890">
<meta property="og:site_name" content="Community Server">
<meta property="og:image" content="/cdn/icons/space-icon.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="How to configure widgets — Community Forum">
<meta name="twitter:description" content="Step-by-step guide to setting up widgets...">
```

This is implemented **server-side** in `accordserver/src/routes/seo.rs`, not in the Godot client. The client's role is limited to URL fragment routing so that linked pages load the correct content when a human visitor arrives via redirect.

### Export output paths

- **Local / CI:** `dist/build/web/Daccord.html` (from `export_presets.cfg`).
- The `web-export.sh` script also copies JS dependencies (livekit-client, godot-livekit-web.js, coop_coep.js) into `dist/build/web/`.

### Platform guards in the codebase

The following files contain `OS.get_name() == "Web"` or `OS.has_feature("web")` guards to branch behavior on web:

| File | Guard | Purpose |
|------|-------|---------|
| `client.gd` (line 192) | `OS.get_name() == "Web"` | Loads `WebVoiceSession` instead of `LiveKitAdapter` |
| `client_web_links.gd` (line 31) | `OS.get_name() == "Web"` | All web link methods are no-ops on non-web |
| `web_voice_session.gd` (line 57) | `OS.get_name() == "Web"` | All voice methods are no-ops on non-web |
| `web_mic_audio.gd` (lines 11, 32, 47, 63, 81, 95) | `OS.get_name() != "Web"` | Early-returns on non-web |
| `app_settings.gd` (lines 101, 155, 252, 301, 313, 377, 403) | `OS.get_name() == "Web"` | Hides device selection, routes mic test to WebMicAudio |
| `voice_bar.gd` (line 57) | `OS.get_name() == "Web"` | Hides screen share button on web |
| `screen_picker_dialog.gd` (line 11) | `OS.get_name() == "Web"` | Blocks screen picker with error on web |
| `plugin_management_dialog.gd` (line 170) | `OS.get_name() == "Web"` | Disables plugin upload on web |
| `main_window.gd` (line 209) | `OS.has_feature("web")` | Skips window manipulation on web |

**Missing guard:** `client.gd` lines 242-266 initialize `ClientTestApi` and `ClientMcp` (both use `TCPServer`) without a web platform check. `TCPServer` is unavailable on HTML5 exports. If developer mode is enabled, this will error on web. See WEB-10.

## Implementation Status

### Web export pipeline
- [x] Web export preset exists in `export_presets.cfg` (preset.5, single-threaded WASM)
- [x] Custom HTML shell uses Godot 4.5 `$GODOT_CONFIG` placeholder
- [x] `web-export.sh` script handles full export + JS bundle setup + `serve` subcommand
- [x] `coop_coep.js` service worker exists (retained for forward compat; HTML shell currently unregisters it)
- [x] CI web export job with Chrome headless smoke test
- [x] Release CI bundles web JS dependencies (livekit-client, godot-livekit-web.js, coop_coep.js) into the web release artifact
- [ ] TCPServer-based subsystems (Test API, MCP) lack web platform guard — will error if developer mode is enabled on web (see WEB-10)

### Voice & video on web
- [x] `godot-livekit-web.js` wrapper mirrors GDExtension API
- [x] `WebVoiceSession` bridges JS room events to GDScript signals
- [x] Voice on web uses LiveKit JS SDK via `WebVoiceSession`
- [x] Video on web (camera publish, remote track receive)
- [ ] Local video preview on web
- [ ] Screen share on web
- [ ] Per-device audio/video selection on web
- [x] Deafen suppresses remote audio playback (`godot-livekit-web.js` `setDeafened()` mutes all audio elements)

### Shareable links
- [x] URL fragment routing in HTML shell (`#space/channel/post-id`)
- [x] `Client._ready()` reads `window.daccordDeepLink` on web for initial navigation
- [x] `history.replaceState()` updates browser URL on channel/post navigation
- [x] Browser back/forward (`popstate`) triggers in-app navigation
- [x] Forum post links include post ID in fragment

### Preset servers & auto-guest
- [x] `window.daccordPresetServer` config block in HTML shell (commented template in `dist/web/index.html`)
- [x] `ClientWebLinks._read_preset_server()` reads preset config via JavaScriptBridge (`client_web_links.gd` lines 82-100)
- [x] Auto-guest: client requests `POST /auth/guest` from preset server on startup when no auth token exists (`client_web_links.gd` lines 104-131)
- [x] `localStorage` auth token check: skip guest flow if authenticated session exists (`try_auto_connect()` lines 49-75)
- [x] Same-origin fallback: default `base_url` to `window.location.origin` when omitted (`client_web_links.gd` line 87)
- [x] Guest-to-auth upgrade persists token to `localStorage` via `_on_guest_mode_changed` (line 343)
- [x] Preset server is non-removable (read from HTML shell on every load, never persisted to Config)

### Guest mode (read only)
See [Read Only Mode — Implementation Status](read_only_mode.md#implementation-status) for all guest mode items.

### SEO and link previews
- [x] Server-side HTML snapshots for crawler user agents (accordserver)
- [x] Open Graph / Twitter Card `<meta>` tags on HTML snapshots
- [x] `<link rel="canonical">` on server-rendered pages
- [x] Forum post content rendered as semantic HTML for crawlers
- [x] `rel="next"` pagination for threaded forum replies
- [x] `<noscript>` fallback link to server-rendered content in HTML shell

### Mic test monitor on web
- [x] `WebMicAudio` helper class (`scenes/user/web_mic_audio.gd`) — Web Audio API bridge: `start_analyser()`, `get_rms()`, `start_monitor()`, `stop_monitor()`, `set_monitor_gate()`
- [x] `app_settings.gd` creates `_web_mic: RefCounted = WebMicAudio.new()` and routes mic test through it on web
- [x] RMS level meter uses `AnalyserNode` (unaffected by sample-rate issues)
- [x] Monitor playback uses `GainNode` → `AudioContext.destination` (bypasses Godot audio bus)

### Known rendering issues
- [x] Icons not rendering (three SVGs used `stroke="currentColor"` which Godot's SVG rasterizer can't resolve; replaced with explicit `#72767d` hex color)
- [x] Initial layout is squashed into the lower half of the screen (no longer reproduces)
- [x] Mic test audio plays back at correct pitch (Web Audio API loopback via `WebMicAudio`)

### Known breakage (web build currently broken)
- [ ] **Web export fails or crashes at runtime** — exact failure mode needs diagnosis. Potential causes:
  - TCPServer initialization on web when developer mode is enabled (see WEB-10)
  - Service worker unregistration means older cached service workers are removed but no new one is registered — this is intentional since thread support is disabled, but may interact unexpectedly with browser caching
  - `variant/thread_support=false` means single-threaded WASM — some Godot features may behave differently or be unavailable
  - Voice debug logging uses `FileAccess` / `DirAccess` (`client_voice.gd` lines 502-530) which is restricted on web — silently fails but may cause unexpected behavior if debug logging is enabled

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
- **Status:** fixed
- **Impact:** 2
- **Effort:** 2
- **Tags:** voice
- **Notes:** `set_deafened()` now calls `r.setDeafened()` on the JS side (`web_voice_session.gd` line 139). `godot-livekit-web.js` implements `setDeafened()` (line 318) by setting `audioElements[sid].muted = isDeafened` on all tracked audio elements.

### WEB-4: No per-device selection on web
- **Status:** open
- **Impact:** 1
- **Effort:** 2
- **Tags:** ui, voice, video
- **Notes:** Settings UI device enumeration depends on LiveKit GDExtension. Web could use `navigator.mediaDevices.enumerateDevices()` via `JavaScriptBridge`.

### WEB-5: Icons not rendering on web
- **Status:** fixed
- **Impact:** 3
- **Effort:** 2
- **Tags:** ui, rendering
- **Notes:** Three SVGs (`bell.svg`, `lock.svg`, `update.svg`) used `stroke="currentColor"` and/or `fill="currentColor"` — a CSS value that Godot's SVG rasterizer cannot resolve, causing garbled output on web. Fixed by replacing `currentColor` with an explicit hex color (`#72767d`), matching the convention used by all other theme icons. Icons are tinted at runtime via `modulate`, so the source color doesn't matter.

### WEB-6: Initial layout squashed on load
- **Status:** fixed
- **Impact:** 3
- **Effort:** 2
- **Tags:** ui, rendering
- **Notes:** On first load, the entire UI appeared squashed into the lower half of the screen. Resizing the browser window corrected the layout. No longer reproduces.

### WEB-7: Mic test audio plays back at high pitch
- **Status:** fixed
- **Impact:** 2
- **Effort:** 2
- **Tags:** voice, audio
- **Notes:** Mic test playback sounded higher-pitched than expected on web due to a sample-rate mismatch between the browser's AudioContext and Godot's audio pipeline. Fixed by keeping the Godot audio bus permanently muted on web and routing monitor playback through the Web Audio API directly (`getUserMedia` → `GainNode` → `AudioContext.destination`). The level meter still uses Godot's `AudioEffectCapture` (unaffected by the rate mismatch). Desktop path is unchanged.

### WEB-8: URL fragment routing for shareable links
- **Status:** fixed
- **Impact:** 4
- **Effort:** 3
- **Tags:** ui, web
- **Notes:** The HTML shell parses `#space/channel/post-id` fragments and stores them in `window.daccordDeepLink`. `ClientWebLinks` reads this on startup and navigates to the target after channels load. `history.replaceState()` updates the URL on every channel/thread navigation. Browser back/forward triggers in-app navigation via a `popstate` callback.

### WEB-9: SEO — server-side HTML snapshots
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** seo, web
- **Notes:** Implemented in `accordserver/src/routes/seo.rs`. Three endpoints under `/s/`: space index, channel snapshot, and post snapshot with paginated thread replies. Detects crawler user agents and serves semantic HTML with Open Graph/Twitter Card meta tags, `<link rel="canonical">`, and `rel="next"` pagination. Human visitors are redirected to the fragment-based web client URL. Only public spaces are served. A `<noscript>` fallback was added to the HTML shell (`dist/web/index.html`).

### WEB-10: TCPServer (Test API / MCP) crashes on web
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** crash, web
- **Notes:** `client.gd` lines 242-266 initialize `ClientTestApi` and `ClientMcp` using `TCPServer.new()` (`client_test_api.gd` line 50, `client_mcp.gd` line 67) without checking `OS.get_name() == "Web"`. `TCPServer` is unavailable on HTML5 exports. If developer mode is enabled in Config, the web build will error on startup. **Fix:** Add `and OS.get_name() != "Web"` guard to lines 245 and 258 in `client.gd`.

### WEB-11: Voice debug logging uses FileAccess on web
- **Status:** open
- **Impact:** 1
- **Effort:** 1
- **Tags:** voice, web
- **Notes:** `client_voice.gd` lines 502-530 use `FileAccess` and `DirAccess` for voice debug logging to `user://voice_debug.log`. File I/O to `user://` is restricted on web. If `debug_voice_logs` is enabled (via Config), `FileAccess.open()` will silently fail and logging will be lost. Low impact since debug logging is opt-in, but an explicit web guard would be cleaner.

### WEB-12: Web build is currently broken
- **Status:** open
- **Impact:** 5
- **Effort:** 3
- **Tags:** crash, web, blocking
- **Notes:** The web version is currently non-functional. Root cause needs diagnosis — could be export template incompatibility, runtime error, or configuration issue. Recommended approach: (1) run `./web-export.sh` locally and check for export errors, (2) run `./web-export.sh serve` and open in Chrome DevTools to capture console errors, (3) check the CI `web-export` job logs for the most recent run.

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Web build is broken (WEB-12) | High | Root cause unknown — needs diagnosis via local export + browser DevTools |
| TCPServer on web crashes (WEB-10) | High | `client.gd` lines 245/258 lack web guard; `TCPServer` unavailable on HTML5 |
| Service worker unregistered but retained in build | Medium | HTML shell (line 160) unregisters workers; `coop_coep.js` shipped but unused. If thread support is re-enabled, registration must be restored |
| No local video preview (WEB-1) | Medium | `publish_camera()` returns stub; no `<video>` overlay integration |
| No screen sharing (WEB-2) | Medium | `publish_screen()` returns null; `getDisplayMedia()` available but unwired |
| No per-device selection (WEB-4) | Low | Settings UI hidden on web; `enumerateDevices()` available but unused |
| Voice debug FileAccess on web (WEB-11) | Low | `FileAccess.open()` silently fails on web; debug logs lost if enabled |

## Related User Flows

| Flow | Relationship |
|------|-------------|
| [Read Only Mode](read_only_mode.md) | Full specification of guest mode: auth, token lifecycle, UI states, member list, server-side requirements |
| [Forums](forums.md) | Forum channels are the primary SEO target; post titles and threaded replies become indexable web content |
| [URL Protocol](url_protocol.md) | Desktop deep links (`daccord://navigate/...`) complement web URLs (`#space/channel`) for the native client |
| [Server Connection](server_connection.md) | Guest mode is a variant of the server connection flow, skipping credentials |
| [User Onboarding](user_onboarding.md) | Guest-to-authenticated upgrade is an onboarding path; grayed-out inputs guide conversion |
| [Master Server Discovery](master_server_discovery.md) | Discovery panel "Preview" button connects in guest mode for browsing before joining |
