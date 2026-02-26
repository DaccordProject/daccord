# Screen Sharing

## Overview

Screen sharing in daccord lets users broadcast their display to other participants in a voice channel. The flow uses the godot-livekit GDExtension to publish a `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`, and a screen picker dialog that enumerates available screens via Godot's `DisplayServer`. The published stream renders both as a local preview tile and as a live remote tile for other participants in the voice channel.

**Available but not yet integrated:** The godot-livekit addon now provides `LiveKitScreenCapture` -- a native screen/window capture class backed by the **frametap** library. It supports enumerating monitors (`get_monitors()`) and individual application windows (`get_windows()`), permission checking (`check_permissions()`), and continuous frame capture (`start()` / `poll()` / `get_image()` / `get_texture()`). This class can replace the current `DisplayServer`-based enumeration and fill the missing frame capture gap, and enables window-level sharing. See the Gaps section for integration details.

## User Steps

1. User joins a voice channel (prerequisite -- must already be in voice)
2. User clicks the **Share** button in the voice bar
3. A full-screen overlay appears listing available screens with their resolutions (e.g., "Screen 1 (1920x1080)")
4. User clicks a screen to select it -- the overlay closes automatically
5. The Share button changes to **Sharing** with a green tint, indicating an active share
6. A video tile showing the local screen share preview appears in the video grid above the message area
7. Remote participants see a blue "S" indicator next to the user's name in the voice channel participant list
8. Remote participants see the shared screen rendered as a live video tile in their video grid
9. User clicks the **Sharing** button again to stop -- the tile disappears and the button reverts to "Share"

## Signal Flow

### Start Screen Share

```
User clicks "Share" button
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd:65)
       |-- AppState.is_screen_sharing == false
       |
       v
ScreenPickerDialog instantiated               (voice_bar.gd:69)
       |-- source_selected.connect(_on_screen_source_selected)
       |-- added to scene tree root
       |
       v
ScreenPickerDialog._populate_screens()        (screen_picker_dialog.gd:21)
       |-- DisplayServer.get_screen_count()
       |-- DisplayServer.screen_get_size(i) for each screen
       |-- creates Button per screen with "Screen N (WxH)"
       |
User clicks a screen button
       |
       v
source_selected.emit("screen", i)             (screen_picker_dialog.gd:44)
       |-- dialog self-destructs via queue_free()
       |
       v
voice_bar._on_screen_source_selected()        (voice_bar.gd:73)
       |
       v
Client.start_screen_share(source_type, id)    (client.gd:510)
       |
       v
ClientVoice.start_screen_share()              (client_voice.gd:226)
       |-- closes existing _screen_track if any  (line 232)
       |-- calls _voice_session.publish_screen()
       |
       v
LiveKitAdapter.publish_screen()               (livekit_adapter.gd:142)
       |-- LiveKitVideoSource.create(1920, 1080)
       |-- LiveKitLocalVideoTrack.create("screen", source)
       |-- LiveKitLocalParticipant.publish_track(
       |       track, {source: SOURCE_SCREENSHARE})
       |-- LiveKitVideoStream.from_track(track)
       |-- returns stream
       |
       v
ClientVoice stores stream in Client._screen_track  (client_voice.gd:240)
       |
       v
AppState.set_screen_sharing(true)             (app_state.gd:288)
       |-- is_screen_sharing = true
       |-- screen_share_changed.emit(true)
       |
       +---> voice_bar._on_screen_share_changed()
       |         |-- _update_button_visuals()
       |         |-- Share -> "Sharing" + green tint  (voice_bar.gd:164)
       |
       +---> video_grid._on_video_changed()
                 |-- _rebuild()                       (video_grid.gd:73)
                 |-- Client.get_screen_track() != null
                 |-- creates live VideoTile           (video_grid.gd:88-97)
```

### Stop Screen Share

