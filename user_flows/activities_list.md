# Activities List

## Overview
Activities (server plugins with type "activity") currently live inside voice channels — they are launched from voice channel context menus and shown as pending banners in the video grid. This flow separates activities into their own dedicated section in the channel list sidebar, so users can browse, join lobbies, and optionally join voice without first entering a voice channel.

## User Steps
1. User navigates to a space that has installed activity plugins.
2. When one or more activity sessions are active (state "lobby" or "running"), an **Activities** section appears in the channel list below the regular channels.
3. Each row in the Activities section shows:
   - The activity name (from plugin manifest)
   - Session state badge ("Lobby" or "In Progress")
   - Participant count / max participants
   - **Join Lobby** button (enabled when state is "lobby" and max participants not reached)
   - **Join Voice** button (visible only when the host user is in a voice channel)
4. User clicks **Join Lobby** to join the activity session as a player (downloads the plugin runtime, enters the lobby).
5. User clicks **Join Voice** to join the same voice channel as the host, then auto-join the activity.
6. The Activities section updates in real time as sessions start, transition to "running", gain/lose participants, or end.
7. When no active sessions remain, the Activities section disappears.

## Signal Flow
```
Gateway plugin_session_state event
  |
  v
ClientGatewayEvents.on_plugin_session_state()
  |
  v
ClientPlugins.on_plugin_session_state()
  |
  +---> Updates _space_sessions cache (line 575)
  +---> AppState.active_sessions_updated.emit(space_id) (line 586)
  +---> AppState.activity_session_state_changed(plugin_id, state)
  +---> AppState.activity_available(plugin_id, channel_id, session_id)
  +---> AppState.activity_participants_updated(session_id, participants)
          |
          v
        ActivitiesSection._on_active_sessions_updated(space_id)
          |
          v
        ActivitiesSection.refresh() -> rebuilds rows from _space_sessions
          |
          +---> For each session: ActivityRow.setup(session_data, manifest)
                  |
                  +---> Join Lobby button -> channel_list._on_join_lobby()
                  |       -> sets pending activity state
                  |       -> auto-joins voice if needed
                  |       -> calls Client.plugins.join_activity()
                  +---> Join Voice button -> channel_list._on_join_voice()
                          -> Client.join_voice_channel()

Voice state updates:
  Gateway voice_state_update
    -> AppState.voice_state_updated(channel_id)
    -> ActivitiesSection._on_voice_state_updated(channel_id)
    -> Each ActivityRow.update_voice_state()
    -> Updates "Join Voice" button visibility per row
```

## Key Files
| File | Role |
|------|------|
| `scripts/client/client_plugins.gd` | Activity lifecycle, session management, plugin cache, space-level session cache (`_space_sessions`, line 25) |
| `scripts/client/client_gateway_events.gd` | Routes gateway plugin/voice events to Client (line 166) |
| `scripts/autoload/app_state.gd` | Signal bus: activity signals (lines 206-222), `active_sessions_updated` (line 222) |
| `scripts/autoload/client.gd` | Voice state cache, `get_voice_users()` (line 534) |
| `scenes/sidebar/channels/channel_list.gd` | Channel list population, activities section injection (line 220), join lobby/voice handlers (lines 377-415) |
| `scenes/sidebar/channels/activities_section.gd` | Collapsible "ACTIVITIES" section with real-time signal wiring |
| `scenes/sidebar/channels/activities_section.tscn` | Activities section scene (header + row container) |
| `scenes/sidebar/channels/activity_row.gd` | Individual activity row: name, state badge, participant count, Join Lobby/Voice buttons |
| `scenes/sidebar/channels/activity_row.tscn` | Activity row scene layout |
| `scenes/sidebar/channels/voice_channel_item.gd` | Existing voice channel UI (reference for participant display) |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | `get_channel_sessions()` (line 51), `get_space_sessions()` (line 59) |
| `addons/accordkit/models/plugin_manifest.gd` | Plugin metadata: `lobby`, `max_participants`, `max_spectators` |
| `scripts/client/client_voice.gd` | Voice channel join/leave |

## Implementation Details

### Activities Section in Channel List

A collapsible **Activities** section is injected into `channel_list.gd`'s `load_space()` method (line 220), appended after all channel categories. It renders when there are active sessions in any voice channel within the current space.

**Data source:** The section uses a space-level session cache (`ClientPlugins._space_sessions`, line 25). On load, `fetch_space_sessions()` (line 89) calls `GET /spaces/{space_id}/sessions/active` (implemented in accordserver `routes/plugins.rs`). A per-channel polling fallback exists via `_fetch_space_sessions_fallback()` (line 114) for older server versions.

**Session data shape** (returned by `get_channel_sessions`, line 51):
```gdscript
{
    "id": String,           # session_id
    "plugin_id": String,    # which plugin
    "channel_id": String,   # which voice channel
    "state": String,        # "lobby" | "running" | "ended"
    "host_user_id": String, # who started it
    "participants": [       # array of participant dicts
        {"user_id": String, "role": String}  # "player" | "spectator"
    ]
}
```

### Activities Section UI (`activities_section.gd`)

- **Header row:** Collapsible "ACTIVITIES" label styled like category headers (font size 11, muted color, chevron icon)
- **Activity rows:** One per active session via `ActivityRowScene`, each containing:
  - Plugin icon (default gamepad icon from `assets/theme/icons/rocket.svg`)
  - Activity name (from `manifest.name`)
  - State badge: "Lobby" (green/success color) or "In Progress" (yellow/warning color)
  - Participant count: `"{current}/{max}"` using `participants.size()` and `manifest.max_participants` (0 = unlimited, show as `"{current}"`)
  - **Join Lobby** button: Disabled when `state == "running"` or at max capacity
  - **Join Voice** button: Visible only when the host user appears in the voice state cache
