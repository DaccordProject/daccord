# Screen Sharing

## Overview

Screen sharing in daccord lets users broadcast their display or a specific window to other participants in a voice channel. The flow uses the godot-livekit GDExtension's `LiveKitScreenCapture` API for native screen/window enumeration and capture, publishing frames via `LiveKitVideoSource.capture_frame()` to a `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`. The published stream renders both as a local preview tile and as a live remote tile for other participants in the voice channel.

**Available but not yet integrated:** The godot-livekit addon now provides `LiveKitScreenCapture` -- a native screen/window capture class backed by the **frametap** library. It supports enumerating monitors (`get_monitors()`) and individual application windows (`get_windows()`), permission checking (`check_permissions()`), and continuous frame capture (`start()` / `poll()` / `get_image()` / `get_texture()`). This class can replace the current `DisplayServer`-based enumeration and fill the missing frame capture gap, and enables window-level sharing. See the Gaps section for integration details.

## User Steps

1. User joins a voice channel (prerequisite -- must already be in voice)
2. User clicks the **Share** button in the voice bar
3. A full-screen overlay appears listing available screens under a "Screens" header and open windows under a "Windows" header, each showing name and resolution (e.g., "DP-1 (2560x1440)")
4. If screen capture permissions are missing, an error message is shown instead of the source list
5. User clicks a screen or window to select it -- the overlay closes automatically
6. The Share button changes to **Sharing** with a green tint, indicating an active share
7. A video tile showing the local screen share preview appears in the video grid above the message area
8. Remote participants see a blue "S" indicator next to the user's name in the voice channel participant list
9. Remote participants see the shared screen rendered as a live video tile in their video grid
10. User clicks the **Sharing** button again to stop -- the tile disappears and the button reverts to "Share"

## Signal Flow

### Start Screen Share

```
User clicks "Share" button
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd)
       |-- AppState.is_screen_sharing == false
       |
       v
ScreenPickerDialog instantiated               (voice_bar.gd)
       |-- source_selected.connect(_on_screen_source_selected)
       |-- added to scene tree root
       |
       v
ScreenPickerDialog._ready()                   (screen_picker_dialog.gd)
       |-- LiveKitScreenCapture.check_permissions()
       |-- if PERMISSION_ERROR: show error label, stop
       |-- else: _populate_sources()
       |
       v
_populate_sources()                            (screen_picker_dialog.gd)
       |-- LiveKitScreenCapture.get_monitors() -> Array of {id, name, x, y, width, height, scale}
       |-- LiveKitScreenCapture.get_windows()  -> Array of {id, name, x, y, width, height}
       |-- creates "Screens" header + button per monitor
       |-- creates "Windows" header + button per window
       |-- each button stores source dict with "_type": "monitor" or "window"
       |
User clicks a source button
       |
       v
source_selected.emit(source_dict)              (screen_picker_dialog.gd)
       |-- dialog self-destructs via queue_free()
       |
       v
voice_bar._on_screen_source_selected(source)   (voice_bar.gd)
       |
       v
Client.start_screen_share(source)              (client.gd)
       |
       v
ClientVoice.start_screen_share(source)         (client_voice.gd)
       |-- _voice_log("start_screen_share source=...")
       |-- closes existing _screen_track if any
       |-- calls _voice_session.publish_screen(source)
       |
       v
LiveKitAdapter.publish_screen(source)          (livekit_adapter.gd)
       |-- _cleanup_local_screen() (closes prior capture + track)
       |-- source._type == "monitor" or "window"
       |-- LiveKitScreenCapture.create_for_monitor(source)
       |       or create_for_window(source)
       |-- _screen_capture.start()
       |-- LiveKitVideoSource.create(source.width, source.height)
       |-- LiveKitLocalVideoTrack.create("screen", source)
       |-- LiveKitLocalParticipant.publish_track(
       |       track, {source: SOURCE_SCREENSHARE})
       |-- LiveKitVideoStream.from_track(track)
       |-- returns stream
       |
       v
ClientVoice stores stream in Client._screen_track
       |-- _voice_log("start_screen_share success")
       |
       v
AppState.set_screen_sharing(true)
       |-- is_screen_sharing = true
       |-- screen_share_changed.emit(true)
       |
       +---> voice_bar._on_screen_share_changed()
       |         |-- _update_button_visuals()
       |         |-- Share -> "Sharing" + green tint
       |
       +---> video_grid._on_video_changed()
                 |-- _rebuild()
                 |-- Client.get_screen_track() != null
                 |-- creates live VideoTile
```

