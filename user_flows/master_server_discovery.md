# Master Server Discovery

Priority: 59
Depends on: Server Connection

## Overview

The accord master server (`accordmasterserver`) is a lightweight registry that aggregates public spaces from multiple accordserver instances into a single searchable directory. Server operators opt in by registering their accordserver URL with the master server. The master server periodically polls each registered instance's `GET /spaces/public` endpoint, caches the results, and exposes a unified API for browsing, searching, and joining public servers.

The daccord client provides two entry points for discovery: a dedicated discovery panel accessible from the space bar's compass icon, and a "Browse Servers" tab inside the Add Server dialog. Both use the `DirectoryApi` AccordKit endpoint to query the master server.

This flow is analogous to Discord's Server Discovery or Matrix's room directory -- a federated index of public communities.

## User Steps

### Browse Public Servers (Discovery Panel)

1. User clicks the "Discover" button in the space bar (compass icon, below the Add Server button).
2. `AppState.open_discovery()` emits `discovery_opened`. `main_window` hides the message view and channel panel, shows `DiscoveryPanel`.
3. `discovery_panel.activate()` fetches `GET /directory` from the master server via `DirectoryApi.browse()`.
4. Space cards are displayed in a responsive grid (3 columns >= 800px, 2 columns >= 500px, 1 column < 500px). Each card shows icon, name, ping strength indicator, member count (with optional online count), description, and tag chips. The ping indicator uses Unicode bar characters (▂▄▆█) colored by latency: green <200ms, yellow <400ms, red >=400ms.
5. User can type in the search box (0.4s debounce) to search by name/description. Search re-fetches from the master server (server-side).
6. Tag chips are dynamically populated from the response data. Clicking a tag re-fetches with a `tag` query parameter (server-side filter). "All" resets to unfiltered.
7. Clicking a card hides the grid/search/tags and shows a detail view inline: banner image, icon, name, member/online counts, description, comma-separated tags, server URL (protocol stripped), ping strength (with latency in ms), and a "Join Server" button. The ping row shows "Measuring..." until the health check completes.

### Browse Public Servers (Add Server Dialog)

1. User clicks Add Server in the space bar, then switches to the "Browse Servers" tab.
2. An embedded `discovery_panel` (with `set_embedded(true)`) fetches the directory and shows discovery cards in a single-column grid. The header (close button + title) is hidden and margins are reduced to fit within the dialog.
3. User can search (0.4s debounce, server-side) and filter by tags, identical to the full discovery panel.
4. Clicking a card shows the inline detail view with back button and join button.
5. Clicking "Join Server" emits `join_requested` to the dialog, which handles auth and connection via `_on_browse_join()`.

### Join a Public Server (Client)

1. From either the discovery detail view or the browse servers panel, user clicks "Join Server" / join button.
2. Client checks if user already has an account on the target accordserver:
   - **Has account**: Checks `Config.get_servers()` for a matching `base_url` that is currently connected (`Client.is_server_connected()`). Uses stored token to call `POST /api/v1/spaces/{space_id}/join` on the target server.
   - **No account**: Client opens the auth dialog (register or sign-in) for the target server URL. After auth, calls `POST /api/v1/spaces/{space_id}/join`.
3. On success, `Config.add_server()` saves the connection and `Client.connect_server()` adds the space to the sidebar.
4. `AppState.close_discovery()` hides the discovery panel and restores the message view. The new space is selected via `AppState.select_space()`.

### Register a Server (Server Operator)

1. Operator runs an accordserver instance with at least one public space (`public: true`).
2. Operator sends a `POST /servers` request to the master server with their accordserver URL and an admin API key.
3. Master server validates the URL by calling `GET /health` on the target.
4. On success, the server is added to the registry and its public spaces are indexed on the next poll cycle.
5. Operator can update or remove their listing via `PATCH /servers/{id}` or `DELETE /servers/{id}`.


## Architecture

### Master Server (accordmasterserver)

A standalone Rust service (separate from accordserver) with its own database. Responsibilities:

1. **Server registry** -- stores registered accordserver URLs and metadata.
2. **Space indexer** -- periodically polls each registered server's `GET /api/v1/spaces/public` endpoint.
3. **Directory API** -- serves aggregated, searchable space listings to daccord clients.
4. **Health monitoring** -- tracks which servers are online and filters out unreachable instances.

