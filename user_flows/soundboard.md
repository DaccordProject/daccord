# Soundboard

Last touched: 2026-02-19

## Overview

A soundboard allows users to play short audio clips into a voice channel for all participants to hear. Users manage a server-wide collection of sounds and trigger them via a UI panel while connected to a voice channel. The server (accordserver) provides full REST API endpoints for soundboard CRUD and playback, a database table for sound metadata, audio file storage on disk, gateway events for real-time updates, and permission flags (`manage_soundboard`, `use_soundboard`). The daccord client provides a management dialog for admins, an in-voice trigger panel, and client-side audio playback via `SoundManager`.

## User Steps

1. User joins a voice channel
2. User clicks the "SFX" button in the voice bar (visible if user has `use_soundboard` permission)
3. Soundboard panel opens with a searchable list of sounds (fetched via `GET /spaces/{id}/soundboard`)
4. User clicks a sound to play it (triggers `POST /spaces/{id}/soundboard/{sound_id}/play`)
5. Server broadcasts `soundboard.play` gateway event with user_id to space members
6. All participants in voice hear the sound (client-side playback via `SoundManager`)
7. Users with `manage_soundboard` permission can upload, rename, adjust volume, or delete sounds via the management dialog (banner menu → Soundboard)

### Sound Management (Admin)

1. Admin opens the soundboard management dialog
2. Admin clicks "Add Sound" and selects an audio file
3. File is uploaded as a base64 data URI via `POST /spaces/{id}/soundboard` with `{name, audio, volume?}`
4. Server stores the audio file to disk, creates a database record, and broadcasts `soundboard.create` gateway event
5. Admin can rename sounds or adjust volume via `PATCH /spaces/{id}/soundboard/{sound_id}`
6. Admin can delete sounds via `DELETE /spaces/{id}/soundboard/{sound_id}`

## Signal Flow

```
soundboard_panel.gd          Client              AccordKit         SoundManager
     |                           |                    |                    |
     |-- play_sound(gid, sid) -->|                    |                    |
     |                           |-- POST /spaces/   |                    |
     |                           |   {id}/soundboard/ |                    |
     |                           |   {sound_id}/play  |                    |
     |                           |                    |                    |
     |                           |<-- gateway event --|                    |
     |                           |   soundboard.play  |                    |
     |                           |                    |                    |
     |              AppState.soundboard_played(gid, sid, uid) ----------->|
     |                           |                    |   download audio   |
     |                           |                    |   decode & cache   |
     |                           |                    |   play via SFX bus |

soundboard_mgmt.gd           Client              AccordKit
     |                           |                    |
     |-- upload_sound() -------->|                    |
     |                           |-- POST /spaces/    |
     |                           |   {id}/soundboard  |
     |                           |                    |<-- gateway event
     |                           |                    |   soundboard.create
     |                           |                    |
     |-- delete_sound() -------->|                    |
     |                           |-- DELETE /spaces/  |
     |                           |   {id}/soundboard/ |
     |                           |   {sound_id}       |
     |                           |                    |<-- gateway event
     |                           |                    |   soundboard.delete
```

## Key Files

| File | Role |
|------|------|
| `addons/accordkit/models/sound.gd` | `AccordSound` model with `from_dict()` / `to_dict()` |
| `addons/accordkit/rest/endpoints/soundboard_api.gd` | `SoundboardApi` REST class (list/fetch/create/update/delete/play) |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway signals and dispatch for `soundboard.*` events |
| `addons/accordkit/core/accord_client.gd` | Exposes `soundboard: SoundboardApi` and forwards gateway signals |
| `addons/accordkit/models/permission.gd` | `MANAGE_SOUNDBOARD` and `USE_SOUNDBOARD` constants |
| `addons/accordkit/utils/cdn.gd` | `AccordCDN.sound()` URL helper |
| `scenes/admin/soundboard_management_dialog.gd/.tscn` | Soundboard management dialog (upload, rename, volume, delete, search) |
| `scenes/admin/sound_row.gd/.tscn` | Sound row component with play, rename, volume, delete controls |
| `scenes/soundboard/soundboard_panel.gd/.tscn` | In-voice soundboard panel (sound trigger buttons, search) |
| `scenes/sidebar/voice_bar.gd/.tscn` | Voice bar with SFX button that toggles soundboard panel |
| `scenes/sidebar/channels/banner.gd` | Banner dropdown with "Soundboard" menu item |
| `scripts/autoload/app_state.gd` | `soundboard_updated`, `soundboard_played` signals |
| `scripts/autoload/client.gd` | Routes soundboard API calls, wires gateway signals |
| `scripts/autoload/client_admin.gd` | Soundboard CRUD wrappers with AppState signal emissions |
| `scripts/autoload/client_gateway.gd` | Soundboard gateway event handlers |
| `scripts/autoload/client_models.gd` | `sound_to_dict()` converter |

