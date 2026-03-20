# Screen Sharing

Priority: 24
Depends on: Video Chat

## Overview

Screen sharing in daccord lets users broadcast their display or a specific window to other participants in a voice channel. The flow uses the godot-livekit GDExtension's `LiveKitScreenCapture` API for native screen/window enumeration and capture, publishing frames via `LiveKitVideoSource.capture_frame()` to a `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`. The published stream renders both as a local preview tile and as a live remote tile for other participants in the voice channel. Screen shares are automatically spotlighted (displayed as a large dominant view with participants in a strip below).

The screen picker dialog shows thumbnail previews of each monitor/window and includes a confirmation step with a full-size preview before sharing begins.

## User Steps

1. User joins a voice channel (prerequisite — must already be in voice)
2. User clicks the **Share** button in the voice bar
3. A modal overlay appears listing available screens under a "Screens" header and open windows under a "Windows" header, each showing a thumbnail preview, name, and resolution (e.g., "DP-1 (2560x1440)")
4. If screen capture permissions are missing, an error message is shown instead of the source list
5. User clicks a screen or window — a full-size preview of the selected source appears with its name and resolution, alongside "Back" and "Start Sharing" buttons
6. User clicks **Start Sharing** to confirm — the dialog closes and sharing begins
7. The Share button changes to show a screen-share-off icon with a green tint, tooltip "Stop Sharing"
8. A video tile showing the local screen share preview appears spotlighted (large dominant view) in the video grid
9. Remote participants see a blue "S" indicator next to the user's name in the voice channel participant list
10. Remote participants see the shared screen rendered as a spotlighted video tile in their video grid
11. User clicks the share button again to stop — the tile disappears and the button reverts

## Signal Flow

### Start Screen Share

```
User clicks "Share" button
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd:177)
       |-- AppState.is_screen_sharing == false
       |
       v
ScreenPickerDialog instantiated               (voice_bar.gd:181)
       |-- source_selected.connect(_on_screen_source_selected)
       |-- added to scene tree root
       |
       v
ScreenPickerDialog._ready()                   (screen_picker_dialog.gd:23)
       |-- LiveKitScreenCapture.check_permissions()
       |-- if PERMISSION_ERROR: show error label, stop
       |-- else: _populate_sources()
       |
       v
_populate_sources()                            (screen_picker_dialog.gd:112)
       |-- LiveKitScreenCapture.get_monitors() -> Array of {id, name, x, y, width, height, scale}
       |-- LiveKitScreenCapture.get_windows()  -> Array of {id, name, x, y, width, height}
       |-- creates "Screens" header + thumbnail button per monitor
       |-- creates "Windows" header + thumbnail button per window
       |-- each button stores source dict with "_type": "monitor" or "window"
       |
User clicks a source button
       |
       v
_show_preview(source)                          (screen_picker_dialog.gd:97)
       |-- _capture_screenshot(source) for full-size preview
       |-- hides source list, shows preview panel
       |-- title changes to "Preview"
       |
User clicks "Start Sharing"
       |
       v
_confirm_share()                               (screen_picker_dialog.gd:109)
       |-- source_selected.emit(source_dict)
       |-- dialog closes via _close()
       |
       v
voice_bar._on_screen_source_selected(source)   (voice_bar.gd:185)
       |
       v
Client.start_screen_share(source)              (client.gd:631)
       |
       v
ClientVoice.start_screen_share(source)         (client_voice.gd:250)
       |-- _voice_log("start_screen_share source=...")
       |-- closes existing _screen_track if any
       |-- calls _voice_session.publish_screen(source)
       |
       v
LiveKitAdapter.publish_screen(source)          (livekit_adapter.gd:215)
       |-- _cleanup_local_screen() (closes prior capture + track)
       |-- source._type == "monitor" or "window"
       |-- LiveKitScreenCapture.create_for_monitor(source)
       |       or create_for_window(source)
       |-- _capped_size(source.width, source.height) for encoding resolution
       |-- LiveKitVideoSource.create(capped_w, capped_h)
       |-- LiveKitLocalVideoTrack.create("screen", source)
       |-- LiveKitLocalParticipant.publish_track(
       |       track, {source: SOURCE_SCREENSHARE, max_bitrate: ...})
       |-- returns LocalVideoPreview (lightweight RefCounted)
       |
       v
ClientVoice stores stream in Client._screen_track
       |-- _voice_log("start_screen_share success")
       |
       v
AppState.set_screen_sharing(true)              (app_state.gd:394)
       |-- is_screen_sharing = true
       |-- screen_share_changed.emit(true)
       |
       +---> voice_bar._on_screen_share_changed()  (voice_bar.gd:236)
       |         |-- _update_button_visuals()
       |         |-- icon → ICON_SCREEN_SHARE_OFF, green tint
       |
       +---> video_grid._on_video_changed()        (video_grid.gd:108)
                 |-- _rebuild()
                 |-- _has_screen_share() → true → auto-spotlight
                 |-- _rebuild_spotlight() with screen tile dominant
```