```
┌─────────────────────────────────────────────────┐
│                accordmasterserver               │
│                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────────┐  │
│  │ Registry │  │ Indexer  │  │ Directory API│  │
│  │          │  │ (poller) │  │   (public)   │  │
│  └────┬─────┘  └────┬─────┘  └──────┬───────┘  │
│       │              │               │          │
│       └──────────────┴───────────────┘          │
│                      │                          │
│               ┌──────┴──────┐                   │
│               │  Database   │                   │
│               │  (SQLite)   │                   │
│               └─────────────┘                   │
└─────────────────────────────────────────────────┘
        ▲                           ▲
        │ POST /servers             │ GET /directory
        │ (operators)               │ (daccord clients)
        │                           │
   ┌────┴────┐               ┌──────┴──────┐
   │ Server  │               │   daccord   │
   │ Operator│               │   client    │
   └─────────┘               └─────────────┘

Indexer polls each registered accordserver:
   accordmasterserver ──GET /api/v1/spaces/public──▶ accordserver A
   accordmasterserver ──GET /api/v1/spaces/public──▶ accordserver B
   accordmasterserver ──GET /api/v1/spaces/public──▶ accordserver C
```

### Data Flow

```
1. Registration:
   Operator ──POST /servers {url}──▶ accordmasterserver
     ──GET /health──▶ accordserver (validation)
     ◀── 200 OK
     ◀── server added to registry

2. Indexing (periodic, every 5 minutes):
   accordmasterserver ──GET /api/v1/spaces/public──▶ accordserver
     ◀── [{name, slug, description, icon, member_count, ...}]
     → upsert spaces into directory DB
     → mark server as healthy/unhealthy based on response

3. Client discovery:
   daccord ──GET /directory?q=gaming&tag=gaming──▶ accordmasterserver
     ◀── [{space_name, description, member_count, server_url, space_id, icon_url, tags, ...}]

4. Client join:
   daccord ──POST /api/v1/spaces/{space_id}/join──▶ accordserver (direct)
     ◀── 200 OK (member added)
```


## Key Files

| File | Role |
|------|------|
| `accordmasterserver/src/main.rs` | Service entry point, HTTP server setup |
| `accordmasterserver/src/routes/` | API route handlers (servers, directory) |
| `accordmasterserver/src/indexer.rs` | Background poller that fetches public spaces from registered servers |
| `accordmasterserver/src/db/` | Database layer (server registry, space directory) |
| `accordmasterserver/migrations/` | SQLite schema migrations |
| `scenes/sidebar/guild_bar/discover_button.gd` | Compass icon button in space bar, emits `discover_pressed` |
| `scenes/sidebar/guild_bar/guild_bar.gd` | Connects discover button to `AppState.open_discovery()` |
| `scenes/discovery/discovery_panel.gd` | Full discovery panel: search, tag filter, responsive card grid, inline detail view, server ping measurement |
| `scenes/discovery/discovery_card.gd` | Individual space card in the discovery grid (icon, name, ping indicator, members, description, tags) |
| `scenes/discovery/discovery_detail.gd` | Detail view with banner, icon, stats, description, tags, ping row, join button |
| `scenes/discovery/discovery_panel.gd` | Also used in embedded mode inside the Add Server dialog's "Browse Servers" tab (single-column grid, no header) |
| `addons/accordkit/rest/endpoints/directory_api.gd` | `DirectoryApi` class: `browse(query, tag, page)` and `get_space(space_id)` |
| `scripts/autoload/config.gd` | `get_master_server_url()` / `set_master_server_url()` (default: `https://master.daccord.gg`) |
| `scripts/autoload/app_state.gd` | `discovery_opened` / `discovery_closed` signals, `is_discovery_open` state |
| `scenes/main/main_window.gd` | Mounts discovery panel, toggles visibility on discovery signals |


## Implementation Details

### Master Server API

**Public endpoints (no auth):**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/directory` | Browse/search public spaces (supports `q`, `tag`, `page` query params) |
| `GET` | `/directory/{space_id}` | Get detail for a specific space listing |

**Admin endpoints (API key auth):**

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/servers` | Register a new accordserver |
| `GET` | `/servers` | List registered servers |
| `GET` | `/servers/{id}` | Get server details |
| `PATCH` | `/servers/{id}` | Update server registration |
| `DELETE` | `/servers/{id}` | Remove server from registry |

### Directory Response Shape

```json
{
  "spaces": [
    {
      "id": "space_id",
      "name": "My Community",
      "slug": "my-community",
      "description": "A place for chatting",
      "icon_url": "https://server.example.com/cdn/icons/space_id/hash.png",
      "banner_url": "https://server.example.com/cdn/banners/space_id/hash.png",
      "member_count": 142,
      "presence_count": 37,
      "tags": ["gaming", "social"],
      "server_url": "https://server.example.com:39099",
      "server_name": "Example Server",
      "last_seen_healthy": "2026-02-21T10:00:00Z",
      "indexed_at": "2026-02-21T10:05:00Z"
    }
  ],
  "total": 1,
  "page": 1,
  "per_page": 25
}
```

