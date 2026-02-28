# Web Export

## Overview

This flow covers exporting daccord to the web (Godot Web / WASM) and the runtime differences that impact voice and video. Today, daccord’s voice/video pipeline depends on the LiveKit GDExtension (`AccordVoiceSession`, device enumeration, track creation), which is unavailable in web exports; a web build needs a separate “voice session” backend implemented via browser Web APIs (WebRTC + `getUserMedia`) instead.

## User Steps

### Export & deploy (developer)

1. Developer adds a Web export preset (not present in `export_presets.cfg` today) and exports the project to static files (HTML/JS/WASM/PCK).
2. Developer hosts the exported folder on a static web server (local dev server or a CDN-backed host).
3. User opens the web URL in a browser; daccord boots into the same empty-state experience as desktop when no servers are configured.

### Text chat (user)

4. User adds a server via “Add Server” and connects (same flow as desktop).
5. User navigates channels and sends/receives messages (same flow as desktop).

### Voice (basic, web target behavior)

6. User clicks a voice channel to join.
7. Browser prompts for microphone permission (first use).
8. Client joins voice via REST (`VoiceApi.join`) and receives `AccordVoiceServerUpdate` credentials.
9. Client establishes a WebRTC connection using browser APIs:
   - Create `RTCPeerConnection`
   - Capture mic audio via `navigator.mediaDevices.getUserMedia({audio: ...})`
   - Add the audio track to the peer connection
10. Client sends SDP offer/answer and ICE candidates to the server using the existing gateway `VOICE_SIGNAL` mechanism.
11. Voice bar appears; mute/deafen toggles update the server voice state and local WebRTC track state.

### Video (basic, web target behavior)

12. While in voice, user clicks “Cam” to enable camera.
13. Browser prompts for camera permission (first use).
14. Client captures camera video via `getUserMedia({video: ...})`, adds a video track to the peer connection, and renegotiates through `VOICE_SIGNAL`.
15. Local self-video tile appears; remote video tiles render when remote tracks are received.

## Signal Flow

```
voice_channel_item.gd            AppState                 Client / ClientVoice
     |                              |                              |
     |-- channel_pressed(id) ------>|                              |
     |                              |-- join_voice_channel(id) --->|
     |                              |                              |-- VoiceApi.join(id)
     |                              |                              |-- _validate_backend_info()
     |                              |                              |
     |                              |-- (Desktop) _voice_session.connect_custom_sfu()
     |                              |-- (Web)     WebVoiceSession.connect_custom_sfu()
     |                              |                              |
     |<-- voice_joined(id) ---------|                              |
     |   (show voice bar)           |                              |
     |                              |                              |
gateway voice.signal event          |                              |
     |-- ClientGatewayEvents.on_voice_signal(data) --------------->|
     |                              |                              |-- (Desktop) _voice_session.handle_voice_signal()
     |                              |                              |-- (Web)     WebVoiceSession.handle_voice_signal()
```

## Key Files

| File | Role |
|------|------|
| `export_presets.cfg:1` | Export presets. No Web preset is defined today (only Linux/Windows/macOS/ARM). |
| `.github/workflows/release.yml:209` | CI exports release presets via `godot --headless --export-release`; no web artifact is built. |
| `scripts/autoload/client.gd:129` | Voice session wiring. Loads `LiveKit` singleton and instantiates `AccordVoiceSession` if available (lines 162-205). |
| `scripts/autoload/client_voice.gd:26` | Voice join pipeline: calls REST join, validates backend info, then `_connect_voice_backend()` (lines 26-115). |
| `scripts/autoload/client_voice.gd:120` | Backend connect currently no-ops if `_voice_session` is null (lines 120-123). |
| `scripts/autoload/client_voice.gd:227` | Video/screen-share toggles require `_accord_stream` for camera/screen tracks; errors if unavailable (lines 227-285). |
| `scripts/autoload/client_gateway_events.gd:89` | Gateway voice event handling and forwarding of `voice.signal` to `_voice_session` (lines 89-170). |
| `addons/accordkit/gateway/gateway_socket.gd:449` | `send_voice_signal()` sends `VOICE_SIGNAL` op with `{type, payload}` for signaling. |
| `scenes/sidebar/screen_picker_dialog.gd:5` | Screen/window picker depends on `LiveKit.get_screens()` / `get_windows()` (web builds need a different UI or no screen share). |
| `scenes/user/user_settings.gd:190` | “Voice & Video” settings page enumerates devices via LiveKit when available (lines 190+). |