### Frame Capture Loop (livekit_adapter.gd _process)

```
Every _process() tick while _screen_capture != null:
       |
       v
_screen_capture.poll()
       |-- returns true if a new frame is available
       |
       v
_screen_capture.get_image() -> Image
       |-- native screen/window pixel data
       |
       v
_local_screen_source.capture_frame(image, Time.get_ticks_usec(), 0)
       |-- pushes frame to LiveKit video source
       |-- LiveKit encodes and transmits to remote peers
```

### Stop Screen Share

```
User clicks "Sharing" button
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd)
       |-- AppState.is_screen_sharing == true
       |
       v
Client.stop_screen_share()                   (client.gd)
       |
       v
ClientVoice.stop_screen_share()              (client_voice.gd)
       |-- _voice_log("stop_screen_share")
       |-- _screen_track.close()
       |-- _screen_track = null
       |-- _voice_session.unpublish_screen()
       |
       v
LiveKitAdapter.unpublish_screen()            (livekit_adapter.gd)
       |-- _cleanup_local_screen()
       |-- _screen_capture.close() + null
       |-- unpublish_track(sid) via LocalParticipant
       |-- nulls _local_screen_pub, _local_screen_track, _local_screen_source
       |
       v
AppState.set_screen_sharing(false)
       |-- is_screen_sharing = false
       |-- screen_share_changed.emit(false)
       |
       +---> voice_bar: "Sharing" -> "Share", green tint removed
       +---> video_grid: _rebuild() removes screen tile
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
VideoGrid._on_remote_track_received()        (video_grid.gd)
       |-- _rebuild()
       |-- detects state.self_stream == true
       |-- Client.get_remote_track(uid)
       |-- tile.setup_local(remote_track, user)
       |
       v
VideoTile._process()                         (video_tile.gd)
       |-- _stream.poll()
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
       |-- _screen_capture.close() + null
       |-- nulls all local track references
       |-- room teardown handles unpublishing
       |
       v
AppState.leave_voice()
       |-- is_screen_sharing = false
       |-- voice_left.emit(old_channel)
       |
       v
VideoGrid._on_voice_left()                  (video_grid.gd)
       |-- _clear() + visible = false
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/screen_picker_dialog.gd` | Screen picker overlay: enumerates monitors/windows via `LiveKitScreenCapture`, permission check, emits `source_selected(source: Dictionary)` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: full-screen `ColorRect` backdrop with centered panel + `ScrollContainer` of source buttons |
| `scenes/sidebar/voice_bar.gd` | Share button handler: opens screen picker or stops share, visual state updates |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: `ShareBtn` in `ButtonRow` |
| `scenes/video/video_grid.gd` | Self-managing grid: rebuilds tiles from AppState signals, renders local screen share tile |
| `scenes/video/video_grid.tscn` | Video grid scene: 140px min height strip above message area |
| `scenes/video/video_tile.gd` | Renders live video via `LiveKitVideoStream.poll()` + `get_texture()` per frame |
| `scenes/video/video_tile.tscn` | Video tile scene: 160x120 min size, dark background, `TextureRect` + name bar |
| `scripts/autoload/app_state.gd` | `screen_share_changed` signal, `is_screen_sharing` state, `set_screen_sharing()` |
| `scripts/autoload/client.gd` | `start_screen_share(source)` / `stop_screen_share()` public API, `_screen_track` storage, `get_screen_track()` |
| `scripts/autoload/client_voice.gd` | `start_screen_share(source)`: publish flow + state update + voice logging; `stop_screen_share()`: cleanup flow; `_send_voice_state_update()`: gateway sync with `is_screen_sharing` flag |
| `scripts/autoload/livekit_adapter.gd` | `publish_screen(source)`: creates `LiveKitScreenCapture` + `LiveKitVideoSource` + `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`; `_process()` capture loop pushes frames via `capture_frame()`; `unpublish_screen()`; `_cleanup_local_screen()` |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState.self_stream` flag for screen share state |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` includes `self_stream` key |
| `scenes/sidebar/channels/voice_channel_item.gd` | Blue "S" indicator for participants who are screen sharing |

