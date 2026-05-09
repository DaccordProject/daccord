# Screen Sharing Audio

Priority: 25
Depends on: Screen Sharing, Voice Channels

## Overview

Screen share audio allows users to stream application or system audio alongside their screen share video to other voice channel participants. This feature requires platform-specific system audio capture (PipeWire/PulseAudio monitor on Linux, WASAPI loopback on Windows, ScreenCaptureKit audio on macOS) fed into a `LiveKitAudioSource` and published as a `SOURCE_SCREENSHARE_AUDIO` track.

Audio capture is **not** a frametap concern — frametap is a video/screenshot library. Audio capture backends belong in **godot-livekit**, which already owns the LiveKit audio pipeline. The only frametap change needed is exposing the PipeWire audio node ID from the portal session on Wayland, since frametap owns the xdg-desktop-portal ScreenCast session. On all other platforms (Windows, macOS, X11/PulseAudio), audio capture is completely independent of video capture.

This document is an implementation plan for SCREEN-4 from the Screen Sharing user flow.

## User Steps

1. User joins a voice channel (prerequisite)
2. User clicks the **Share** button in the voice bar
3. Screen picker dialog opens with source list
4. User selects a screen or window and clicks **Start Sharing**
5. **(New)** An "Include Audio" checkbox in the screen picker (or auto-detected per platform) controls whether system audio is captured
6. Screen share video begins as today; additionally, a second audio track is published with `SOURCE_SCREENSHARE_AUDIO`
7. Remote participants hear the shared application's audio mixed into their playback
8. User clicks the share button to stop — both video and audio tracks are torn down

## Current State

### What Exists

**godot-livekit** already has the plumbing to publish screen share audio:
- `LiveKitTrack.SOURCE_SCREENSHARE_AUDIO = 4` is defined (`src/livekit_track.h:39`)
- `LiveKitAudioSource.create(sample_rate, channels, queue_size_ms)` accepts arbitrary audio frames (`src/livekit_audio_source.h:30`)
- `LiveKitAudioSource.capture_frame(data, sample_rate, channels, samples_per_channel)` pushes `PackedFloat32Array` PCM data to LiveKit (`src/livekit_audio_source.h:32`)
- `LiveKitLocalAudioTrack.create(name, source)` creates a publishable audio track
- `LiveKitLocalParticipant.publish_track(track, {"source": SOURCE_SCREENSHARE_AUDIO})` publishes with the correct source type

**daccord** has a working microphone capture pattern to replicate:
- `livekit_adapter.gd:491-510` — `_setup_mic_capture()` creates a "MicCapture" audio bus with `AudioEffectCapture`, an `AudioStreamPlayer` with `AudioStreamMicrophone`, and feeds frames in `_process()`
- `livekit_adapter.gd:349-372` — `_process()` reads frames from `AudioEffectCapture.get_buffer()`, converts stereo→mono, applies gain, pushes via `capture_frame()`
- `livekit_adapter.gd:473-489` — `_publish_local_audio()` creates `LiveKitAudioSource` and publishes with `SOURCE_MICROPHONE`

**frametap** uses PipeWire for video on Wayland (`src/platform/linux/wayland/wl_backend.cpp:71`) and has the xdg-desktop-portal session infrastructure, but captures video frames only. The portal session (`wl_portal.cpp`) could request audio sources alongside video, exposing an audio PipeWire node ID for godot-livekit to connect to.

### What Does NOT Exist

1. **No system/application audio capture in godot-livekit** — godot-livekit only provides the `AudioSource` push API, no platform audio backends exist
2. **No audio node from frametap portal** — the Wayland portal session doesn't request audio sources or expose an audio PipeWire node ID
3. **No audio track associated with screen shares** — `livekit_adapter.gd:publish_screen()` only creates a video source/track
4. **No UI for "Include Audio" option** — the screen picker dialog has no audio checkbox
5. **No remote-side handling of screenshare audio tracks** — `_on_track_subscribed()` doesn't distinguish `SOURCE_SCREENSHARE_AUDIO` from `SOURCE_MICROPHONE`

