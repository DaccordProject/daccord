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
  +---> AppState.activity_session_state_changed(plugin_id, state)
  +---> AppState.activity_available(plugin_id, channel_id, session_id)
  +---> AppState.activity_participants_updated(session_id, participants)
  +---> [NEW] AppState.active_sessions_updated(space_id)
          |
          v
        ChannelList._on_active_sessions_updated(space_id)
          |
          v
        ActivitiesSection.refresh(sessions)
          |
          +---> For each session: ActivityRow.setup(session_data)
                  |
                  +---> Join Lobby button -> ClientPlugins.join_activity()
                  +---> Join Voice button -> Client.join_voice_channel()

Voice state updates:
  Gateway voice_state_update
    -> AppState.voice_state_updated(channel_id)
    -> ActivitiesSection._on_voice_state_updated(channel_id)
    -> Update "Join Voice" button visibility per row
```

## Key Files
| File | Role |
|------|------|
| `scripts/client/client_plugins.gd` | Activity lifecycle, session management, plugin cache |
| `scripts/client/client_gateway_events.gd` | Routes gateway plugin/voice events to Client |
| `scripts/autoload/app_state.gd` | Signal bus for activity and voice state (lines 206-261) |
| `scripts/autoload/client.gd` | Voice state cache, `get_voice_users()` |
| `scenes/sidebar/channels/channel_list.gd` | Channel list population — activities section to be added here |
| `scenes/sidebar/channels/voice_channel_item.gd` | Existing voice channel UI (reference for participant display) |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | `get_channel_sessions()` REST call (line 51) |
| `addons/accordkit/models/plugin_manifest.gd` | Plugin metadata: `lobby`, `max_participants`, `max_spectators` |
| `scripts/client/client_voice.gd` | Voice channel join/leave |

## Implementation Details

### Current State: Activities Are Coupled to Voice Channels

Activities are currently discovered and displayed in two places:

1. **On voice join** — `ClientPlugins._on_voice_joined()` (line 585) calls `check_active_session()` which queries `get_channel_sessions()` for the voice channel the user just joined. If a session exists, it auto-rejoins.

2. **In the video grid** — `scenes/video/video_grid.gd` listens for `AppState.activity_available` (line 83) and shows a `pending_activity_banner.tscn` overlay inside the video view. This only works when the user is already in the voice channel.

There is no way to discover or browse active activities from the channel list without already being in voice.

### New: Activities Section in Channel List

A new collapsible **Activities** section should be injected into `channel_list.gd`'s `load_space()` method, appended after all channel categories. It renders when there are active sessions in any voice channel within the current space.

**Data source:** The section needs active sessions across all voice channels in the space. Two approaches:

- **Option A (per-channel polling):** For each voice channel in the space, call `get_channel_sessions()`. This reuses the existing REST endpoint but requires N requests.
- **Option B (new space-level endpoint):** Add `GET /spaces/{space_id}/sessions/active` to accordserver that returns all active sessions in the space in one call. This is the preferred approach.

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

### Activities Section UI (New Scene)

A new scene `scenes/sidebar/channels/activities_section.tscn` with script:

- **Header row:** Collapsible "ACTIVITIES" label (styled like category headers in `category_item.gd`)
- **Activity rows:** One per active session, each containing:
  - Plugin icon (from manifest `icon` field, or a default game controller icon)
  - Activity name (from `manifest.name`)
  - State badge: "Lobby" (green) or "In Progress" (yellow)
  - Participant count: `"{current}/{max}"` using `participants.size()` and `manifest.max_participants` (0 = unlimited, show as `"{current}"`)
  - **Join Lobby** button: Calls `ClientPlugins.join_activity()` after setting pending activity state. Disabled when `state == "running"` (non-participants cannot join mid-game, line 286-287 of `client_plugins.gd`). Disabled when at max capacity.
  - **Join Voice** button: Visible only when the host user (`host_user_id`) appears in the voice state cache for the session's `channel_id`. Calls `Client.join_voice_channel(channel_id)`.

### Real-Time Updates

The section must stay current by listening to these signals:

| Signal | Update |
|--------|--------|
| `AppState.activity_session_state_changed(plugin_id, state)` | Update state badge; remove row if "ended" |
| `AppState.activity_available(plugin_id, channel_id, session_id)` | Add new row for the session |
| `AppState.activity_participants_updated(session_id, participants)` | Update participant count; enable/disable Join Lobby |
| `AppState.activity_ended(plugin_id)` | Remove row; hide section if empty |
| `AppState.voice_state_updated(channel_id)` | Check if host is in voice → toggle Join Voice button |
| `AppState.voice_joined(channel_id)` | Same as above |
| `AppState.voice_left(channel_id)` | Same as above |
| `AppState.plugins_updated()` | Refresh manifest data (name, icon, limits) |

### Scope of Gateway Changes

The `plugin_session_state` gateway event (handled at `client_plugins.gd` line 500) currently only sets pending activity state when the user is in the same voice channel (line 536). For the activities section to show all space-wide sessions, this filtering needs to be relaxed — sessions should be cached at the space level regardless of whether the local user is in that voice channel.

**New cache needed in ClientPlugins:**
```gdscript
# Space-level active session cache: space_id -> { session_id -> session_dict }
var _space_sessions: Dictionary = {}
```

Updated on:
- `on_plugin_session_state()` — add/update/remove from `_space_sessions`
- `fetch_plugins()` — optionally pre-fetch active sessions for the space
- Voice state changes — update host voice status within cached sessions

A new signal `AppState.active_sessions_updated(space_id)` would notify the channel list to rebuild the activities section.

### Accordserver Changes (../accordserver)

A new REST endpoint is needed:

```
GET /spaces/{space_id}/sessions/active
```

Returns all non-ended plugin sessions across all channels in the space. This avoids the client needing to poll each voice channel individually.

Additionally, the `plugin_session_state` gateway event should include `space_id` so the client can cache sessions at the space level without a channel-to-space lookup.

### Join Lobby Flow

When the user clicks **Join Lobby** on a session row:

1. Set `AppState.pending_activity_*` fields from the session data
2. If user is not in the session's voice channel:
   - Call `Client.join_voice_channel(session.channel_id)` first
   - On `voice_joined`, call `Client.plugins.join_activity()`
3. If user is already in the voice channel:
   - Call `Client.plugins.join_activity()` directly
4. `join_activity()` (line 277) assigns the user as "player" via `assign_role()`, downloads the runtime, and emits `activity_started`

### Join Voice Flow

When the user clicks **Join Voice**:

1. Look up the `channel_id` from the session data
2. Check `AccordPermission.CONNECT` for that voice channel
3. Call `Client.join_voice_channel(channel_id)`
4. The existing `_on_voice_joined` handler in `ClientPlugins` (line 585) will auto-discover and rejoin the activity session via `check_active_session()`

### Voice Status for Host

To determine whether the host user is currently in voice:

```gdscript
func _is_host_in_voice(session: Dictionary) -> bool:
    var channel_id: String = session.get("channel_id", "")
    var host_id: String = session.get("host_user_id", "")
    if channel_id.is_empty() or host_id.is_empty():
        return false
    var voice_users: Array = Client.get_voice_users(channel_id)
    for vs in voice_users:
        if vs.get("user_id", "") == host_id:
            return true
    return false