## Implementation Details

### Screen Picker Dialog (screen_picker_dialog.gd)

A `ColorRect` overlay that covers the full viewport with a semi-transparent backdrop. On `_ready()`, connects the close button and backdrop input handler, then checks screen capture permissions via `LiveKitScreenCapture.check_permissions()`.

**Permission check:**
- If `status == PERMISSION_ERROR`, shows an error label with the `summary` string and stops
- Otherwise, calls `_populate_sources()`

**Source enumeration** (`_populate_sources()`):
- `LiveKitScreenCapture.get_monitors()` returns an array of `{id, name, x, y, width, height, scale}` dicts
- `LiveKitScreenCapture.get_windows()` returns an array of `{id, name, x, y, width, height}` dicts
- Monitors are shown under a "Screens" section header, windows under a "Windows" section header
- Each source is presented as a button: `"Name  (WxH)"` (e.g., "DP-1  (2560x1440)")
- If no monitors or windows are found, shows "No screens or windows found"

**Source selection:**
- Each button stores the full source dictionary with an added `"_type"` key (`"monitor"` or `"window"`)
- On click, emits `source_selected(source_dict)` and self-destructs via `queue_free()`

**Dismissal:**
- Escape key via `_input()` `ui_cancel` action
- Clicking the backdrop via `gui_input` handler
- Close button in the header

### Voice Bar Share Button (voice_bar.gd)

The Share button toggles between two states:

**Starting a share:**
- Checks `AppState.is_screen_sharing` -- if false, instantiates `ScreenPickerDialog`
- Connects `source_selected` signal to `_on_screen_source_selected(source: Dictionary)`
- Adds the dialog to the scene tree root

**Stopping a share:**
- If `AppState.is_screen_sharing` is true, calls `Client.stop_screen_share()` directly -- no confirmation dialog

**Visual feedback:**
- Active state: text changes to "Sharing", green `StyleBoxFlat` overlay `(0.231, 0.647, 0.365, 0.3)` with 4px corner radius
- Inactive state: text reverts to "Share", style override removed

### Publishing Pipeline (client_voice.gd + livekit_adapter.gd)

**ClientVoice.start_screen_share(source: Dictionary):**
1. Logs the source dictionary via `_voice_log()`
2. Early-returns if not in a voice channel
3. Stops any existing screen track: `_screen_track.close()` + `unpublish_screen()`
4. Calls `_voice_session.publish_screen(source)` which returns a `LiveKitVideoStream`
5. On failure (null stream), emits `voice_error("Failed to share screen")`
6. Stores the stream in `Client._screen_track`
7. Logs success via `_voice_log()`
8. Sets `AppState.set_screen_sharing(true)`
9. Sends a gateway voice state update with all current flags

**LiveKitAdapter.publish_screen(source: Dictionary):**
1. `_cleanup_local_screen()` closes any prior capture + track
2. Determines type from `source.get("_type", "monitor")`
3. Creates capture: `LiveKitScreenCapture.create_for_monitor(source)` or `create_for_window(source)`
4. `_screen_capture.start()`
5. Creates `LiveKitVideoSource.create(source.width, source.height)` — uses actual resolution from source
6. Creates `LiveKitLocalVideoTrack.create("screen", _local_screen_source)`
7. Publishes with `SOURCE_SCREENSHARE`
8. Returns `LiveKitVideoStream.from_track(_local_screen_track)` for local preview

**Frame capture loop in `_process()`:**
- After polling remote streams and before the mic capture loop
- `_screen_capture.poll()` returns true when a new frame is available
- `_screen_capture.get_image()` returns a Godot `Image` with native pixel data
- `_local_screen_source.capture_frame(image, timestamp_us, rotation)` pushes the frame to LiveKit
- This mirrors the mic capture pattern: each `_process()` tick, read available data from the OS, then push it to the LiveKit source

### Video Grid Screen Share Tile (video_grid.gd)

During `_rebuild()`, the grid creates a local screen share tile:
- Calls `Client.get_screen_track()` -- if non-null, instantiates a `VideoTile`
- Calls `tile.setup_local(screen_track, Client.current_user)` to start live rendering
- The tile renders via `_process()` polling: `_stream.poll()` then `_stream.get_texture()`

