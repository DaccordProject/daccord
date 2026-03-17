# Plugin Store

## Overview

The Plugin Store lets space administrators browse, search, and install plugins from a public catalog hosted on the master server (`master.daccord.gg`). This extends the existing plugin management flow — which only supports manual ZIP upload and per-server uninstall — with a centralized discovery experience modeled after the Master Server Discovery panel for spaces.

## User Steps

1. Space administrator opens **Space Settings → Plugins** (or right-clicks the space icon → "Plugins")
2. The plugin management dialog opens showing installed plugins with an **Upload Plugin** button
3. Administrator clicks a new **Browse Store** button in the plugin management dialog
4. A plugin store panel opens, fetching the plugin catalog from the master server
5. Administrator can **search** by name/keyword and **filter** by tag (e.g. "game", "utility", "theme")
6. Each plugin card shows: name, description, author, runtime badge (Scripted/Native), version, download count
7. Clicking a card opens a detail view with full description, permissions requested, and an **Install** button
8. Clicking **Install** downloads the plugin bundle from the master server and installs it to the current space via the existing `install_plugin` REST endpoint
9. For native (unsigned) plugins, the trust dialog appears before installation completes
10. On success, the plugin appears in the installed list and the `plugins_updated` signal fires

## Signal Flow

```
User clicks "Browse Store"
  → Plugin Store panel opens
  → REST: GET master.daccord.gg/api/v1/plugins?q=...&tag=...
  → Populate plugin cards in grid

User clicks plugin card
  → REST: GET master.daccord.gg/api/v1/plugins/{id}
  → Show detail view with Install button

User clicks "Install"
  → REST: GET master.daccord.gg/api/v1/plugins/{id}/bundle  (download)
  → [If native + unsigned] → PluginTrustDialog → trust_granted / trust_denied
  → REST: POST /spaces/{space_id}/plugins  (install on server)
  → AppState.plugins_updated.emit()
  → Plugin appears in installed list
```

## Key Files

| File | Role |
|------|------|
| `scenes/admin/plugin_management_dialog.gd` | Existing plugin management UI — upload, list, uninstall; entry point for store |
| `scripts/autoload/client_plugins.gd` | Plugin cache, launch/stop lifecycle, gateway event handlers |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | REST endpoints for plugin CRUD, sessions, bundles |
| `addons/accordkit/rest/endpoints/directory_api.gd` | Existing master server directory API (pattern for plugin catalog API) |
| `addons/accordkit/models/plugin_manifest.gd` | `AccordPluginManifest` — 20+ field model for plugin metadata |
| `scenes/plugins/plugin_trust_dialog.gd` | Trust confirmation for unsigned native plugins |
| `scripts/autoload/plugin_download_manager.gd` | Bundle download, SHA-256 verification, local caching |
| `scenes/discovery/discovery_panel.gd` | Space discovery panel — UI/UX pattern to follow for plugin browsing |
| `scripts/autoload/config.gd` | `get_master_server_url()` (line 645) — master server URL config |

## Implementation Details

### Existing Plugin Management (Implemented)

The current admin flow in `plugin_management_dialog.gd` provides:

- **Plugin list** with name, runtime badge, version, type, description (lines 82–166)
- **Upload** via native FileDialog accepting `.daccord-plugin` and `.zip` files (lines 169–243)
- **Uninstall** with confirmation dialog (lines 279–303)
- **Gateway sync** via `AppState.plugins_updated` signal (line 306)

The dialog is opened from:
- `server_management_panel.gd` (line 229) — Server Management → space row
- `guild_icon.gd` (line 270) — right-click context menu on space icon

### AccordKit Plugin REST API (Implemented)

`plugins_api.gd` provides 9 endpoints (lines 1–93):
- `list_plugins(space_id, type)` — GET `/spaces/{space_id}/plugins`
- `install_plugin(space_id, manifest, bundle, filename)` — POST multipart
- `delete_plugin(space_id, plugin_id)` — DELETE
- `get_source(plugin_id)` / `get_bundle(plugin_id)` — download binaries
- Session management: `create_session`, `delete_session`, `update_session_state`
- `assign_role`, `send_action`