```
User clicks "Sharing" button
       |
       v
voice_bar._on_share_pressed()                (voice_bar.gd:65)
       |-- AppState.is_screen_sharing == true
       |
       v
Client.stop_screen_share()                   (client.gd:515)
       |
       v
ClientVoice.stop_screen_share()              (client_voice.gd:244)
       |-- _screen_track.close()             (line 246)
       |-- _screen_track = null              (line 247)
       |-- _voice_session.unpublish_screen() (line 248)
       |
       v
LiveKitAdapter.unpublish_screen()            (livekit_adapter.gd:162)
       |-- _cleanup_local_screen()           (line 397)
       |-- unpublish_track(sid) via LocalParticipant
       |-- nulls _local_screen_pub, _local_screen_track, _local_screen_source
       |
       v
AppState.set_screen_sharing(false)           (app_state.gd:288)
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
LiveKitAdapter._on_track_subscribed()        (livekit_adapter.gd:243)
       |-- track.get_kind() == KIND_VIDEO
       |-- LiveKitVideoStream.from_track(track)
       |-- _remote_video[identity] = stream
       |-- track_received.emit(uid, stream)
       |
       v
ClientVoice.on_track_received()              (client_voice.gd:322)
       |-- closes previous track for same peer
       |-- Client._remote_tracks[user_id] = stream
       |-- AppState.remote_track_received.emit(uid, stream)
       |
       v
VideoGrid._on_remote_track_received()        (video_grid.gd:44)
       |-- _rebuild()
       |-- detects state.self_stream == true  (line 113)
       |-- Client.get_remote_track(uid)       (line 127)
       |-- tile.setup_local(remote_track, user) (line 130)
       |
       v
VideoTile._process()                         (video_tile.gd:68)
       |-- _stream.poll()
       |-- _stream.get_texture() -> ImageTexture
       |-- video_rect.texture = tex
```

### Cleanup on Voice Disconnect

```
User clicks Disconnect (or force-disconnected)
       |
       v
ClientVoice.leave_voice_channel()            (client_voice.gd:127)
       |-- _screen_track.close()             (line 135)
       |-- _screen_track = null              (line 137)
       |-- all remote tracks closed          (lines 139-143)
       |-- _voice_session.disconnect_voice()
       |
       v
AppState.leave_voice()                       (app_state.gd:265)
       |-- is_screen_sharing = false         (line 272)
       |-- voice_left.emit(old_channel)
       |
       v
VideoGrid._on_voice_left()                  (video_grid.gd:40)
       |-- _clear() + visible = false
```

## Key Files

| File | Role |
|------|------|
| `scenes/sidebar/screen_picker_dialog.gd` | Screen picker overlay: enumerates screens via `DisplayServer`, emits `source_selected(source_type, source_id)` |
| `scenes/sidebar/screen_picker_dialog.tscn` | Screen picker scene: full-screen `ColorRect` backdrop with centered panel + `ScrollContainer` of source buttons |
| `scenes/sidebar/voice_bar.gd` | Share button handler: opens screen picker or stops share (lines 65-76), visual state updates (lines 163-175) |
| `scenes/sidebar/voice_bar.tscn` | Voice bar scene: `ShareBtn` in `ButtonRow` |
| `scenes/video/video_grid.gd` | Self-managing grid: rebuilds tiles from AppState signals, renders local screen share tile (lines 87-97) |
| `scenes/video/video_grid.tscn` | Video grid scene: 140px min height strip above message area |
| `scenes/video/video_tile.gd` | Renders live video via `LiveKitVideoStream.poll()` + `get_texture()` per frame (lines 68-74) |
| `scenes/video/video_tile.tscn` | Video tile scene: 160x120 min size, dark background, `TextureRect` + name bar |
| `scripts/autoload/app_state.gd` | `screen_share_changed` signal (line 66), `is_screen_sharing` state (line 165), `set_screen_sharing()` (line 288) |
| `scripts/autoload/client.gd` | `start_screen_share()` / `stop_screen_share()` public API (lines 510-516), `_screen_track` storage (line 127), `get_screen_track()` (line 521) |
| `scripts/autoload/client_voice.gd` | `start_screen_share()` (line 226): publish flow + state update; `stop_screen_share()` (line 244): cleanup flow; `_send_voice_state_update()` (line 252): gateway sync with `is_screen_sharing` flag |
| `scripts/autoload/livekit_adapter.gd` | `publish_screen()` (line 142): creates `LiveKitVideoSource` + `LiveKitLocalVideoTrack` with `SOURCE_SCREENSHARE`; `unpublish_screen()` (line 162); `_cleanup_local_screen()` (line 397) |
| `addons/accordkit/models/voice_state.gd` | `AccordVoiceState.self_stream` flag for screen share state |
| `scripts/autoload/client_models.gd` | `voice_state_to_dict()` includes `self_stream` key |
| `scenes/sidebar/channels/voice_channel_item.gd` | Blue "S" indicator for participants who are screen sharing |

## Implementation Details

### Screen Picker Dialog (screen_picker_dialog.gd)