### Server Registration Shape

```json
{
  "url": "https://server.example.com:39099",
  "name": "Example Server",
  "description": "An open community server",
  "tags": ["gaming", "social"],
  "contact_email": "admin@example.com"
}
```

### Database Schema (accordmasterserver)

**servers table:**

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT (UUID) | Primary key |
| `url` | TEXT (unique) | Accordserver base URL |
| `name` | TEXT | Display name |
| `description` | TEXT | Operator-provided description |
| `tags` | TEXT (JSON array) | Category tags |
| `contact_email` | TEXT | Operator contact |
| `api_key_hash` | TEXT | SHA256 hash of the operator's API key |
| `healthy` | BOOLEAN | Whether last health check passed |
| `last_health_check` | TIMESTAMP | When last polled |
| `created_at` | TIMESTAMP | Registration time |

**spaces table:**

| Column | Type | Description |
|--------|------|-------------|
| `id` | TEXT | Accordserver space ID |
| `server_id` | TEXT (FK) | References servers.id |
| `name` | TEXT | Space name |
| `slug` | TEXT | Space slug |
| `description` | TEXT | Space description |
| `icon` | TEXT | Icon hash (for CDN URL construction) |
| `banner` | TEXT | Banner hash |
| `member_count` | INTEGER | Member count |
| `presence_count` | INTEGER | Online count |
| `tags` | TEXT (JSON array) | Category tags (inherited from server + space-level) |
| `indexed_at` | TIMESTAMP | When this data was last fetched |

Composite unique constraint on `(server_id, id)` to prevent duplicates.

### Indexer (Background Poller)

The indexer runs as a background task on a configurable interval (default: 5 minutes).

```
For each registered server:
  1. GET {server_url}/health
     - If unreachable: mark server as unhealthy, skip
     - If reachable: mark server as healthy, update last_health_check
  2. GET {server_url}/api/v1/spaces/public
     - Upsert each space into the spaces table
     - Remove spaces from DB that are no longer in the response (space was made private or deleted)
  3. Log result: "Indexed {N} spaces from {server_name}"
```

Unhealthy servers are still polled on every cycle (they may come back online) but their spaces are excluded from directory results.

### Client Discovery Panel

The discovery panel (`scenes/discovery/discovery_panel.gd`) is mounted in `main_window.tscn` at `$LayoutHBox/DiscoveryPanel`, initially hidden. When `AppState.discovery_opened` fires, `main_window` hides the content area and channel panel, then calls `discovery_panel.activate()`.

**Layout (grid view):**

```
┌──────────────────────────────────────────────┐
│  ← Back    Discover Servers                  │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ Search servers...                    │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Tags: [All] [Gaming] [Social] [Dev] [Art]   │
│                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │Icon Name ▂▄▆█│  │Icon Name ▂▄▆│  │Icon Name ▂▄ │ │
│  │     142 memb │  │     37 memb  │  │     89 memb  │ │
│  │     Desc     │  │     Desc     │  │     Desc     │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                        │
│  ┌──────────────┐  ┌──────────────┐                    │
│  │Icon Name ▂▄▆█│  │Icon Name ▂   │                    │
│  │     56 memb  │  │     203 memb │                    │
│  │     Desc     │  │     Desc     │                    │
│  └──────────────┘  └──────────────┘                    │
└──────────────────────────────────────────────┘
```

**Detail view (inline, replaces grid on card click):**

```
┌──────────────────────────────────────────────┐
│  ← Back to results                           │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │          Banner Image                │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  [Icon]  My Community                        │
│          142 members · 37 online             │
│                                              │
│  A place for chatting about games and more.  │
│                                              │
│  Tags: Gaming, Social                        │
│  Server: server.example.com                  │
│  Ping: ▂▄▆█ 45ms                            │
│                                              │
│  ┌──────────────────┐                        │
│  │   Join Server     │                        │
│  └──────────────────┘                        │
└──────────────────────────────────────────────┘
```

The detail view uses the card's already-loaded data dictionary rather than calling `GET /directory/{space_id}` separately. The join button shows "Joining..." while the request is in flight. Errors are displayed in red below the button.

### Ping Strength Indicator

After the discovery grid is populated, `discovery_panel` pings each unique `server_url` by sending a `GET /health` request and measuring the round-trip time (lines 215-257). Results are cached in `_ping_cache` (line 14) so repeated searches or detail view opens reuse the measurement.