### Plugin Manifest Model (Implemented)

`AccordPluginManifest` (lines 1–96) defines 20+ fields:
- Identity: `id`, `name`, `type` (activity/bot/theme/command), `runtime` (scripted/native)
- Metadata: `description`, `icon_url`, `version`, `format`
- Security: `signed`, `signature`, `bundle_hash` (SHA-256)
- Limits: `max_participants`, `max_spectators`, `max_file_size`, `bundle_size`
- Behavior: `lobby`, `canvas_size`, `data_topics`, `permissions`, `entry_point`

### Master Server Directory Pattern (Implemented — for spaces)

`discovery_panel.gd` (lines 1–426) provides the reference pattern for the plugin store:
- Creates a throwaway `AccordRest` pointed at `Config.get_master_server_url()` (line 93–94)
- Uses `DirectoryApi.browse(query, tag)` with search debounce (lines 89–127)
- Grid layout with responsive column count (lines 67–79)
- Tag bar with "All" + tag buttons (lines 140–184)
- Card → detail view navigation with back button (lines 259–291)
- Server ping display (lines 203–245)

### Master Server (Not Implemented — plugin endpoints needed)

The accordmasterserver (`../accordmasterserver`) currently only serves **space discovery**:
- `GET /api/v1/directory` — browse public spaces
- `GET /api/v1/directory/{space_id}` — space details
- Server registration and heartbeat management
- Background metadata fetcher syncing space data from registered servers

**No plugin-related endpoints exist.** The master server needs:

#### New Database Schema

```sql
-- New table: public_plugins
CREATE TABLE IF NOT EXISTS public_plugins (
    id TEXT PRIMARY KEY,              -- plugin_id from publisher
    server_id TEXT NOT NULL,          -- publishing server
    name TEXT NOT NULL,
    type TEXT NOT NULL,               -- activity, bot, theme, command
    runtime TEXT NOT NULL,            -- scripted, native
    description TEXT DEFAULT '',
    version TEXT DEFAULT '',
    author TEXT DEFAULT '',
    icon_url TEXT,
    tags TEXT DEFAULT '[]',           -- JSON array
    download_count INTEGER DEFAULT 0,
    bundle_size INTEGER DEFAULT 0,
    signed BOOLEAN DEFAULT FALSE,
    featured BOOLEAN DEFAULT FALSE,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
```

#### New REST Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/plugins` | Browse/search plugins (query, tag, type, page) |
| `GET` | `/api/v1/plugins/{id}` | Plugin detail with full manifest |
| `GET` | `/api/v1/plugins/{id}/bundle` | Download plugin bundle |
| `POST` | `/api/v1/plugins` | Publish a plugin (server auth required) |
| `DELETE` | `/api/v1/plugins/{id}` | Remove a published plugin |

### Client-Side Changes Needed

#### New AccordKit Endpoint: `PluginDirectoryApi`

A new endpoint class in `addons/accordkit/rest/endpoints/` following the `DirectoryApi` pattern:

```gdscript
class_name PluginDirectoryApi
extends EndpointBase

func browse(query: String = "", tag: String = "", type: String = "", page: int = 1) -> RestResult:
    var params := {}
    if not query.is_empty():
        params["q"] = query
    if not tag.is_empty():
        params["tag"] = tag
    if not type.is_empty():
        params["type"] = type
    if page > 1:
        params["page"] = page
    return await _rest.make_request("GET", AccordConfig.API_BASE_PATH + "/plugins", null, params)

func get_plugin(plugin_id: String) -> RestResult:
    return await _rest.make_request("GET", AccordConfig.API_BASE_PATH + "/plugins/" + plugin_id)

func get_bundle(plugin_id: String) -> RestResult:
    return await _rest.make_raw_request(AccordConfig.API_BASE_PATH + "/plugins/" + plugin_id + "/bundle")
```