## Signal Flow (Proposed)

### Publishing Screen Share Audio

```
User clicks "Start Sharing" with "Include Audio" enabled
       |
       v
voice_bar._on_screen_source_selected(source)
       |-- source["include_audio"] == true
       |
       v
Client.start_screen_share(source)
       |
       v
ClientVoice.start_screen_share(source)
       |-- _voice_session.publish_screen(source)       [video — existing]
       |-- _voice_session.publish_screen_audio(source)  [audio — NEW]
       |
       v
LiveKitAdapter.publish_screen_audio() — NEW
       |-- mix_rate = AudioServer.get_mix_rate()
       |-- _screen_audio_source = LiveKitAudioSource.create(mix_rate, 2, 200)
       |-- _screen_audio_track = LiveKitLocalAudioTrack.create("screen_audio", source)
       |-- publish_track(track, {"source": SOURCE_SCREENSHARE_AUDIO})
       |-- _setup_system_audio_capture()   [platform-specific — see below]
       |
       v
_process() tick (alongside existing mic + screen video capture):
       |-- read frames from system audio capture effect
       |-- push to _screen_audio_source.capture_frame(...)
```

### Platform-Specific Audio Capture (in godot-livekit)

```
All platform audio backends live in godot-livekit, NOT frametap.
frametap is a video/screenshot library — audio capture is independent
of video capture on every platform except Wayland (where the portal
session must request audio alongside video).

├── Linux (Wayland/PipeWire):
|   |-- frametap exposes audio PipeWire node ID from portal session
|   |-- godot-livekit creates its own pw_stream for the audio node
|   |-- PipeWire audio stream delivers PCM frames via process callback
|   |-- Only platform where frametap is involved (portal owns the session)
|
├── Linux (PulseAudio fallback for X11):
|   |-- Create PulseAudio monitor source for default sink
|   |-- pa_simple_read() delivers PCM frames on dedicated thread
|   |-- Fully independent of video capture
|   |-- Less granular than PipeWire (captures ALL system audio)
|
├── Windows (WASAPI):
|   |-- IAudioClient in loopback mode on default render device
|   |-- GetBuffer() delivers PCM frames at device mix rate
|   |-- Fully independent of DXGI video capture
|   |-- Alternative: Windows Audio Session API for per-app capture
|
└── macOS (ScreenCaptureKit / Core Audio):
    |-- Option A: SCStreamConfiguration.capturesAudio on a new SCStream
    |-- Option B: Core Audio loopback (independent of frametap's SCStream)
    |-- Fully independent of frametap video capture
```

## Key Files

| File | Role |
|------|------|
| `scripts/voice/livekit_adapter.gd` | Would host `publish_screen_audio()`, `_setup_system_audio_capture()`, `_cleanup_screen_audio()`, and `_process()` audio frame push loop |
| `scripts/client/client_voice.gd` | Would call `publish_screen_audio()` / `unpublish_screen_audio()` alongside video |
| `scenes/sidebar/screen_picker_dialog.gd` | Would add "Include Audio" checkbox, pass `include_audio` flag in source dict |
| `scripts/voice/web_voice_session.gd` | Web `getDisplayMedia({audio: true})` handles this natively — no native capture needed |
| `../godot-livekit/src/livekit_track.h` | `SOURCE_SCREENSHARE_AUDIO = 4` already defined (line 39) |
| `../godot-livekit/src/livekit_audio_source.h` | `LiveKitAudioSource` — push API for arbitrary PCM frames (line 30-32) |
| `../godot-livekit/src/livekit_screen_capture.h` | Would expose `get_audio_node_id()` from frametap portal session |
| `../godot-livekit/src/` | Would add new `LiveKitSystemAudioCapture` class with per-platform backends (WASAPI, PulseAudio, PipeWire audio, ScreenCaptureKit) |
| `../frametap/include/frametap/types.h` | Minimal change: `PortalSession.audio_node` field (internal, not public API) |
| `../frametap/src/platform/linux/wayland/wl_portal.h` | Add `audio_node` field to `PortalSession` struct |
| `../frametap/src/platform/linux/wayland/wl_portal.cpp` | Add audio type flag to `SelectSources`, parse audio node from `Start` response |
| `../frametap/src/platform/linux/wayland/wl_backend.h` | Expose `get_audio_node_id()` accessor for godot-livekit to read |