### Frame Capture Loop (livekit_adapter.gd _process)

```
Every _process() tick while _screen_capture != null:
       |
       v
_screen_capture.screenshot()                   (livekit_adapter.gd:316)
       |-- synchronous capture (start_async doesn't fire on X11)
       |-- returns Image with native pixel data
       |
       v
Resize if capture size != _screen_capture_size (livekit_adapter.gd:318)
       |-- image.resize(..., INTERPOLATE_BILINEAR)
       |
       v
_local_screen_source.capture_frame(image)      (livekit_adapter.gd:321)
       |-- pushes frame to LiveKit video source
       |-- LiveKit encodes and transmits to remote peers
       |
       v
_screen_preview.update_frame(image)            (livekit_adapter.gd:323)
       |-- updates local preview ImageTexture
       |-- emits frame_received signal
       |-- fixes X11 alpha=0 issue via RGB8 round-trip
```

### Stop Screen Share

```
User clicks share button (now showing stop icon)
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd:177)
       |-- AppState.is_screen_sharing == true
       |
       v
Client.stop_screen_share()                   (client.gd:634)
       |
       v
ClientVoice.stop_screen_share()              (client_voice.gd:270)
       |-- _voice_log("stop_screen_share")
       |-- _screen_track.close() (releases preview texture)
       |-- _screen_track = null
       |-- _voice_session.unpublish_screen()
       |
       v
LiveKitAdapter.unpublish_screen()            (livekit_adapter.gd:282)
       |-- _cleanup_local_screen()
       |-- nulls _screen_capture (stops _process loop)
       |-- mutes track to flush encoder
       |-- nulls _local_screen_source (C++ destructor joins thread)
       |-- capture.close()
       |-- _screen_preview.close() + null
       |-- nulls track, pub, resets size
       |
       v
AppState.set_screen_sharing(false)
       |-- is_screen_sharing = false
       |-- screen_share_changed.emit(false)
       |
       +---> voice_bar: icon → ICON_SCREEN_SHARE, green tint removed
       +---> video_grid: _rebuild() removes screen tile, spotlight off
```

### Remote Peer Receives Screen Share

```
LiveKit server delivers screen share track to remote peer
       |
       v
LiveKitAdapter._on_track_subscribed()        (livekit_adapter.gd)
       |-- track.get_kind() == KIND_VIDEO
       |-- LiveKitVideoStream.from_track(track)
       |-- _remote_video[identity] = stream
       |-- track_received.emit(uid, stream)
       |
       v
ClientVoice.on_track_received()              (client_voice.gd)
       |-- closes previous track for same peer
       |-- Client._remote_tracks[user_id] = stream
       |-- AppState.remote_track_received.emit(uid, stream)
       |
       v
VideoGrid._on_remote_track_received()        (video_grid.gd:123)
       |-- _rebuild()
       |-- _collect_tiles() checks state.self_stream (line 355)
       |-- auto-spotlight: is_screen → spotlight_tile_idx (line 449)
       |-- _rebuild_spotlight() → large tile + strip
       |
       v
VideoTile._process()                         (video_tile.gd:91)
       |-- _stream.get_texture() -> ImageTexture
       |-- video_rect.texture = tex
```

### Cleanup on Voice Disconnect

