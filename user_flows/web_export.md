# Web Export

## Overview

This flow covers exporting daccord to the web (Godot Web / WASM). The web build produces static files (HTML/JS/WASM/PCK) that can be served from any static web host. Voice and video use the LiveKit JS SDK (`livekit-client`) via a custom JavaScript wrapper (`godot-livekit-web.js`) that mirrors the GDExtension API surface, bridged to GDScript through `WebVoiceSession` and `JavaScriptBridge`.

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

## Signal Flow

```
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
```

## Key Files

| File | Role |
|------|------|
| `web-export.sh` | One-step export script: runs Godot web export, downloads `livekit-client` UMD, copies `godot-livekit-web.js` into `dist/web/`. |
| `export/web/index.html` | Custom HTML shell template. Uses `$GODOT_CONFIG` (Godot 4.5 consolidated placeholder). Loads `livekit-client.umd.min.js` and `godot-livekit-web.js` before the engine. Registers the `coop_coep.js` service worker for cross-origin isolation. |
| `export/web/coop_coep.js` | Service worker that adds `Cross-Origin-Opener-Policy` and `Cross-Origin-Embedder-Policy` headers (required for `SharedArrayBuffer` / WASM threads in Chrome). |
| `export/web/godot-livekit-web.js` | JavaScript wrapper around `livekit-client.js` that mirrors the godot-livekit GDExtension API surface. Exposes `GodotLiveKit.createRoom()` globally. |
| `export_presets.cfg` (preset `Web`) | Web export preset. `export_path="dist/web/Daccord.html"`, `custom_html_shell="res://export/web/index.html"`. Excludes `addons/godot-livekit/*` (GDExtension not used on web). |
| `scripts/autoload/web_voice_session.gd` | `WebVoiceSession` — web-only voice session using `JavaScriptBridge` to call into `godot-livekit-web.js`. Mirrors `LiveKitAdapter` signal/API surface. No-ops on non-web builds. |
| `scripts/autoload/client_voice.gd` | Voice join pipeline: calls REST join, then routes to `LiveKitAdapter` (desktop) or `WebVoiceSession` (web). |
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

### Export output paths

- **Local:** `dist/web/Daccord.html` (from `export_presets.cfg`).
- **CI:** `dist/build/web/index.html` (CI overrides the output name for consistency).

## Implementation Status

- [x] Web export preset exists in `export_presets.cfg`
- [x] Custom HTML shell uses Godot 4.5 `$GODOT_CONFIG` placeholder
- [x] `web-export.sh` script handles full export + JS bundle setup
- [x] `coop_coep.js` service worker for cross-origin isolation
- [x] `godot-livekit-web.js` wrapper mirrors GDExtension API
- [x] `WebVoiceSession` bridges JS room events to GDScript signals
- [x] CI web export job with Chrome headless smoke test
- [x] Release CI bundles web JS dependencies (livekit-client, godot-livekit-web.js, coop_coep.js) into the web release artifact
- [x] Web export hosted build can connect to a server and do text chat
- [x] Voice on web uses LiveKit JS SDK via `WebVoiceSession`
- [x] Video on web (camera publish, remote track receive)
- [ ] Icons not rendering (displays garbled ASCII instead of SVG/theme icons)
- [ ] Initial layout is squashed into the lower half of the screen (requires a window resize to correct)
- [ ] Mic test audio plays back at a higher pitch than expected
- [ ] Local video preview on web
- [ ] Screen share on web
- [ ] Per-device audio/video selection on web
- [ ] Deafen suppresses remote audio playback

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