## Implementation Details

### Architecture: Audio Capture Lives in godot-livekit, Not frametap

Frametap is a video/screenshot library. Audio capture is **not** its concern. On every platform except Wayland, audio capture is completely independent of video capture:

- **Windows:** WASAPI loopback opens the default audio render device — no connection to DXGI
- **macOS:** Core Audio or a separate SCStream — no connection to frametap's SCStream
- **X11/PulseAudio:** Monitor source is independent of XShm video capture
- **Wayland:** The only coupling — the xdg-desktop-portal ScreenCast session (owned by frametap) must request audio sources. Frametap exposes the audio PipeWire node ID; godot-livekit creates its own `pw_stream` for it.

### Implementation Plan

#### Phase 1: frametap Portal Audio Node (Wayland only — minimal change)

Extend the portal session to optionally request audio and expose the audio node ID:

**Extend `PortalSession`** in `wl_portal.h`:
```cpp
struct PortalSession {
    int pw_fd = -1;
    uint32_t pw_node = 0;        // Video node (existing)
    uint32_t audio_node = 0;     // Audio node (NEW — 0 if no audio)
    std::string session_handle;
    sd_bus *bus = nullptr;
};
```

**Extend `open_screencast_session()`** in `wl_portal.cpp`:
- Add `bool capture_audio = false` parameter
- In SelectSources, OR the source types with audio flag if supported by the portal version
- In Start response parsing, extract both video and audio stream node IDs from the `streams` array

**Expose on `WaylandBackend`** in `wl_backend.h`:
```cpp
uint32_t get_audio_node_id() const { return portal_.audio_node; }
int get_pipewire_fd() const { return portal_.pw_fd; }
```

No changes to frametap's public API (`include/frametap/`), types, or build system.

#### Phase 2: godot-livekit System Audio Capture

New `LiveKitSystemAudioCapture` class in godot-livekit with per-platform backends:

```cpp
class LiveKitSystemAudioCapture : public RefCounted {
    static Ref<LiveKitSystemAudioCapture> create();
    void start();
    void stop();
    PackedFloat32Array get_buffer();  // Returns accumulated samples since last call
    int get_sample_rate() const;
    int get_channels() const;
    bool is_supported();  // Platform check

    // For Wayland: connect to an existing portal session's audio node
    void connect_pipewire(int pw_fd, uint32_t audio_node);
};
```

**Platform backends** (all in godot-livekit, not frametap):

| Platform | API | Implementation Notes |
|----------|-----|---------------------|
| Linux (Wayland) | PipeWire audio stream | `connect_pipewire(fd, node)` creates a `pw_stream` for the audio node from frametap's portal session. Dedicated thread runs `pw_main_loop`. PCM frames accumulated in ring buffer, returned via `get_buffer()`. |
| Linux (X11) | PulseAudio monitor | `pa_simple_new()` with `@DEFAULT_MONITOR@`. Polling thread reads 10ms chunks. Converts to float32. Fully independent of frametap. Build dep: `libpulse-simple`. |
| Windows | WASAPI loopback | `IMMDeviceEnumerator::GetDefaultAudioEndpoint(eRender)` → `IAudioClient::Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK)` → `IAudioCaptureClient::GetBuffer()`. Dedicated thread, converts to float32. |
| macOS | ScreenCaptureKit | Separate `SCStream` with `capturesAudio = YES`, `excludesCurrentProcessAudio = YES`. Handle `SCStreamOutputTypeAudio`. Extract float32 from `CMSampleBuffer`. |
| Android | N/A | MediaProjection audio requires API 29+, foreground service. Low priority. |

The polling pattern (`get_buffer()` returning accumulated samples) matches the existing `AudioEffectCapture.get_buffer()` pattern in daccord's mic capture.

#### Phase 3: daccord Integration