A `ColorRect` overlay that covers the full viewport with a semi-transparent backdrop. On `_ready()` (line 8), connects the close button and backdrop input handler, then calls `_populate_screens()`.

**Screen enumeration** (lines 21-32):
- `DisplayServer.get_screen_count()` returns the number of available screens
- For each screen, `DisplayServer.screen_get_size(i)` returns the resolution as `Vector2i`
- Each screen is presented as a button: `"Screen N (WxH)"` (e.g., "Screen 1 (1920x1080)")
- If no screens are found, shows an empty label: "No screens found" (line 25)

**Source selection** (lines 34-47):
- Each button's `pressed` signal emits `source_selected("screen", index)` (line 44)
- The dialog self-destructs immediately after selection via `queue_free()` (line 45)

**Dismissal** (lines 13-19, 62-63):
- Escape key via `_input()` `ui_cancel` action (line 14)
- Clicking the backdrop via `gui_input` handler (line 18)
- Close button in the header (line 9)

### Voice Bar Share Button (voice_bar.gd)

The Share button at line 14 toggles between two states:

**Starting a share** (lines 65-71):
- Checks `AppState.is_screen_sharing` -- if false, instantiates `ScreenPickerDialog`
- Connects `source_selected` signal to `_on_screen_source_selected`
- Adds the dialog to the scene tree root

**Stopping a share** (lines 66-67):
- If `AppState.is_screen_sharing` is true, calls `Client.stop_screen_share()` directly -- no confirmation dialog

**Visual feedback** (lines 163-175):
- Active state: text changes to "Sharing", green `StyleBoxFlat` overlay `(0.231, 0.647, 0.365, 0.3)` with 4px corner radius
- Inactive state: text reverts to "Share", style override removed

### Publishing Pipeline (client_voice.gd + livekit_adapter.gd)

**ClientVoice.start_screen_share()** (lines 226-242):
1. Early-returns if not in a voice channel (line 229)
2. Stops any existing screen track: `_screen_track.close()` + `unpublish_screen()` (lines 232-235)
3. Calls `_voice_session.publish_screen()` which returns a `LiveKitVideoStream` (line 236)
4. On failure (null stream), emits `voice_error("Failed to share screen")` (line 238)
5. Stores the stream in `Client._screen_track` (line 240)
6. Sets `AppState.set_screen_sharing(true)` (line 241)
7. Sends a gateway voice state update with all current flags (line 242)

**LiveKitAdapter.publish_screen()** (lines 142-160):
1. Creates a `LiveKitVideoSource` at hardcoded **1920x1080** (line 147)
2. Creates `LiveKitLocalVideoTrack` named `"screen"` backed by that source (lines 148-149)
3. Gets the `LiveKitLocalParticipant` from the room (line 151)
4. Publishes the track with `{"source": LiveKitTrack.SOURCE_SCREENSHARE}` (lines 154-155)
5. Creates and returns a `LiveKitVideoStream.from_track()` for local preview rendering (lines 157-159)

**Note:** The `source_type` and `source_id` parameters from the screen picker are currently **unused** -- `publish_screen()` takes no arguments and always publishes the default screen at 1920x1080. This is a known limitation.

### Video Grid Screen Share Tile (video_grid.gd)

During `_rebuild()` (lines 73-137), the grid creates a local screen share tile at lines 87-97:
- Calls `Client.get_screen_track()` -- if non-null, instantiates a `VideoTile`
- Calls `tile.setup_local(screen_track, Client.current_user)` to start live rendering
- The tile renders via `_process()` polling: `_stream.poll()` then `_stream.get_texture()`

For remote peers, the grid checks `state.get("self_stream", false)` at line 113. If true and a remote track exists via `Client.get_remote_track(uid)`, it renders a live tile; otherwise shows a placeholder with the user's initials.

### Gateway State Synchronization (client_voice.gd)

`_send_voice_state_update()` (lines 252-266) sends the current screen share state to the server via `AccordClient.update_voice_state()`, which includes `AppState.is_screen_sharing` as the `self_stream` parameter (line 265). This ensures remote participants see the blue "S" indicator in the voice channel participant list even before the video track arrives.

### Track Cleanup

Screen share tracks are cleaned up in three scenarios:

