# Master Server Discovery


## Overview

The accord master server (`accordmasterserver`) is a lightweight registry that aggregates public spaces from multiple accordserver instances into a single searchable directory. Server operators opt in by registering their accordserver URL with the master server. The master server periodically polls each registered instance's `GET /spaces/public` endpoint, caches the results, and exposes a unified API for browsing, searching, and joining public servers. The daccord client adds a "Discover Servers" panel accessible from the guild bar, where users can browse the directory and join servers with one click.

This flow is analogous to Discord's Server Discovery or Matrix's room directory -- a federated index of public communities.


## User Steps

### Browse Public Servers (Client)

1. User clicks the "Discover" button in the guild bar (compass icon, below the Add Server button).
2. A full-width discovery panel replaces the message view area.
3. The panel fetches `GET /directory` from the master server.
4. Server cards are displayed in a scrollable grid: icon, name, description, member count, tags.
5. User can search by name/description or filter by category tag.
6. Clicking a card opens a detail view: full description, banner, member count, category, server URL.
7. User clicks "Join Server" to connect.

### Join a Public Server (Client)

1. From the detail view, user clicks "Join Server".
2. Client checks if user already has an account on the target accordserver:
   - **Has account**: Client uses stored credentials to call `POST /spaces/{space_id}/join` on the target server.
   - **No account**: Client opens the auth dialog (register or sign-in) for the target server URL. After auth, calls `POST /spaces/{space_id}/join`.
3. On success, `Config.add_server()` saves the connection and `Client.connect_server()` adds the guild to the sidebar.
4. Discovery panel closes; the new guild appears in the guild bar.

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
| `daccord: scenes/sidebar/guild_bar/discover_button.gd` | Compass icon button in guild bar |
| `daccord: scenes/discovery/discovery_panel.gd` | Discovery panel UI (search, grid, detail view) |
| `daccord: scenes/discovery/server_card.gd` | Individual server card in the discovery grid |
| `daccord: addons/accordkit/rest/endpoints/directory.gd` | AccordKit REST client for master server directory API |
| `daccord: scripts/autoload/config.gd` | Stores master server URL in config |


## Implementation Details

### Master Server API

**Public endpoints (no auth):**

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check |
| `GET` | `/directory` | Browse/search public spaces |
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

The discovery panel is a new scene added to the main window, shown in place of the message view when the user clicks "Discover".

**Layout:**

```
┌──────────────────────────────────────────────┐
│  ← Back    Discover Servers                  │
│                                              │
│  ┌──────────────────────────────────────┐    │
│  │ 🔍 Search servers...                 │    │
│  └──────────────────────────────────────┘    │
│                                              │
│  Tags: [All] [Gaming] [Social] [Dev] [Art]   │
│                                              │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐      │
│  │  Icon   │  │  Icon   │  │  Icon   │      │
│  │  Name   │  │  Name   │  │  Name   │      │
│  │  Desc   │  │  Desc   │  │  Desc   │      │
│  │  142 👤 │  │  37 👤  │  │  89 👤  │      │
│  └─────────┘  └─────────┘  └─────────┘      │
│                                              │
│  ┌─────────┐  ┌─────────┐                   │
│  │  Icon   │  │  Icon   │                   │
│  │  Name   │  │  Name   │                   │
│  │  Desc   │  │  Desc   │                   │
│  │  56 👤  │  │  203 👤 │                   │
│  └─────────┘  └─────────┘                   │
└──────────────────────────────────────────────┘
```

**Detail view (on card click):**

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
│                                              │
│  ┌──────────────────┐                        │
│  │   Join Server     │                        │
│  └──────────────────┘                        │
└──────────────────────────────────────────────┘
```

### Client Config Addition

`Config` gains a `master_server_url` setting:

```gdscript
# Default master server URL (can be overridden by user)
const DEFAULT_MASTER_SERVER_URL := "https://directory.accordchat.com"

func get_master_server_url() -> String:
    return _config.get_value("general", "master_server_url", DEFAULT_MASTER_SERVER_URL)

func set_master_server_url(url: String) -> void:
    _config.set_value("general", "master_server_url", url)
    _config.save(_config_path)
```

### Join Flow Signal Chain

```
discovery_panel: user clicks "Join Server"
  → _check_existing_account(server_url)
    → Config.get_servers() -- look for matching base_url
    → If found: has account, use stored token
    → If not found: open auth_dialog for server_url
  → auth complete (existing or new account)
  → client: POST /api/v1/spaces/{space_id}/join on target accordserver
    → On 200: space joined
  → Config.add_server(base_url, token, guild_name)
  → Client.connect_server(server_config)
    → Fetches space, connects gateway
    → AppState.guilds_updated.emit()
  → discovery_panel closes
  → Guild appears in guild bar
```

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

- [ ] Master server: project scaffolding (Cargo.toml, main.rs, Axum setup)
- [ ] Master server: database schema and migrations
- [ ] Master server: server registry CRUD endpoints (`POST/GET/PATCH/DELETE /servers`)
- [ ] Master server: API key authentication for admin endpoints
- [ ] Master server: background indexer (poll `GET /spaces/public` on registered servers)
- [ ] Master server: health check monitoring
- [ ] Master server: directory API (`GET /directory` with search and tag filtering)
- [ ] Master server: space detail endpoint (`GET /directory/{space_id}`)
- [ ] Master server: pagination for directory results
- [ ] Master server: rate limiting
- [ ] daccord: "Discover" button in guild bar
- [ ] daccord: discovery panel scene (search, tag filter, card grid)
- [ ] daccord: server card scene
- [ ] daccord: server detail view with "Join Server" button
- [ ] daccord: join flow (account check, auth dialog, `POST /spaces/{id}/join`, add to config)
- [ ] daccord: master server URL in Config
- [ ] accordkit: directory REST endpoint wrapper


## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No accordmasterserver code exists yet | **High** | Repo is empty; needs full implementation |
| No discovery UI in daccord | **High** | Discover button and panel need to be built |
| No tag/category system on accordserver spaces | Medium | Spaces have no `tags` field; master server could add its own tagging layer, or accordserver could add a `tags` column |
| No space preview (channels, recent messages) | Low | Could add a read-only preview before joining, but adds complexity |
| No vanity/featured listings | Low | Could add a "featured" flag to the master server for curated highlights |
| No abuse reporting for listed servers | Medium | Operators can list anything; no report/flag mechanism yet |
| No server-side icon/banner proxying | Low | Directory returns direct CDN URLs to each accordserver; if a server goes down, icons break |
| No WebSocket push for directory updates | Low | Clients poll on panel open; could add real-time updates via SSE or WebSocket later |