For remote peers, the grid checks `state.get("self_stream", false)`. If true and a remote track exists via `Client.get_remote_track(uid)`, it renders a live tile; otherwise shows a placeholder with the user's initials.

### Gateway State Synchronization (client_voice.gd)

`_send_voice_state_update()` sends the current screen share state to the server via `AccordClient.update_voice_state()`, which includes `AppState.is_screen_sharing` as the `self_stream` parameter. This ensures remote participants see the blue "S" indicator in the voice channel participant list even before the video track arrives.

### Track Cleanup

Screen share tracks are cleaned up in three scenarios:

1. **User stops sharing** (`stop_screen_share()`): closes stream, unpublishes from room, closes `_screen_capture`, resets AppState
2. **User leaves voice** (`leave_voice_channel()`): closes `_screen_track` alongside camera and remote tracks
3. **Voice disconnect** (room disconnection): `LiveKitAdapter.disconnect_voice()` closes `_screen_capture` and nulls all local track references; the room teardown handles unpublishing
4. **AppState.leave_voice()**: resets `is_screen_sharing = false` as part of clearing all voice state

## Implementation Status

- [x] Screen picker dialog enumerating monitors via LiveKitScreenCapture
- [x] Window enumeration via LiveKitScreenCapture
- [x] Permission check at dialog open
- [x] Screen resolution display per source
- [x] Share button in voice bar with active/inactive visual states
- [x] Source dictionary flows through to LiveKitAdapter.publish_screen(source)
- [x] Native screen capture via LiveKitScreenCapture.create_for_monitor/create_for_window
- [x] Frame capture loop in _process() pushing frames via capture_frame()
- [x] Actual source resolution used (not hardcoded 1920x1080)
- [x] Publishing screen share track via LiveKitAdapter with SOURCE_SCREENSHARE
- [x] Local screen share preview tile in video grid
- [x] Remote screen share rendering via LiveKitVideoStream polling
- [x] AppState `screen_share_changed` signal and `is_screen_sharing` state
- [x] Gateway voice state sync with `self_stream` flag
- [x] Blue "S" indicator in voice channel participant list for screen sharers
- [x] Track cleanup on stop, voice leave, and disconnect
- [x] Escape / backdrop click / close button to dismiss screen picker
- [x] Migrate screen picker to use `LiveKitScreenCapture.get_monitors()` and `get_windows()` instead of `DisplayServer`
- [x] Add window sharing tab using `LiveKitScreenCapture.get_windows()`
- [x] Add permission check via `LiveKitScreenCapture.check_permissions()` before showing picker
- [x] Voice logging in start_screen_share and stop_screen_share
- [ ] Use `LiveKitScreenCapture` for actual frame capture (`start()` / `poll()` / `get_image()`) piped to `LiveKitVideoSource.capture_frame()`
- [ ] Use actual monitor/window resolution from `LiveKitScreenCapture` source metadata instead of hardcoded 1920x1080
- [ ] Screen share spotlight layout (large dominant view)
- [ ] Screen share audio (system audio capture alongside video)
- [ ] Mini PiP preview when navigating away from voice channel

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Hardcoded 1920x1080 resolution | Medium | `LiveKitVideoSource.create(1920, 1080)` ignores the actual selected screen's resolution. `LiveKitScreenCapture.get_monitors()` returns `width`/`height`/`scale` per monitor, which should be used for `LiveKitVideoSource.create()` |
| No actual frame capture | High | `LiveKitVideoSource` is created but no frames are ever pushed to it -- the screen share track publishes blank video. Use `LiveKitScreenCapture.start()` + `poll()` + `get_image()` in `_process()` to pipe frames to `LiveKitVideoSource.capture_frame()` |
| No spotlight layout for screen shares | Medium | `video_grid.gd` treats screen share tiles identically to camera tiles in a uniform `GridContainer`. Discord shows screen shares as a large dominant view with participants as a small strip. Covered in the Video Chat user flow |
| No screen share audio | Low | Only the video track is published. System audio capture is not included in the screen share. Would require a separate `LiveKitAudioSource` capturing desktop audio |
| Screen picker shows no thumbnails | Low | Each source is a text-only button. No preview thumbnail of the screen/window content. `LiveKitScreenCapture.screenshot()` can provide preview thumbnails |
| No confirmation before sharing | Low | Clicking a source immediately starts sharing with no confirmation step. Discord shows a preview before the user commits |