```

This uses the existing `_voice_state_cache` in `client.gd`, updated in real time by `voice_state_update` gateway events (handled at `client_gateway_events.gd` line 187).

## Implementation Status
- [x] Plugin manifest model with `lobby`, `max_participants`, `max_spectators` fields
- [x] Plugin session create/join/leave/state REST endpoints (`plugins_api.gd`)
- [x] `get_channel_sessions()` REST endpoint for per-channel session queries
- [x] Gateway events for `plugin_session_state` and `plugin_role_changed`
- [x] AppState signals for activity lifecycle (`activity_available`, `activity_started`, `activity_ended`, etc.)
- [x] Voice state cache with real-time updates via gateway
- [x] `ClientPlugins.join_activity()` flow for non-host joining
- [x] Pending activity banner in video grid (existing approach)
- [ ] Activities section scene (`activities_section.tscn` + script)
- [ ] Activity row scene (`activity_row.tscn` + script) with Join Lobby / Join Voice buttons
- [ ] Space-level active session cache in `ClientPlugins._space_sessions`
- [ ] New `AppState.active_sessions_updated(space_id)` signal
- [ ] Integration into `channel_list.gd` `load_space()` to inject activities section
- [ ] Relax voice-channel filter in `on_plugin_session_state()` to cache all space sessions
- [ ] `GET /spaces/{space_id}/sessions/active` endpoint in accordserver
- [ ] `space_id` field in `plugin_session_state` gateway event payload
- [ ] Real-time signal wiring for session/voice state changes in activities section
- [ ] Auto-voice-join before lobby join when user is not in the session's voice channel

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| No space-level session endpoint | High | `get_channel_sessions()` (line 51) is per-channel only; need `GET /spaces/{space_id}/sessions/active` in accordserver to avoid N+1 queries |
| `plugin_session_state` filtered by voice channel | High | `on_plugin_session_state()` (line 536) only caches sessions when `channel_id == AppState.voice_channel_id`; must cache all space sessions for the activities section |
| No space-level session cache | High | `ClientPlugins` tracks only the single active session (`_active_session_id`); needs a `_space_sessions` dictionary for multiple concurrent sessions |
| No `space_id` in session gateway event | Medium | `plugin_session_state` event payload lacks `space_id`; client must do `_channel_to_space` lookup which may miss channels not yet cached |
| No activities section UI | High | No scene or script exists for the activities section in the channel list |
| No activity row UI | High | No scene for individual activity rows with Join Lobby / Join Voice buttons |
| Join Lobby requires voice join first | Medium | `join_activity()` assumes user is already in the voice channel; needs orchestration to auto-join voice first if not connected |
| Running sessions not joinable | Low | By design, `state == "running"` blocks new players (line 286-287); spectator join for running sessions is not implemented |
| No activity icon in manifests | Low | Plugin manifests have no `icon` field; activity rows would need a default icon or the manifest schema needs extending |