Wire up the capture in the daccord GDScript layer:

**livekit_adapter.gd** — New state variables:
```gdscript
var _screen_audio_source: RefCounted   # LiveKitAudioSource
var _screen_audio_track: RefCounted    # LiveKitLocalAudioTrack
var _screen_audio_pub: RefCounted      # LiveKitLocalTrackPublication
var _system_audio_capture: RefCounted  # LiveKitSystemAudioCapture (or extended ScreenCapture)
```

**livekit_adapter.gd** — New `publish_screen_audio()`:
```gdscript
func publish_screen_audio() -> bool:
    _cleanup_screen_audio()
    _system_audio_capture = LiveKitSystemAudioCapture.create()
    if _system_audio_capture == null or not _system_audio_capture.is_supported():
        return false
    _system_audio_capture.start()
    var sr: int = _system_audio_capture.get_sample_rate()
    var ch: int = _system_audio_capture.get_channels()
    _screen_audio_source = LiveKitAudioSource.create(sr, ch, 200)
    _screen_audio_track = LiveKitLocalAudioTrack.create("screen_audio", _screen_audio_source)
    var lp: LiveKitLocalParticipant = _room.get_local_participant()
    _screen_audio_pub = lp.publish_track(
        _screen_audio_track,
        {"source": LiveKitTrack.SOURCE_SCREENSHARE_AUDIO}
    )
    return _screen_audio_pub != null
```

**livekit_adapter.gd** — `_process()` addition (after existing screen video + mic capture):
```gdscript
# System audio: capture frames → push to screen audio track
if _system_audio_capture != null and _screen_audio_source != null:
    var buf: PackedFloat32Array = _system_audio_capture.get_buffer()
    if buf.size() > 0:
        var sr: int = _system_audio_capture.get_sample_rate()
        var ch: int = _system_audio_capture.get_channels()
        _screen_audio_source.capture_frame(buf, sr, ch, buf.size() / ch)
```

**screen_picker_dialog.gd** — Add checkbox:
```gdscript
# In _build_content() or _build_preview_panel():
var audio_check := CheckBox.new()
audio_check.text = "Include system audio"
audio_check.button_pressed = true  # Default on
audio_check.visible = LiveKitSystemAudioCapture.is_supported()
# On confirm: source["include_audio"] = audio_check.button_pressed
```

**client_voice.gd** — Wire audio alongside video:
```gdscript
func start_screen_share(source: Dictionary) -> void:
    # ... existing video publish ...
    if source.get("include_audio", false):
        _voice_session.publish_screen_audio()

func stop_screen_share() -> void:
    # ... existing video cleanup ...
    _voice_session.unpublish_screen_audio()
```

#### Phase 4: Remote-Side Handling

Remote participants receive `SOURCE_SCREENSHARE_AUDIO` as a separate audio track:

**livekit_adapter.gd** — `_on_track_subscribed()` already sets up remote audio playback for any `KIND_AUDIO` track. No changes needed if the existing pipeline handles it generically. However, the track should be labeled so the UI can show an audio indicator.

### Web Export Considerations

The web export (`web_voice_session.gd`) uses browser `getDisplayMedia()`. Browsers natively support `{audio: true}` in the constraints:

```javascript
navigator.mediaDevices.getDisplayMedia({
    video: true,
    audio: true  // Browser shows "Share audio" checkbox
})
```

This is handled in `godot-livekit-web.js` and requires no native capture code. The browser handles the audio capture and LiveKit's JavaScript SDK publishes it as `SOURCE_SCREENSHARE_AUDIO` automatically.

### Platform Availability Matrix

| Platform | Video (frametap) | Audio (godot-livekit) | Audio API | Notes |
|----------|:----------------:|:--------------------:|-----------|-------|
| Linux (Wayland) | Yes | Planned | PipeWire | Portal audio node from frametap; pw_stream in godot-livekit |
| Linux (X11) | Yes | Planned | PulseAudio | Monitor source, fully independent of frametap |
| Windows | Yes | Planned | WASAPI | Loopback mode, fully independent of frametap |
| macOS | Yes | Planned | ScreenCaptureKit | Separate SCStream, fully independent of frametap |
| Web | Yes | Planned | getDisplayMedia | Browser-native, no native capture needed |
| Android | Yes | Not planned | MediaProjection | API 29+ only, requires foreground service |