**Measurement:** `_ping_server()` (line 229) creates an `HTTPRequest`, records `Time.get_ticks_msec()` before the request, and calculates the delta on completion. Only successful responses (2xx) are cached; failed pings are silently ignored.

**Display tiers:** Both `discovery_card.set_ping()` (line 63) and `discovery_detail.set_ping()` (line 80) use the same tier logic with Unicode bar characters:

| Latency | Bars | Color |
|---------|------|-------|
| < 100ms | ▂▄▆█ | `success` (green) |
| 100-199ms | ▂▄▆ | `success` (green) |
| 200-399ms | ▂▄ | `warning` (yellow) |
| >= 400ms | ▂ | `error` (red) |

**Card:** The ping label sits in a `TopRow` HBoxContainer alongside the space name (line 8-9 in `discovery_card.gd`), right-aligned at 11px font size.

**Detail view:** A dedicated `PingRow` in the Details section shows "Ping:" label and value (line 17 in `discovery_detail.gd`). The `setup()` method initializes it to "Measuring..." in muted text (lines 61-62). When the panel opens the detail view, it either applies the cached ping immediately or re-pings the server (lines 288-293 in `discovery_panel.gd`).

**Propagation:** `_apply_ping_to_cards()` (line 249) iterates all grid children and the active detail view, matching by `server_url`. This means when an async ping completes, all cards for that server update simultaneously.

### Browse Servers Tab (Add Server Dialog)

The "Browse Servers" tab in the Add Server dialog reuses `discovery_panel.gd` in **embedded mode** (`set_embedded(true)`). This gives it the same search, tag filtering, card grid, and detail view as the full-page discovery panel, with these adaptations:

- **Header hidden** -- the close button and "Discover Servers" title are removed (the dialog has its own close button).
- **Reduced margins** -- 8px instead of 24px/16px to fit within the 480px dialog.
- **Single-column grid** -- always 1 column regardless of panel width.
- **Join via signal** -- instead of handling join internally, the panel emits `join_requested(server_url, space_id)` which the dialog's `_on_browse_join()` handler processes (with its own auth/connect logic).
- **Auto-activates** -- `activate()` is called in `_ready()` when embedded, so data loads as soon as the tab is shown.

### Client Config

`Config` stores the master server URL under the `"master"` section:

```gdscript
func get_master_server_url() -> String:
    return _config.get_value("master", "url", "https://master.daccord.gg")

func set_master_server_url(url: String) -> void:
    _config.set_value("master", "url", url)
    _save()
```

### AppState Discovery Signals

```gdscript
signal discovery_opened()
signal discovery_closed()
var is_discovery_open: bool = false

func open_discovery():   # guards against double-open, sets flag, emits discovery_opened
func close_discovery():  # guards, clears flag, emits discovery_closed
```

Channel selection auto-closes discovery: `main_window._on_channel_selected()` checks `AppState.is_discovery_open` and calls `AppState.close_discovery()`.

### Join Flow Signal Chain

```
discovery_panel: user clicks "Join Server" in detail view
  → _on_detail_join(server_url, space_id)
    → Config.get_servers() -- look for matching base_url with active connection
    → If found: use stored token, call _join_and_connect()
    → If not found: open auth_dialog for server_url, on auth complete call _join_and_connect()
  → _join_and_connect():
    → POST /api/v1/spaces/{space_id}/join on target accordserver (direct, with bearer token)
      → On 200: space joined
    → Config.add_server(base_url, token, space_id)
    → await Client.connect_server(server_index)
      → Fetches space, connects gateway
    → AppState.close_discovery()
    → AppState.select_space(joined_space_id)
    → Space appears in space bar
```

### Theming

All discovery components use `ThemeManager` for colors:

- **discovery_panel.gd**: Uses `panel_bg`, `text_body`, `input_bg`, `accent`, `text_white`, `secondary_button`, `secondary_button_hover`, `accent_hover`. Connected to `AppState.theme_changed` for live updates (long-lived component).
- **discovery_card.gd**: Uses `nav_bg`, `button_hover`, `text_muted`, `secondary_button`, `success`, `warning`, `error` (ping indicator). Colors read at creation time (short-lived).
- **discovery_detail.gd**: Uses `text_muted`, `accent`, `accent_hover`, `accent_pressed`, `text_white`, `error`, `success`, `warning` (ping indicator). Colors read at creation time (short-lived).
- **discover_button.gd**: Uses `nav_bg` (normal) and `accent` (hover). Colors read at `_ready()`.