## Implementation Details

### Current State

The server provides a complete soundboard API. AccordKit and the daccord client support the full soundboard pipeline: CRUD management, in-voice trigger panel, and client-side audio playback. When a `soundboard.play` gateway event arrives, `SoundManager` downloads the audio file, decodes it (OGG/MP3/WAV), caches it, and plays it locally via a dedicated `AudioStreamPlayer` on the SFX bus.

- **accordserver** -- Full REST API with CRUD endpoints, play trigger, audio file storage, gateway events, and permission checks. Database table `soundboard_sounds` stores metadata (id, space_id, name, audio_path, audio_content_type, audio_size, volume, creator_id, timestamps)
- **AccordKit** -- `AccordSound` model, `SoundboardApi` REST class (list/fetch/create/update/delete/play), gateway event handling for `soundboard.*` events, `AccordCDN.sound()` URL helper, permission constants (`MANAGE_SOUNDBOARD`, `USE_SOUNDBOARD`)
- **daccord client** -- Soundboard management dialog (upload, rename, volume, delete, search/filter), sound row component, AppState signals (`soundboard_updated`, `soundboard_played`), Client/ClientAdmin/ClientGateway/ClientModels integration, banner menu entry for users with soundboard permissions
- **LiveKit** -- Provides microphone capture and WebRTC peer connections. Audio file playback for soundboard is handled client-side by `SoundManager`, not via LiveKit
- **Voice join/leave UI** -- Fully implemented (see `voice_channels.md`). Users can join/leave voice channels and the soundboard panel appears in the voice bar

### Server API (accordserver -- implemented)

**Database schema** (`soundboard_sounds` table):
- `id` TEXT PRIMARY KEY (snowflake)
- `space_id` TEXT NOT NULL (references spaces)
- `name` TEXT NOT NULL
- `audio_path` TEXT (file path on disk)
- `audio_content_type` TEXT
- `audio_size` INTEGER
- `volume` REAL NOT NULL DEFAULT 1.0 (clamped 0.0-2.0)
- `creator_id` TEXT (references users)
- `created_at` TEXT NOT NULL
- `updated_at` TEXT NOT NULL

**REST endpoints**:
- `GET /spaces/{space_id}/soundboard` -- List sounds (requires space membership)
- `GET /spaces/{space_id}/soundboard/{sound_id}` -- Fetch single sound (requires membership)
- `POST /spaces/{space_id}/soundboard` -- Create sound (requires `manage_soundboard` permission). Body: `{name: String, audio: String (base64 data URI), volume?: f64}`
- `PATCH /spaces/{space_id}/soundboard/{sound_id}` -- Update name/volume (requires `manage_soundboard`). Body: `{name?: String, volume?: f64}`
- `DELETE /spaces/{space_id}/soundboard/{sound_id}` -- Delete sound and file (requires `manage_soundboard`)
- `POST /spaces/{space_id}/soundboard/{sound_id}/play` -- Trigger playback (requires `use_soundboard`)

**Gateway events** (broadcast to space members):
- `soundboard.create` -- New sound uploaded (full sound object in payload)
- `soundboard.update` -- Sound metadata changed
- `soundboard.delete` -- Sound removed
- `soundboard.play` -- Sound triggered by a user (includes `user_id`)

**Response model**:
```json
{
  "id": "snowflake",
  "name": "airhorn",
  "audio_url": "/sounds/snowflake_id.ogg",
  "volume": 1.0,
  "creator_id": "snowflake",
  "created_at": "2026-01-15T12:00:00Z",
  "updated_at": "2026-01-15T12:00:00Z"
}
```