### Cleanup Order (Critical)

Following the same careful order as screen video cleanup (`livekit_adapter.gd:605-631`):

1. Stop `_system_audio_capture` (stops native audio thread)
2. Mute `_screen_audio_track` (flush encoder)
3. Null `_screen_audio_source` (C++ destructor joins capture thread)
4. Close system audio capture handle
5. Null track, publication references

## Implementation Status

- [x] `SOURCE_SCREENSHARE_AUDIO` enum defined in godot-livekit (`livekit_track.h:39`)
- [x] `LiveKitAudioSource` push API exists for arbitrary PCM frames
- [x] Microphone capture pattern established as reference implementation
- [x] PipeWire integration exists in frametap for video (extensible to audio)
- [x] Screen picker dialog with confirmation flow (UI to extend)
- [ ] frametap Wayland portal audio node exposure (minimal: `PortalSession.audio_node` + SelectSources flag)
- [ ] godot-livekit `LiveKitSystemAudioCapture` class with platform backends
- [ ] godot-livekit Linux/Wayland audio backend (PipeWire stream from portal audio node)
- [ ] godot-livekit Linux/X11 audio backend (PulseAudio monitor)
- [ ] godot-livekit Windows audio backend (WASAPI loopback)
- [ ] godot-livekit macOS audio backend (ScreenCaptureKit audio)
- [ ] daccord `publish_screen_audio()` in livekit_adapter.gd
- [ ] daccord `_process()` system audio frame push loop
- [ ] daccord screen picker "Include Audio" checkbox
- [ ] daccord client_voice.gd audio track lifecycle (start/stop/cleanup)
- [ ] daccord remote screenshare audio track playback verification
- [ ] Web export getDisplayMedia audio support in godot-livekit-web.js
- [ ] Platform availability detection and graceful fallback

## Tasks

### SCREEN-AUDIO-1: frametap Wayland portal audio node
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** audio, native, frametap, linux
- **Notes:** Minimal frametap change. Add `audio_node` field to `PortalSession` struct in `wl_portal.h`. Extend `open_screencast_session()` with `bool capture_audio` parameter. In `SelectSources`, OR source types with audio flag. In `Start` response, parse audio node ID from `streams` array. Expose `get_audio_node_id()` and `get_pipewire_fd()` on `WaylandBackend`. No changes to frametap's public API, types, or build system.

### SCREEN-AUDIO-2: godot-livekit LiveKitSystemAudioCapture class
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** audio, native, godot-livekit
- **Notes:** New `LiveKitSystemAudioCapture` RefCounted class with `create()`, `start()`, `stop()`, `get_buffer()`, `get_sample_rate()`, `get_channels()`, `is_supported()`, and `connect_pipewire(fd, node)` for Wayland. Ring buffer accumulates PCM samples between `_process()` polls. Register in `register_types.cpp`. Platform backends compile conditionally.

### SCREEN-AUDIO-3: godot-livekit Linux PipeWire audio backend
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** audio, native, godot-livekit, linux
- **Notes:** `connect_pipewire(fd, node)` creates a `pw_stream` connected to the audio node from frametap's portal session. Runs `pw_main_loop` on dedicated thread. PipeWire delivers float32 PCM via `process` callback. Accumulated in thread-safe ring buffer. Resampling may be needed if PipeWire negotiates a rate other than 48kHz.

### SCREEN-AUDIO-4: godot-livekit Linux PulseAudio fallback
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** audio, native, godot-livekit, linux
- **Notes:** For X11 sessions without PipeWire. `pa_simple_new()` with `@DEFAULT_MONITOR@`. Polling thread reads 10ms chunks, converts to float32. Captures ALL system audio (no per-app isolation). Build dep: `libpulse-simple`.