```
User clicks Disconnect (or force-disconnected)
       |
       v
ClientVoice.leave_voice_channel()            (client_voice.gd)
       |-- _screen_track.close()
       |-- _screen_track = null
       |-- all remote tracks closed
       |-- _voice_session.disconnect_voice()
       |
       v
LiveKitAdapter.disconnect_voice()            (livekit_adapter.gd)
       |-- _cleanup_local_screen()
       |-- nulls all local track references
       |-- room teardown handles unpublishing
       |
       v
AppState.leave_voice()                       (app_state.gd:372)
       |-- is_screen_sharing = false
       |-- voice_left.emit(old_channel)
       |
       v
VideoGrid._on_voice_left()                  (video_grid.gd:119)
       |-- _clear() + visible = false
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/screen_picker_dialog.gd` | Screen picker overlay: enumerates monitors/windows via `LiveKitScreenCapture`, thumbnail previews, confirmation step with full-size preview, emits `source_selected(source: Dictionary)` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: full-screen `ColorRect` backdrop with centered 520x480 panel + `ScrollContainer` of source buttons |
| `scenes/sidebar/voice_bar.gd` | Share button handler: opens screen picker or stops share, icon/tooltip/style state updates |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: share button in `ButtonRow` |
| `scenes/video/video_grid.gd` | Self-managing grid: rebuilds tiles from AppState signals, auto-spotlights screen shares, spotlight area + participant strip layout |
| `scenes/video/video_grid.tscn` | Video grid scene: VBox with SpotlightArea + ParticipantGrid |
| `scenes/video/video_tile.gd` | Renders live video via `LocalVideoPreview.get_texture()` or `LiveKitVideoStream.poll()` + `get_texture()` per frame; double-click toggles spotlight |
| `scenes/video/video_tile.tscn` | Video tile scene: 160x120 min size, dark background, `TextureRect` + name bar |
| `scripts/autoload/app_state.gd` | `screen_share_changed` signal (line 70), `is_screen_sharing` state (line 235), `set_screen_sharing()` (line 394), `spotlight_changed` signal (line 86) |
| `scripts/autoload/client.gd` | `start_screen_share(source)` / `stop_screen_share()` public API (lines 631-635), `_screen_track` storage (line 154), `get_screen_track()` (line 640) |
| `scripts/client/client_voice.gd` | `start_screen_share(source)` (line 250): publish flow + state update + voice logging; `stop_screen_share()` (line 270): cleanup flow; `_send_voice_state_update()` (line 282): gateway sync with `is_screen_sharing` flag |
| `scripts/voice/livekit_adapter.gd` | `publish_screen(source)` (line 215): creates `LiveKitScreenCapture` + `LiveKitVideoSource` + `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`; `_process()` frame loop (line 312) uses `.screenshot()` synchronously; `_cleanup_local_screen()` (line 605); `LocalVideoPreview` inner class (line 692); `_republish_screen()` on reconnection (line 252) |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState.self_stream` flag for screen share state |
| `scripts/client/client_models.gd` | `voice_state_to_dict()` includes `self_stream` key |
| `scenes/sidebar/channels/voice_channel_item.gd` | Blue "S" indicator for participants who are screen sharing |

## Implementation Details

### Screen Picker Dialog (screen_picker_dialog.gd)

A `ModalBase` overlay that covers the full viewport with a semi-transparent backdrop. On `_ready()`, builds a preview/confirmation panel, then checks platform and screen capture permissions via `LiveKitScreenCapture.check_permissions()`.

**Permission check:**
- Web platform: shows "Screen sharing is not supported in the web client" (line 29)
- If `status == PERMISSION_ERROR`, shows an error label with the `summary` string and stops
- Otherwise, calls `_populate_sources()`

**Source enumeration** (`_populate_sources()`, line 112):
- `LiveKitScreenCapture.get_monitors()` returns an array of `{id, name, x, y, width, height, scale}` dicts
- `LiveKitScreenCapture.get_windows()` returns an array of `{id, name, x, y, width, height}` dicts
- Monitors are shown under a "Screens" section header, windows under a "Windows" section header
- Each source is presented as a button with an 80x45 thumbnail icon and text: `"Name  (WxH)"`
- If no monitors or windows are found, shows "No screens or windows found"

**Thumbnail capture** (`_capture_screenshot()`, line 155):
- Creates a temporary `LiveKitScreenCapture` instance for the source
- Calls `.screenshot()` to capture a single frame
- Closes the capture immediately and returns the `Image`
- For source list buttons, the image is resized to 80x45 and set as the button icon
- For the preview panel, the full-size image is displayed

**Confirmation step** (`_show_preview()`, line 97):
- When user clicks a source button, the source list is hidden and a preview panel is shown
- Full-size screenshot of the selected source is displayed in a `TextureRect`
- Source name and resolution shown below the preview
- "Back" button returns to the source list; "Start Sharing" confirms and starts sharing

**Source selection** (`_confirm_share()`, line 109):
- Emits `source_selected(source_dict)` and closes the dialog via `_close()`

**Dismissal:**
- Escape key via `ModalBase._input()` `ui_cancel` action
- Clicking the backdrop
- Close button in the header

### Voice Bar Share Button (voice_bar.gd)

The Share button toggles between two states:

**Starting a share** (line 177):
- Checks `AppState.is_screen_sharing` — if false, instantiates `ScreenPickerDialog`
- Connects `source_selected` signal to `_on_screen_source_selected(source: Dictionary)` (line 185)
- Adds the dialog to the scene tree root

**Stopping a share:**
- If `AppState.is_screen_sharing` is true, calls `Client.stop_screen_share()` directly — no confirmation dialog

**Visual feedback** (`_update_button_visuals()`, line 279):
- Active state: icon → `ICON_SCREEN_SHARE_OFF`, tooltip "Stop Sharing", green `StyleBoxFlat` overlay from `ThemeManager.make_flat_style("success", ...)` with 4px corner radius
- Inactive state: icon → `ICON_SCREEN_SHARE`, tooltip "Screen Share", style override removed

### Publishing Pipeline (client_voice.gd + livekit_adapter.gd)

**ClientVoice.start_screen_share(source: Dictionary)** (line 250):
1. Logs the source dictionary via `_voice_log()`
2. Early-returns if not in a voice channel
3. Stops any existing screen track: `_screen_track.close()` + `unpublish_screen()`
4. Calls `_voice_session.publish_screen(source)` which returns a `LocalVideoPreview`
5. On failure (null), emits `voice_error("Failed to share screen")`
6. Stores the preview in `Client._screen_track`
7. Logs success, sets `AppState.set_screen_sharing(true)`
8. Sends a gateway voice state update with all current flags

**LiveKitAdapter.publish_screen(source: Dictionary)** (line 215):
1. `_cleanup_local_screen()` closes any prior capture + track
2. Determines type from `source.get("_type", "monitor")`
3. Creates capture: `LiveKitScreenCapture.create_for_monitor(source)` or `create_for_window(source)`
4. `_capped_size(source.width, source.height)` — scales down to `Config.get_max_screen_capture_size()` while preserving aspect ratio and ensuring even dimensions
5. Creates `LiveKitVideoSource.create(capped_w, capped_h)`
6. Creates `LiveKitLocalVideoTrack.create("screen", _local_screen_source)`
7. Publishes with `SOURCE_SCREENSHARE` and doubled bitrate (text clarity)
8. Returns a `LocalVideoPreview` instance for local tile rendering

**Frame capture loop in `_process()`** (line 312):
- Uses synchronous `_screen_capture.screenshot()` each frame (async `start()` callback doesn't fire on X11)
- Resizes captured image to `_screen_capture_size` if dimensions don't match
- `_local_screen_source.capture_frame(image)` pushes the frame to LiveKit
- `_screen_preview.update_frame(image)` updates the local preview texture with alpha fix (X11 32-bit depth returns alpha=0; fixed via RGB8 round-trip)

**Reconnection** (`_republish_screen()`, line 252):
- When room reconnects, re-creates source/track/publication from the surviving `_screen_capture`
- Uses a fresh screenshot to determine current resolution

### Spotlight Layout (video_grid.gd)

Screen shares are automatically spotlighted in `FULL_AREA` mode:

**Auto-spotlight logic** (`_rebuild()`, lines 447-452):
- If no manual `AppState.spotlight_user_id` is set, scans tiles for `is_screen == true`
- First screen share tile found becomes the spotlight

**Spotlight rendering** (`_rebuild_spotlight()`, line 691):
- Spotlight tile rendered in `spotlight_area` (large, fills available space)
- Remaining participants rendered as small tiles in the `ParticipantGrid` strip below
- Vertical resize handle between spotlight and grid (min 100px, max 70% of parent)

**Manual spotlight** (video_tile.gd, line 75):
- Double-clicking any tile toggles it as the spotlight via `AppState.set_spotlight(user_id)`

**Grid columns** (`_update_grid_columns()`, line 232):
- When spotlight or screen share is active, grid uses `columns = 99` (single horizontal row)

### Gateway State Synchronization (client_voice.gd)

`_send_voice_state_update()` (line 282) sends the current screen share state to the server via `AccordClient.update_voice_state()`, which includes `AppState.is_screen_sharing` as the `self_stream` parameter (line 295). This ensures remote participants see the blue "S" indicator in the voice channel participant list even before the video track arrives.

### Track Cleanup

Screen share tracks are cleaned up in four scenarios:

1. **User stops sharing** (`stop_screen_share()`, line 270): closes preview stream, unpublishes from room, cleans up screen capture, resets AppState
2. **User leaves voice** (`leave_voice_channel()`): closes `_screen_track` alongside camera and remote tracks
3. **Voice disconnect** (room disconnection): `_cleanup_local_screen()` (line 605) nulls `_screen_capture` to stop `_process()` loop, mutes track, destroys source (C++ destructor joins thread), closes capture handle, cleans preview, nulls remaining references
4. **AppState.leave_voice()** (line 372): resets `is_screen_sharing = false` as part of clearing all voice state

### LocalVideoPreview (livekit_adapter.gd:692)

Lightweight `RefCounted` inner class that replaces `LiveKitVideoStream.from_track()` for local tracks (the SDK reader blocks forever on local tracks). Updated directly from the capture loop:
- `update_frame(image)` converts to `ImageTexture`, emits `frame_received`
- `get_texture()` returns the current `ImageTexture`
- `close()` nulls the texture to release resources
- Handles X11 alpha=0 bug by converting through RGB8 format (line 707)

## Implementation Status

- [x] Screen picker dialog enumerating monitors via LiveKitScreenCapture
- [x] Window enumeration via LiveKitScreenCapture
- [x] Permission check at dialog open
- [x] Screen resolution display per source
- [x] Thumbnail previews in source list via LiveKitScreenCapture.screenshot()
- [x] Confirmation step with full-size preview before sharing
- [x] Share button in voice bar with active/inactive icon/tooltip/style states
- [x] Source dictionary flows through to LiveKitAdapter.publish_screen(source)
- [x] Native screen capture via LiveKitScreenCapture.create_for_monitor/create_for_window
- [x] Frame capture loop in _process() using synchronous .screenshot()
- [x] Resolution capping via _capped_size() with aspect ratio preservation
- [x] Publishing screen share track via LiveKitAdapter with SOURCE_SCREENSHARE
- [x] Double bitrate for screen shares (text clarity)
- [x] Local screen share preview tile via LocalVideoPreview
- [x] Remote screen share rendering via LiveKitVideoStream polling
- [x] AppState `screen_share_changed` signal and `is_screen_sharing` state
- [x] Gateway voice state sync with `self_stream` flag
- [x] Blue "S" indicator in voice channel participant list for screen sharers
- [x] Auto-spotlight layout for screen shares (large dominant view + strip)
- [x] Manual spotlight via double-click on any tile
- [x] Vertical resize handle between spotlight and participant strip
- [x] Track cleanup on stop, voice leave, and disconnect
- [x] Escape / backdrop click / close button to dismiss screen picker
- [x] Screen capture re-publish on room reconnection
- [x] Voice logging in start_screen_share and stop_screen_share
- [x] X11 alpha=0 fix in LocalVideoPreview (RGB8 round-trip)
- [ ] Screen share audio (system audio capture alongside video)
- [ ] Mini PiP preview when navigating away from voice channel

## Tasks

### SCREEN-1: Hardcoded 1920x1080 resolution
- **Status:** done
- **Impact:** 3
- **Effort:** 1
- **Tags:** video, voice
- **Notes:** `publish_screen()` now reads `source.get("width", 1920)` and `source.get("height", 1080)` from the selected monitor/window, then applies `_capped_size()` to scale down to `Config.get_max_screen_capture_size()` while preserving aspect ratio. Fallback values only apply if source dict is missing dimensions (shouldn't happen with the picker).

### SCREEN-2: No actual frame capture
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** video, voice
- **Notes:** `_process()` at line 312 uses synchronous `_screen_capture.screenshot()` each frame (the async `start()` callback doesn't fire on X11). Frames are resized to `_screen_capture_size` if needed and pushed via `capture_frame()`. `LocalVideoPreview.update_frame()` provides the local preview.

### SCREEN-3: No spotlight layout for screen shares
- **Status:** done
- **Impact:** 3
- **Effort:** 3
- **Tags:** ui, video
- **Notes:** `video_grid.gd` auto-spotlights screen share tiles at lines 447-452. `_rebuild_spotlight()` renders the screen share in a large `spotlight_area` with other participants in a horizontal `ParticipantGrid` strip below. A vertical resize handle allows adjusting the split. Manual spotlight via double-click on any tile.

### SCREEN-4: No screen share audio
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** audio, video, voice
- **Notes:** Only the video track is published. System audio capture is not included in the screen share. Would require a separate `LiveKitAudioSource` capturing desktop audio, plus platform-specific loopback capture (PulseAudio monitor on Linux, WASAPI loopback on Windows).

### SCREEN-5: Screen picker shows thumbnails
- **Status:** done
- **Impact:** 2
- **Effort:** 3
- **Tags:** ui, voice
- **Notes:** Each source button now shows an 80x45 thumbnail via `_capture_screenshot()` which creates a temporary `LiveKitScreenCapture` instance, calls `.screenshot()`, and closes it. The image is resized and set as the button icon.

### SCREEN-6: Confirmation before sharing
- **Status:** done
- **Impact:** 2
- **Effort:** 2
- **Tags:** general
- **Notes:** Clicking a source now shows a preview panel with a full-size screenshot, source name/resolution, and "Back" / "Start Sharing" buttons. The user must explicitly confirm before sharing begins.