#### Plugin Store UI Panel

A new scene following the `discovery_panel.gd` pattern:
- Search input with debounce timer
- Tag bar with type filter (Activity, Bot, Theme, Command)
- Responsive grid of plugin cards
- Card → detail view with Install button
- Download progress indicator

#### Integration into Plugin Management Dialog

`plugin_management_dialog.gd` needs a "Browse Store" button (next to the existing "Upload Plugin" button) that opens the plugin store panel.

#### Install-from-Store Flow

1. Download bundle from master server via `PluginDirectoryApi.get_bundle()`
2. Extract manifest from downloaded ZIP (reuse existing `_extract_manifest()` from `plugin_management_dialog.gd`, lines 245–276)
3. For native unsigned plugins, show trust dialog (reuse `ClientPlugins._show_trust_dialog()`, lines 284–300)
4. Call `plugins_api.install_plugin()` to upload to the user's server
5. Emit `AppState.plugins_updated`

## Implementation Status

- [x] Plugin manifest model (`AccordPluginManifest`) with all needed fields
- [x] Plugin REST API for install/uninstall on individual servers
- [x] Plugin management dialog (list, upload, uninstall)
- [x] Plugin trust model for unsigned native plugins
- [x] Bundle download and SHA-256 verification (`PluginDownloadManager`)
- [x] Master server infrastructure (Rust/Axum/SQLite) with directory pattern
- [x] Space discovery panel as UI reference pattern
- [x] Master server URL configuration (`Config.get_master_server_url()`)
- [ ] Master server plugin database schema
- [ ] Master server plugin REST endpoints (browse, detail, bundle download, publish)
- [ ] `PluginDirectoryApi` AccordKit endpoint class
- [ ] Plugin store UI panel (grid, search, tags, detail view)
- [ ] Plugin store card scene (name, description, author, runtime badge, downloads)
- [ ] Plugin store detail view (full manifest, permissions, Install button)
- [ ] "Browse Store" button in plugin management dialog
- [ ] Install-from-store flow (download → extract → trust check → install)
- [ ] Plugin publishing flow (server admins publish to master server)
- [ ] Download count tracking on master server
- [ ] Plugin ratings/reviews
- [ ] Plugin version update notifications
- [ ] Featured/curated plugin highlights

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No plugin endpoints on master server | High | `../accordmasterserver` only has space directory (`/api/v1/directory`). Needs new `public_plugins` table and full CRUD endpoints for plugin catalog. |
| No `PluginDirectoryApi` in AccordKit | High | Need a new endpoint class in `addons/accordkit/rest/endpoints/` following the `DirectoryApi` pattern (lines 1–27 of `directory_api.gd`). |
| No plugin store UI | High | Need new scenes: plugin store panel, plugin card, plugin detail view. Follow `discovery_panel.gd` (426 lines) pattern for grid, search, tags, card→detail navigation. |
| No "Browse Store" entry point | Medium | `plugin_management_dialog.gd` only has "Upload Plugin" button (line 31). Need a second button to open the store. |
| No plugin publishing flow | Medium | Server admins need a way to publish plugins to the master server. Could be a REST endpoint called from `plugin_management_dialog.gd` or a separate publishing tool. |
| No version update detection | Medium | Once a plugin is installed, there's no mechanism to check if a newer version is available on the master server and prompt the admin to update. |
| No download count / popularity | Low | Master server needs to track download counts. Useful for sorting "most popular" in the store. |
| No ratings or reviews | Low | No way for users to rate or review plugins. Would require user accounts on the master server. |
| No plugin screenshots/media | Low | `AccordPluginManifest` has `icon_url` but no field for screenshots or preview media that would make store browsing more engaging. |
| No author verification | Low | No mechanism to verify plugin authors or show verified badges. The `signed` field on manifests covers code integrity but not author identity. |