### SCREEN-AUDIO-5: godot-livekit Windows WASAPI loopback
- **Status:** open
- **Impact:** 4
- **Effort:** 3
- **Tags:** audio, native, godot-livekit, windows
- **Notes:** `IMMDeviceEnumerator::GetDefaultAudioEndpoint(eRender, eConsole)` → `IAudioClient::Initialize()` with `AUDCLNT_STREAMFLAGS_LOOPBACK` → `IAudioCaptureClient::GetBuffer()`. Dedicated thread. WASAPI delivers in device mix format (usually float32 at 48kHz). Link against `ole32`, `mmdevapi`.

### SCREEN-AUDIO-6: godot-livekit macOS ScreenCaptureKit audio
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** audio, native, godot-livekit, macos
- **Notes:** Create separate `SCStream` with `capturesAudio = YES` and `excludesCurrentProcessAudio = YES`. Handle `SCStreamOutputTypeAudio` in output delegate. Extract interleaved float32 from `CMSampleBuffer`. Independent of frametap's video SCStream.

### SCREEN-AUDIO-7: daccord screen share audio publishing
- **Status:** open
- **Impact:** 4
- **Effort:** 2
- **Tags:** audio, voice, daccord
- **Notes:** Add `publish_screen_audio()` / `unpublish_screen_audio()` to `livekit_adapter.gd`. Create `LiveKitAudioSource` + `LiveKitLocalAudioTrack`, publish with `SOURCE_SCREENSHARE_AUDIO`. Add `_process()` loop to read system audio buffer and push frames. Wire into `client_voice.gd` start/stop screen share flow. Follow cleanup order from screen video.

### SCREEN-AUDIO-8: Screen picker "Include Audio" UI
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** ui, daccord
- **Notes:** Add a `CheckBox` labeled "Include system audio" to `screen_picker_dialog.gd`, visible only when `LiveKitSystemAudioCapture.is_supported()` returns true. Pass `include_audio` flag in the source dictionary. Default to checked. On web, browser natively shows its own audio checkbox so this may be hidden.

### SCREEN-AUDIO-9: Web getDisplayMedia audio
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** audio, web
- **Notes:** Update `godot-livekit-web.js` to pass `{audio: true}` to `getDisplayMedia()` constraints. The browser and LiveKit JS SDK handle the rest — the audio track is automatically published as `SOURCE_SCREENSHARE_AUDIO`. Lowest effort of all tasks.

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No system audio capture in godot-livekit | High | Core blocker — godot-livekit needs `LiveKitSystemAudioCapture` with per-platform backends: PipeWire (Wayland), PulseAudio (X11), WASAPI (Windows), ScreenCaptureKit (macOS). (SCREEN-AUDIO-2 through SCREEN-AUDIO-6) |
| No audio node from frametap portal | High | Wayland portal session doesn't request audio sources. Minimal frametap change needed to expose audio PipeWire node ID (SCREEN-AUDIO-1) |
| No screenshare audio track in daccord | High | `publish_screen()` only creates video track. Need parallel audio track with `SOURCE_SCREENSHARE_AUDIO` (SCREEN-AUDIO-7) |
| No "Include Audio" UI in screen picker | Medium | Users need a way to opt in/out of audio sharing (SCREEN-AUDIO-8) |
| Web getDisplayMedia doesn't request audio | Medium | Simple constraint addition but blocks web audio sharing (SCREEN-AUDIO-9) |
| Per-application audio isolation | Low | PulseAudio monitor and WASAPI loopback capture ALL system audio. Per-app capture requires PipeWire (Linux) or Windows Audio Session API. Not critical for MVP |
| Android audio capture | Low | MediaProjection audio requires API 29+, foreground service, and RECORD_AUDIO permission. Low priority given mobile screen share is already limited |
| Audio level indicator for screen share audio | Low | Remote participants have no visual indication that screen audio is active vs. just video. Could reuse speaking indicator pattern |
| Echo cancellation between mic and system audio | Low | If user's mic picks up the same audio being screen-shared, remote participants hear a doubled/echoed signal. May need to exclude self-process audio (macOS ScreenCaptureKit has `excludesCurrentProcessAudio`) |