1. **User stops sharing** (`stop_screen_share()`, line 244): closes stream, unpublishes from room, resets AppState
2. **User leaves voice** (`leave_voice_channel()`, lines 135-137): closes `_screen_track` alongside camera and remote tracks
3. **Voice disconnect** (room disconnection): `LiveKitAdapter.disconnect_voice()` (line 74) nulls all local track references; the room teardown handles unpublishing
4. **AppState.leave_voice()** (line 265): resets `is_screen_sharing = false` as part of clearing all voice state

## Implementation Status

- [x] Screen picker dialog enumerating screens via DisplayServer
- [x] Screen resolution display per screen
- [x] Share button in voice bar with active/inactive visual states
- [x] Publishing screen share track via LiveKitAdapter with SOURCE_SCREENSHARE
- [x] Local screen share preview tile in video grid
- [x] Remote screen share rendering via LiveKitVideoStream polling
- [x] AppState `screen_share_changed` signal and `is_screen_sharing` state
- [x] Gateway voice state sync with `self_stream` flag
- [x] Blue "S" indicator in voice channel participant list for screen sharers
- [x] Track cleanup on stop, voice leave, and disconnect
- [x] Escape / backdrop click / close button to dismiss screen picker
- [ ] Migrate screen picker to use `LiveKitScreenCapture.get_monitors()` and `get_windows()` instead of `DisplayServer`
- [ ] Add window sharing tab using `LiveKitScreenCapture.get_windows()` and `create_for_window()`
- [ ] Add permission check via `LiveKitScreenCapture.check_permissions()` before showing picker
- [ ] Use `LiveKitScreenCapture` for actual frame capture (`start()` / `poll()` / `get_image()`) piped to `LiveKitVideoSource.capture_frame()`
- [ ] Use actual monitor/window resolution from `LiveKitScreenCapture` source metadata instead of hardcoded 1920x1080
- [ ] Screen share spotlight layout (large dominant view)
- [ ] Screen share audio (system audio capture alongside video)
- [ ] Mini PiP preview when navigating away from voice channel

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| Source selection parameters unused | High | `start_screen_share(source_type, source_id)` at `client_voice.gd:226` receives `_source_type` and `_source_id` (underscore-prefixed = unused). `publish_screen()` at `livekit_adapter.gd:142` takes no arguments and always creates a 1920x1080 source. The selected screen index is discarded. **Now unblocked:** `LiveKitScreenCapture.create_for_monitor()` and `create_for_window()` accept the source dict directly |
| Hardcoded 1920x1080 resolution | Medium | `LiveKitVideoSource.create(1920, 1080)` at `livekit_adapter.gd:147` ignores the actual selected screen's resolution. **Now unblocked:** `LiveKitScreenCapture.get_monitors()` returns `width`/`height`/`scale` per monitor, which should be used for `LiveKitVideoSource.create()` |
| No window sharing | Medium | `screen_picker_dialog.gd` only enumerates screens via `DisplayServer.get_screen_count()` (line 23). **Now unblocked:** `LiveKitScreenCapture.get_windows()` returns all application windows with `id`, `name`, `x`, `y`, `width`, `height`. Use `LiveKitScreenCapture.create_for_window(window_dict)` to capture a specific window |
| No actual frame capture | High | `LiveKitVideoSource` is created but no frames are ever pushed to it -- the screen share track publishes blank video. **Now unblocked:** `LiveKitScreenCapture.start()` + `poll()` + `get_image()` in `_process()` provides continuous frame capture that can be piped to `LiveKitVideoSource.capture_frame()` |
| No permission check | Medium | Screen sharing starts without checking OS-level permissions (macOS requires Screen Recording permission). **Now unblocked:** `LiveKitScreenCapture.check_permissions()` returns `status` (`PERMISSION_OK`, `PERMISSION_WARNING`, `PERMISSION_ERROR`), `summary`, and `details` |
| No spotlight layout for screen shares | Medium | `video_grid.gd:73` treats screen share tiles identically to camera tiles in a uniform `GridContainer`. Discord shows screen shares as a large dominant view with participants as a small strip. Covered in the Video Chat user flow |
| No screen share audio | Low | Only the video track is published. System audio capture is not included in the screen share. Would require a separate `LiveKitAudioSource` capturing desktop audio |
| Screen picker shows no thumbnails | Low | Each screen is a text-only button (`"Screen N (WxH)"`). No preview thumbnail of the screen content. **Now unblocked:** `LiveKitScreenCapture.screenshot()` can take a one-shot screenshot of a monitor or window for use as a preview thumbnail in the picker |
| No confirmation before sharing | Low | Clicking a screen immediately starts sharing with no confirmation step. Discord shows a preview before the user commits |