**Permissions**: `manage_soundboard` (create/update/delete), `use_soundboard` (play trigger)

### Required AccordKit Work

1. **New model**: `AccordSound` (id, name, audio_url, volume, creator_id, created_at, updated_at) with `from_dict()` and `to_dict()`
2. **New API class**: `SoundboardApi` with `list()`, `fetch()`, `create()`, `update()`, `delete()`, `play()` methods matching the REST endpoints
3. **Gateway events**: Handle `soundboard.create`, `soundboard.update`, `soundboard.delete`, `soundboard.play` in `gateway_socket.gd`
4. **AccordClient**: Expose `soundboard: SoundboardApi` property, add `soundboard_create`, `soundboard_update`, `soundboard_delete`, `soundboard_play` signals
5. **CDN helper**: Add `AccordCDN.sound()` URL builder for audio file URLs

### Required LiveKit Work

1. **Audio file decoding** -- Load and decode audio files (OGG, MP3, WAV)
2. **Audio mixing** -- Mix decoded audio with microphone input into the outgoing WebRTC stream, OR play audio locally and send via a separate audio track
3. **Alternative**: If server-side mixing is used, LiveKit only needs to play received audio (which it may already handle via `track_received` on `AccordPeerConnection`)

### Required Client Work

1. **Soundboard panel scene** (`scenes/soundboard/soundboard_panel.tscn`) -- Grid of sound buttons, search/filter, volume slider
2. **Sound management dialog** (`scenes/admin/soundboard_management_dialog.tscn`) -- Upload, rename, delete sounds (admin UI)
3. **AppState signals** -- `sound_play_requested`, `sound_played`, `soundboard_updated`
4. **ClientModels** -- `sound_to_dict()` converter for `AccordSound` -> UI dictionary shape
5. **ClientAdmin** -- Soundboard CRUD wrappers with AppState signal emissions
6. **Client integration** -- Route soundboard API calls via `Client.gd`, connect gateway signals
7. **Voice controls integration** -- Soundboard button only visible/enabled when connected to a voice channel

### Architecture Decision: Server-Side vs Client-Side Mixing

| Approach | Pros | Cons |
|----------|------|------|
| **Server-side mixing** | Consistent playback for all participants, no client download needed, lower client complexity | Requires SFU changes, higher server CPU usage, latency |
| **Client-side mixing** | Simpler server implementation, each client controls its own volume | Requires audio download, playback timing may differ across clients, LiveKit needs audio file playback |

## Implementation Status

- [x] Server database table (`soundboard_sounds`)
- [x] Server REST endpoints for soundboard CRUD
- [x] Server play trigger endpoint (`POST .../play`)
- [x] Server gateway events (`soundboard.create`, `soundboard.update`, `soundboard.delete`, `soundboard.play`)
- [x] Server audio file storage (base64 upload, disk storage)
- [x] Server permission checks (`manage_soundboard`, `use_soundboard`)
- [x] AccordKit soundboard model (`AccordSound`)
- [x] AccordKit soundboard API class (`SoundboardApi`)
- [x] AccordKit gateway event handling for `soundboard.*`
- [x] AccordKit CDN helper for sound URLs
- [x] Client-side audio playback via SoundManager (downloads, decodes, caches, plays on `soundboard_played` gateway event)
- [x] Client soundboard panel UI (in-voice playback panel -- separate from admin dialog)
- [x] Client sound management dialog (admin)
- [x] Client AppState signals for soundboard
- [x] Client.gd / ClientAdmin soundboard API routing and gateway handling
- [x] ClientModels `sound_to_dict()` converter
- [x] Voice join/leave UI (implemented -- see `voice_channels.md`)

## Tasks

### SOUND-1: No server-side audio mixing
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** audio, gateway, voice
- **Notes:** Audio is played client-side when receiving the `soundboard.play` gateway event; server-side SFU mixing is not implemented and may not be needed

### SOUND-2: No personal soundboard
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** audio
- **Notes:** Design only covers server-wide sounds; personal/user-level soundboards are not planned