### Security Considerations

**Master server:**
- Admin API key required for server registration (prevents spam listings).
- Rate limiting on `/directory` to prevent abuse.
- The master server never stores user credentials -- it only indexes public data.
- Server URLs are validated via health check before acceptance.
- Spaces marked `public: false` on the accordserver are never exposed.

**Client:**
- The client connects to each accordserver directly for authentication and joining -- the master server is never a credential proxy.
- HTTPS enforced for master server communication.
- Users can configure a custom master server URL (self-hosted directories).

**Accordserver:**
- `GET /spaces/public` is unauthenticated by design -- only spaces explicitly marked `public: true` are returned.
- `POST /spaces/{space_id}/join` requires authentication, ensuring only real users can join.
- Ban checks are enforced server-side on join.

### Tech Stack (accordmasterserver)

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Rust | Matches accordserver; shared tooling and deployment |
| HTTP framework | Axum | Same as accordserver; familiar patterns |
| Database | SQLite | Simple deployment, sufficient for a directory index |
| Background tasks | Tokio tasks | Built into the async runtime already used by Axum |
| Auth | API key (admin) | Simple; no user accounts needed on the master server itself |


## Implementation Status

- [x] Master server: project scaffolding (Cargo.toml, main.rs, Axum setup)
- [x] Master server: database schema and migrations
- [x] Master server: server registry CRUD endpoints (`POST/GET/PATCH/DELETE /servers`)
- [x] Master server: API key authentication for admin endpoints
- [x] Master server: background indexer (poll `GET /spaces/public` on registered servers)
- [x] Master server: health check monitoring
- [x] Master server: directory API (`GET /directory` with search and pagination)
- [x] Master server: pagination for directory results
- [ ] Master server: space detail endpoint (`GET /directory/{space_id}`) -- `DirectoryApi.get_space()` exists but detail view uses cached card data instead
- [ ] Master server: rate limiting
- [x] daccord: Discover button in space bar (compass icon)
- [x] daccord: Discovery panel with responsive card grid, search (debounced), and tag filter
- [x] daccord: Discovery detail view with banner, icon, stats, and join button
- [x] daccord: Browse Servers tab in Add Server dialog (embedded discovery panel, single-column grid)
- [x] daccord: Join flow (account check, auth dialog, `POST /spaces/{id}/join`, add to config)
- [x] daccord: AppState discovery signals (`discovery_opened`, `discovery_closed`, `is_discovery_open`)
- [x] daccord: Master server URL in Config (section `"master"`, key `"url"`)
- [x] daccord: Ping strength indicator on discovery cards and detail view (health endpoint round-trip measurement)
- [x] daccord: ThemeManager integration for all discovery components
- [x] accordkit: `DirectoryApi` class (`browse()`, `get_space()`)
- [x] accordserver: `member_count` in public spaces response (JOIN with members table)


## Tasks

### DISCOVER-1: No accordmasterserver code exists yet
- **Status:** done
- **Impact:** 4
- **Effort:** 5
- **Tags:** general
- **Notes:** Master server implemented with server registry, background fetcher, health monitoring, and directory API

### DISCOVER-2: No discovery UI in daccord
- **Status:** done
- **Impact:** 4
- **Effort:** 3
- **Tags:** ui
- **Notes:** Two entry points: dedicated discovery panel (search, tag filter, card grid, detail view) and Browse Servers tab in Add Server dialog. Both use DirectoryApi.

### DISCOVER-3: No tag/category system on accordserver spaces
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** general
- **Notes:** Spaces have no `tags` field; master server could add its own tagging layer, or accordserver could add a `tags` column

### DISCOVER-4: No space preview (channels, recent messages)
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** general
- **Notes:** Could add a read-only preview before joining, but adds complexity

### DISCOVER-5: No vanity/featured listings
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** general
- **Notes:** Could add a "featured" flag to the master server for curated highlights

### DISCOVER-6: No abuse reporting for listed servers
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** general
- **Notes:** Operators can list anything; no report/flag mechanism yet

### DISCOVER-7: No server-side icon/banner proxying
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** ui
- **Notes:** Directory returns direct CDN URLs to each accordserver; if a server goes down, icons break

### DISCOVER-8: No WebSocket push for directory updates
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** gateway, ui
- **Notes:** Clients poll on panel open; could add real-time updates via SSE or WebSocket later

### DISCOVER-9: No URL normalization for join flow account matching
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** general
- **Notes:** `_on_detail_join()` uses direct string equality to match `base_url` in Config; URLs with trailing slashes or different schemes would fail to match an existing account