## Implementation Details

### Export preset & hosting (not implemented)

- `export_presets.cfg` has no Web preset; adding one is the first step to making a browser build repeatable.
- Release CI (`.github/workflows/release.yml` line 210) exports only presets in the matrix; web export would need a new matrix entry and packaging steps.

### Runtime capability detection (partially implemented)

- `Client._ready()` checks for the LiveKit singleton (line 162) and the `AccordVoiceSession` class (line 164). If missing, it warns “voice disabled” (lines 202-205).
- `ClientVoice.toggle_video()` and `start_screen_share()` hard-fail when `_accord_stream` is null (client_voice.gd lines 235-237, 272-274).

### Voice join behavior when the voice session is missing (implemented but incorrect for web)

- `ClientVoice.join_voice_channel()` always calls REST join and then `_connect_voice_backend()` (client_voice.gd lines 46-103).
- `_connect_voice_backend()` returns early if `_voice_session` is null (lines 120-123).
- Despite having no active media session, `join_voice_channel()` still calls `AppState.join_voice()` (line 113) which shows the voice UI as “connected”.

### Web voice/video session (not implemented)

Target shape for a web build is a second voice session implementation that matches the parts of `AccordVoiceSession` daccord depends on:

- `connect_custom_sfu(sfu_endpoint, ice_config, mic_id)` equivalent (but backed by `RTCPeerConnection`)
- `disconnect_voice()`
- `set_muted()` / `set_deafened()` (mute maps to track enabled/disabled; deafen maps to output gain/mix)
- Outgoing signaling callback compatible with `ClientVoice.on_signal_outgoing()` (client_voice.gd line 401)
- Incoming signaling handler compatible with `ClientGatewayEvents.on_voice_signal()` (client_gateway_events.gd lines 163-170)

The web implementation would use browser APIs via `JavaScriptBridge` and would likely skip advanced features (screen/window lists, per-device selection) initially.

## Implementation Status

- [ ] Web export preset exists and produces a working browser build
- [ ] Web export hosted build can connect to a server and do text chat end-to-end
- [ ] Voice on web uses browser WebRTC APIs (mic) instead of LiveKit
- [ ] Video on web uses browser WebRTC APIs (camera) instead of LiveKit
- [ ] Screen share on web (optional; can be deferred)
- [x] Voice signaling transport exists via gateway `VOICE_SIGNAL` (`send_voice_signal`, `on_voice_signal`)
- [x] UI state/signals for voice + video exist in `AppState` (voice_* / video_enabled_changed)

## Tasks

### WEB-1: No Web export preset
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** ci
- **Notes:** Add a Web preset to `export_presets.cfg` and (optionally) CI packaging.

### WEB-2: Voice “connects” in UI even when `_voice_session` is missing
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** ci, ui, voice
- **Notes:** `_connect_voice_backend()` returns early (client_voice.gd lines 120-123) but `AppState.join_voice()` still fires (line 113). Web builds need to block join or provide a web voice session.

### WEB-3: Voice/video depend on LiveKit APIs
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** api, config, ui, video, voice
- **Notes:** Camera/screen tracks hard-fail when `_accord_stream` is null (client_voice.gd lines 235-237, 272-274); settings UI assumes LiveKit for full device enumeration (user_settings.gd line 192).

### WEB-4: `voice.signal` forwarding only targets `_voice_session`
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** gateway, voice
- **Notes:** `ClientGatewayEvents.on_voice_signal()` forwards to meta `_voice_session` only (client_gateway_events.gd lines 165-170). A web session needs the same hook.

### WEB-5: Screen/window picker is desktop-only
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui, video, voice
- **Notes:** `screen_picker_dialog.gd` assumes LiveKit screen/window enumeration (lines 31-59). Basic web voice/video can ship without screen sharing initially.