- **Collapse toggle:** Hides/shows row container, shows count label when collapsed

### Real-Time Updates

The activities section stays current by listening to these signals:

| Signal | Handler | Update |
|--------|---------|--------|
| `AppState.active_sessions_updated(space_id)` | `_on_active_sessions_updated` | Full refresh from cache |
| `AppState.activity_session_state_changed(plugin_id, state)` | `_on_session_state_changed` | Refresh (updates badge, button state) |
| `AppState.activity_participants_updated(session_id, participants)` | `_on_participants_updated` | Update participant count on specific row |
| `AppState.activity_ended(plugin_id)` | `_on_activity_ended` | Refresh (removes ended sessions) |
| `AppState.voice_state_updated(channel_id)` | `_on_voice_state_updated` | Toggle Join Voice button per row |
| `AppState.voice_joined(channel_id)` | `_on_voice_changed` | Toggle Join Voice button per row |
| `AppState.voice_left(channel_id, intentional)` | `_on_voice_changed` | Toggle Join Voice button per row |

### Space-Level Session Cache

`ClientPlugins._space_sessions` (line 25) is a `Dictionary` mapping `space_id -> { session_id -> session_dict }`. Updated by:

- `on_plugin_session_state()` (line 557) — adds/updates/removes sessions on gateway events, regardless of whether the local user is in the voice channel
- `fetch_space_sessions()` (line 89) — pre-fetches active sessions for a space on initial load
- `_fetch_space_sessions_fallback()` (line 114) — per-channel polling fallback when the server endpoint is unavailable

The gateway handler resolves `space_id` from the event payload (if the server includes it) or falls back to `_channel_to_space` lookup.

### Join Lobby Flow (`channel_list.gd` line 377)

When the user clicks **Join Lobby** on a session row:

1. Set `AppState.pending_activity_*` fields from the session data
2. If user is not in the session's voice channel:
   - Call `Client.join_voice_channel(session.channel_id)` first
   - On `voice_joined` (one-shot), call `Client.plugins.join_activity()`
3. If user is already in the voice channel:
   - Call `Client.plugins.join_activity()` directly
4. `join_activity()` (line 335) assigns the user as "player" via `assign_role()`, downloads the runtime, and emits `activity_started`

### Join Voice Flow (`channel_list.gd` line 404)

When the user clicks **Join Voice**:

1. Look up the `channel_id` from the session data
2. Check `AccordPermission.CONNECT` for that voice channel
3. Call `Client.join_voice_channel(channel_id)`
4. The existing `_on_voice_joined` handler in `ClientPlugins` (line 645) will auto-discover and rejoin the activity session via `check_active_session()`

### Voice Status for Host (`activity_row.gd` line 119)

```gdscript
func _is_host_in_voice(channel_id: String, host_id: String) -> bool:
    if channel_id.is_empty() or host_id.is_empty():
        return false
    var voice_users: Array = Client.get_voice_users(channel_id)
    for vs in voice_users:
        if vs.get("user_id", "") == host_id:
            return true
    return false
```

This uses the existing `_voice_state_cache` in `client.gd`, updated in real time by `voice_state_update` gateway events.

### Existing Activity Coupling (Preserved)

Activities are still discoverable in two existing places (unchanged):

1. **On voice join** — `ClientPlugins._on_voice_joined()` (line 645) calls `check_active_session()` which queries `get_channel_sessions()` for the voice channel the user just joined. If a session exists, it auto-rejoins.

2. **In the video grid** — `scenes/video/video_grid.gd` listens for `AppState.activity_available` and shows a `pending_activity_banner.tscn` overlay inside the video view.

The new activities section provides a third discovery path that works without being in voice.

## Implementation Status
- [x] Plugin manifest model with `lobby`, `max_participants`, `max_spectators` fields
- [x] Plugin session create/join/leave/state REST endpoints (`plugins_api.gd`)
- [x] `get_channel_sessions()` REST endpoint for per-channel session queries
- [x] Gateway events for `plugin_session_state` and `plugin_role_changed`
- [x] AppState signals for activity lifecycle (`activity_available`, `activity_started`, `activity_ended`, etc.)
- [x] Voice state cache with real-time updates via gateway
- [x] `ClientPlugins.join_activity()` flow for non-host joining
- [x] Pending activity banner in video grid (existing approach)
- [x] Activities section scene (`activities_section.tscn` + script)
- [x] Activity row scene (`activity_row.tscn` + script) with Join Lobby / Join Voice buttons
- [x] Space-level active session cache in `ClientPlugins._space_sessions`
- [x] New `AppState.active_sessions_updated(space_id)` signal
- [x] Integration into `channel_list.gd` `load_space()` to inject activities section
- [x] Relax voice-channel filter in `on_plugin_session_state()` to cache all space sessions
- [x] `get_space_sessions()` REST wrapper in `plugins_api.gd` (line 59)
- [x] Fallback per-channel polling when space endpoint unavailable
- [x] Real-time signal wiring for session/voice state changes in activities section
- [x] Auto-voice-join before lobby join when user is not in the session's voice channel
- [x] `GET /spaces/{space_id}/sessions/active` endpoint in accordserver (`routes/plugins.rs`, `db/plugins.rs`)
- [x] `space_id` field in `plugin_session_state` gateway event payload (all three broadcast sites)

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| Running sessions not joinable | Low | By design, `state == "running"` blocks new players; spectator join for running sessions is not implemented |
| No activity icon in manifests | Low | Plugin manifests have no `icon` field; activity rows use a default rocket icon (`rocket.svg`) |
