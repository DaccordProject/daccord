# Plugin Platform Services

Priority: 80
Depends on: Plugin System
Status: Planned (leaderboard endpoints & simulator — implementation target)

Server-provided backend services that plugin developers can use out of the box: persistent storage, leaderboards, achievements, matchmaking, server-authoritative state, timed events, virtual currencies, plugin announcements, and cross-session statistics. These services eliminate the need for plugin authors to build or host their own backends, enabling richer voice channel activities with minimal effort.

## Key Files

### Client (daccord)

| File | Role |
|------|------|
| `scripts/plugins/scripted_runtime.gd` | Lua bridge — `_inject_bridge_api()` (line 313) injects `api.*` functions into sandbox |
| `scripts/plugins/plugin_context.gd` | Native plugin bridge — GDScript API surface for native plugins (93 lines) |
| `scripts/client/client_plugins.gd` | Routes bridge calls to REST via `send_action()`, handles gateway events (786 lines) |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | AccordKit REST endpoint class — 12 endpoints (list/install/delete/sessions/actions) |
| `addons/accordkit/models/plugin_manifest.gd` | AccordPluginManifest model — no `services` block yet (97 lines) |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway dispatch — `plugin_event` signal (line 76), no platform service signals yet |

### Server (accordserver)

| File | Role |
|------|------|
| `src/routes/plugins.rs` | Route handlers — 12 endpoints, `broadcast_plugin_event()` helper (line 695) |
| `src/routes/mod.rs` | Route registration — plugin routes at lines 309–347 |
| `src/db/plugins.rs` | Database functions — CRUD for plugins/sessions/participants (408 lines) |
| `src/models/plugin.rs` | Model structs — `PluginManifest`, `Plugin`, `PluginSession`, `PluginAction` (128 lines) |
| `migrations/019_plugins.sql` | SQLite schema — `plugins`, `plugin_sessions`, `plugin_session_participants` tables |
| `migrations/postgres/003_plugins.sql` | Postgres equivalent |

### Editor (daccord-editor)

| File | Role |
|------|------|
| `scenes/plugins/scripted_runtime.gd` | Editor Lua bridge — same API surface minus `time()`/`ticks_ms()` |
| `scenes/plugins/plugin_canvas.gd` | Drawing command queue executor |
| `scripts/editor.gd` | Editor harness — `MockClientPlugins` (line 328), action loopback, user simulation |

## Overview

Today plugins communicate via `send_action()` (a passthrough REST call at `POST /plugins/{id}/sessions/{sid}/actions`) and LiveKit data channels (`send_data()`). Session state is ephemeral — when a session ends, everything is lost. Plugin developers who want persistence, ranking, or server authority must build it themselves. These platform services fill that gap by providing first-class, server-managed primitives that any plugin (scripted or native) can call through the existing bridge API.

## Current Plugin Infrastructure

### What Exists

**Server (accordserver):**
- Database tables: `plugins`, `plugin_sessions`, `plugin_session_participants` (migration 019)
- 13 REST endpoints registered at `src/routes/mod.rs:309-347`
- Gateway broadcast helper `broadcast_plugin_event()` at `src/routes/plugins.rs:695-716`
- Bundle parsing with manifest validation, signature checks (`src/routes/plugins.rs:587-691`)
- SQLite + PostgreSQL support with abstracted query placeholders

**Client (daccord):**
- Bridge API with ~30 functions injected at `scripted_runtime.gd:313-576`
  - Canvas/drawing (12 functions), state/networking (7), timers (3), audio (3), assets (1), helpers (6)
  - `time()` and `ticks_ms()` (lines 422-425) — not in editor
  - Bulk bridge `_array_from_flat()`/`_dict_from_flat()` — WASM optimization
  - Payload validation: `MAX_ACTION_PAYLOAD_BYTES = 8192` (line 10)
- Native plugin bridge via `PluginContext` — `send_action()`, `send_data()`, `send_file()`, `get_participants()`, `is_host()`
- Gateway signals: `plugin_installed`, `plugin_uninstalled`, `plugin_event`, `plugin_session_state`, `plugin_role_changed` (gateway_socket.gd lines 73-78)
- AccordPluginManifest model with 20+ fields, no `services` block (plugin_manifest.gd)

**Editor (daccord-editor):**
- `MockClientPlugins` inner class (editor.gd:328-331) — loops `send_action()` back as `on_plugin_event("action", data)`
- Multi-user simulation with `_users` array and `_apply_user_context()` (editor.gd:310-316)
- Rejoin simulation (editor.gd:391-451) — intercepts `state_sync`, stops/restarts runtime
- Same bridge API as client minus `time()`/`ticks_ms()` and bulk bridge helpers

### What's Missing (All Platform Services)

No platform service code exists in any of the three codebases:
- ❌ No `plugin_leaderboard_records` / `plugin_storage` / `plugin_achievements` / `plugin_stats` / `plugin_wallet` / `plugin_transactions` / `plugin_timers` tables
- ❌ No leaderboard/storage/achievement REST endpoints
- ❌ No `plugin_leaderboard_updated` / `plugin_storage_updated` / `plugin_achievement_unlocked` gateway signals
- ❌ No `leaderboard_submit` / `storage_set` / `achievement_unlock` bridge functions
- ❌ No `services` block in PluginManifest (server or client models)
- ❌ No editor simulators for any platform service

## User Steps

### Plugin developer declares services in manifest

1. Plugin manifest includes a new `services` block declaring which platform services the plugin uses
2. Server validates the manifest on upload and pre-creates resources (leaderboard schemas, achievement definitions, currency names)
3. Space admins can review requested services before installing a plugin

### Player interacts with platform services during an activity

1. User joins a voice channel activity (existing flow)
2. During gameplay, the plugin calls bridge functions like `storage_set()`, `leaderboard_submit()`, `achievement_unlock()`
3. The bridge routes these through `send_action()` to dedicated server endpoints
4. Server processes the request, updates its database, and broadcasts results via gateway events
5. Plugin receives callbacks (`_on_event("leaderboard_updated", data)`, `_on_event("achievement_unlocked", data)`) and updates its UI
6. After the session ends, data persists — the player's scores, achievements, and storage are available next time

### Player views persistent data outside of an activity

1. User opens a plugin's info card from the activity modal
2. Card shows the user's achievements, leaderboard rank, and stats for that plugin
3. User can browse the full leaderboard or compare with friends

## Signal Flow

### Current (send_action passthrough)

```
Plugin calls api.send_action(data)
    → ScriptedRuntime._bridge_send_action(data)             (scripted_runtime.gd:581)
        → size check: var_to_bytes(data) > 8192 → reject    (scripted_runtime.gd:582-589)
        → _client_plugins.send_action(_plugin_id, data)     (scripted_runtime.gd:590-591)
            → REST: POST /plugins/{id}/sessions/{sid}/actions
                → Server broadcasts plugin.event via gateway
    → Gateway: plugin_event signal                           (gateway_socket.gd:76)
        → client_gateway_events.on_plugin_event()
            → ClientPlugins._on_plugin_event(data)
                → ScriptedRuntime.on_plugin_event(event_type, data)
                    → Lua: _on_event(event_type, data)
```

### Planned (dedicated leaderboard endpoint)

```
Plugin calls api.leaderboard_submit(board_id, score, metadata)
    → ScriptedRuntime._bridge_leaderboard_submit(board_id, score, metadata)
        → REST: POST /plugins/{id}/leaderboards/{board_id}/submit
            → Server validates, updates plugin_leaderboard_records
            → Server broadcasts plugin_leaderboard_updated via gateway
    → Gateway: plugin_leaderboard_updated signal
        → client_gateway_events.on_plugin_leaderboard_updated()
            → ClientPlugins._on_plugin_leaderboard_updated(data)
                → ScriptedRuntime.on_plugin_event("leaderboard_updated", data)
                    → Lua: _on_event("leaderboard_updated", data)
```

### Planned (editor simulator loopback)

```
Plugin calls api.leaderboard_submit(board_id, score, metadata)
    → ScriptedRuntime._bridge_leaderboard_submit(board_id, score, metadata)
        → In-memory sorted array update (no REST, no server)
        → Immediate callback: on_plugin_event("leaderboard_updated", result)
            → Lua: _on_event("leaderboard_updated", data)
```

## Features

### 1. Key-Value Storage

Scoped persistent storage for plugins. Three scope levels:

- **user** — per-user per-plugin, only the owning user can read/write
- **session** — shared within an active session, cleared when session ends
- **global** — per-plugin server-wide, readable by all, writable by host or server

**Server endpoints:**
```
PUT    /plugins/{id}/storage/{collection}/{key}    body: {value, scope}
GET    /plugins/{id}/storage/{collection}/{key}?scope=user
DELETE /plugins/{id}/storage/{collection}/{key}?scope=user
GET    /plugins/{id}/storage/{collection}?scope=user&cursor=...&limit=50
```

**Bridge API (scripted):**
```lua
storage_set(collection, key, value, scope)    -- scope: "user"|"session"|"global"
storage_get(collection, key, scope) -> value
storage_delete(collection, key, scope)
storage_list(collection, scope) -> [{key, value}]
```

**Bridge API (native — PluginContext):**
```gdscript
context.storage_set(collection: String, key: String, value: Dictionary, scope: String)
context.storage_get(collection: String, key: String, scope: String) -> Dictionary
context.storage_delete(collection: String, key: String, scope: String)
context.storage_list(collection: String, scope: String) -> Array[Dictionary]
```

**Limits:**
- Key: max 128 characters
- Value: max 16 KB JSON
- Collections per plugin: max 32
- Keys per collection per user: max 500
- Session-scoped storage cleared automatically on session delete

**Gateway events:**
- `plugin_storage_updated` — broadcast to session participants when session/global scope changes

**Use cases:** save games, user preferences, persistent inventories, draft state, session shared whiteboards.

### 2. Leaderboards

Server-managed ranked lists with automatic sorting, pagination, and reset schedules.

**Manifest declaration:**
```json
{
  "services": {
    "leaderboards": [
      {"id": "high_score", "sort": "descending", "operator": "best", "reset": "weekly"},
      {"id": "fastest_time", "sort": "ascending", "operator": "best", "reset": "never"}
    ]
  }
}
```

**Server endpoints:**
```
POST /plugins/{id}/leaderboards/{board_id}/submit    body: {score, metadata}
GET  /plugins/{id}/leaderboards/{board_id}?limit=50&cursor=...
GET  /plugins/{id}/leaderboards/{board_id}/around?limit=10
GET  /plugins/{id}/leaderboards/{board_id}/user/{user_id}
```

**Bridge API (scripted):**
```lua
leaderboard_submit(board_id, score, metadata)
leaderboard_get(board_id, limit) -> [{user_id, display_name, score, rank, metadata}]
leaderboard_around_me(board_id, limit) -> [{user_id, display_name, score, rank}]
leaderboard_get_user(board_id, user_id) -> {score, rank}
```

**Bridge API (native — PluginContext):**
```gdscript
context.leaderboard_submit(board_id: String, score: float, metadata: Dictionary) -> void
context.leaderboard_get(board_id: String, limit: int) -> Array[Dictionary]
context.leaderboard_around_me(board_id: String, limit: int) -> Array[Dictionary]
context.leaderboard_get_user(board_id: String, user_id: String) -> Dictionary
```

**Operators:**
- `set` — always overwrite
- `best` — only save if better than current (respects sort direction)
- `increment` — add to current score

**Reset schedules:** `never`, `daily` (00:00 UTC), `weekly` (Monday 00:00 UTC). Server archives previous period's results before reset.

**Gateway events:**
- `plugin_leaderboard_updated` — broadcast to channel participants when a score changes rank in the top N

**Use cases:** high score tables, speedrun rankings, weekly competitions, cumulative point totals.

### 3. Achievements

Binary or progress-based milestones tracked per-user per-plugin.

**Manifest declaration:**
```json
{
  "services": {
    "achievements": [
      {"id": "first_win", "name": "First Victory", "description": "Win your first game", "icon": "assets/trophy.png"},
      {"id": "play_100", "name": "Centurion", "description": "Play 100 games", "icon": "assets/star.png", "target": 100}
    ]
  }
}
```

**Server endpoints:**
```
POST /plugins/{id}/achievements/{achievement_id}/unlock
POST /plugins/{id}/achievements/{achievement_id}/progress    body: {increment: 1}
GET  /plugins/{id}/achievements                               # current user's achievements
GET  /plugins/{id}/achievements/{achievement_id}/stats         # server-wide unlock percentage
```

**Bridge API (scripted):**
```lua
achievement_unlock(achievement_id)
achievement_progress(achievement_id, increment)
achievement_list() -> [{id, name, description, unlocked, progress, target}]
achievement_stats(achievement_id) -> {total_users, unlocked_count, percentage}
```

**Behavior:**
- Binary achievements: `unlock()` sets `unlocked_at` timestamp, idempotent
- Progress achievements: `progress()` increments counter, auto-unlocks when `progress >= target`
- Already-unlocked achievements silently succeed (no error, no duplicate event)
- Achievement icons loaded from plugin bundle assets

**Gateway events:**
- `plugin_achievement_unlocked` — sent to the unlocking user and broadcast to session participants
- Client shows a toast notification with the achievement name and icon

**Use cases:** game milestones, collection completion, skill challenges, engagement rewards.

### 4. Server-Authoritative State Sync

Replaces passthrough `send_action()` with an opinionated state machine where the server is the source of truth.

**Server endpoints:**
```
POST /plugins/{id}/sessions/{sid}/state    body: {op, path, value}
GET  /plugins/{id}/sessions/{sid}/state
GET  /plugins/{id}/sessions/{sid}/state/{path}
```

**Operations:**
- `set` — replace value at path
- `merge` — shallow merge dict at path
- `increment` — add numeric value at path
- `append` — push element to array at path
- `remove` — delete key or array element at path

**Bridge API (scripted):**
```lua
state_set(path, value)
state_merge(path, value)
state_increment(path, amount)
state_append(path, value)
state_remove(path)
state_get(path) -> value
state_get_all() -> dict
```

**Behavior:**
- Server validates operations atomically, rejects invalid ops (e.g., increment on a string)
- Optional: manifest declares a JSON schema; server rejects state mutations that violate it
- Server applies the operation and broadcasts the diff to all session participants
- Clients receive `_on_event("state_updated", {path, op, value, full_state})` callback
- State persisted for session lifetime, cleared on session delete
- Role-based write permissions: host can write anywhere, players only to paths prefixed with their user ID (configurable in manifest)

**Gateway events:**
- `plugin_state_updated` — broadcast to all session participants with the operation diff

**Use cases:** turn-based games, shared game boards, synchronized puzzles, voting systems, any game where client-only state allows cheating.

### 5. Matchmaking

Server-managed player queues that automatically form sessions when enough players are ready.

**Server endpoints:**
```
POST   /plugins/{id}/matchmaking/join     body: {mode, criteria}
DELETE /plugins/{id}/matchmaking/leave
GET    /plugins/{id}/matchmaking/status
```

**Bridge API (scripted):**
```lua
matchmaking_join(mode, criteria)     -- criteria: {min_players, max_players, skill_range}
matchmaking_leave()
matchmaking_status() -> {queued, estimated_wait_seconds}
```

**Behavior:**
- Server groups queued players by `mode` string (e.g., "ranked", "casual", "2v2")
- When enough players match (within `criteria` constraints), server auto-creates a session
- Session starts in "lobby" state; participants receive `plugin_match_found` gateway event
- Players who disconnect from voice while queued are automatically dequeued
- Queue timeout: 5 minutes default, configurable per mode in manifest
- Skill-based matching: optional `rating` field in criteria, server matches within `skill_range` tolerance

**Gateway events:**
- `plugin_match_found` — sent to matched players with session ID and participant list
- `plugin_matchmaking_status` — periodic queue position updates

**Use cases:** ranked competitive games, team-based activities, fair pairing for 1v1 games.

### 6. Scheduled / Timed Events

Server-side timers that fire gateway events to session participants, preventing desync.

**Server endpoints:**
```
POST   /plugins/{id}/sessions/{sid}/timers    body: {id, delay_ms, repeat, payload}
DELETE /plugins/{id}/sessions/{sid}/timers/{timer_id}
GET    /plugins/{id}/sessions/{sid}/timers
```

**Bridge API (scripted):**
```lua
server_timer_create(timer_id, delay_ms, repeat, payload)
server_timer_cancel(timer_id)
server_timer_list() -> [{id, remaining_ms, repeat, payload}]
```

**Behavior:**
- Server manages the timer — no single client is the authority on "time's up"
- `repeat`: boolean, if true the timer resets after firing
- Max timers per session: 16
- Min delay: 500ms, max delay: 3600000ms (1 hour)
- Payload included in the fired event (max 1 KB)
- Timers cleared automatically on session delete

**Gateway events:**
- `plugin_timer_fired` — broadcast to all session participants with timer_id and payload

**Use cases:** turn timers, round countdowns, auction deadlines, periodic game ticks, bomb timers.

### 7. Virtual Currencies / Economy

Plugin-defined numeric resources with server-enforced balances and transaction logging.

**Manifest declaration:**
```json
{
  "services": {
    "currencies": [
      {"id": "coins", "name": "Coins", "icon": "assets/coin.png", "initial_balance": 100},
      {"id": "gems", "name": "Gems", "icon": "assets/gem.png", "initial_balance": 0}
    ]
  }
}
```

**Server endpoints:**
```
POST /plugins/{id}/wallet/credit     body: {currency, amount, reason}
POST /plugins/{id}/wallet/debit      body: {currency, amount, reason}
GET  /plugins/{id}/wallet
GET  /plugins/{id}/wallet/history?limit=50&cursor=...
POST /plugins/{id}/wallet/transfer   body: {to_user_id, currency, amount}
```

**Bridge API (scripted):**
```lua
wallet_credit(currency, amount, reason)
wallet_debit(currency, amount, reason) -> bool    -- false if insufficient
wallet_balance(currency) -> number
wallet_transfer(to_user_id, currency, amount) -> bool
wallet_history(currency, limit) -> [{type, amount, reason, timestamp}]
```

**Behavior:**
- Server enforces non-negative balances — debit fails if insufficient funds
- All transactions logged with timestamp, reason, and counterparty
- `credit` can only be called by the session host or by server-side logic (anti-cheat)
- `transfer` deducts from sender and credits receiver atomically
- Currency icons loaded from plugin bundle assets
- Balances persist across sessions

**Gateway events:**
- `plugin_wallet_updated` — sent to the affected user when their balance changes

**Use cases:** in-game economies, betting/wagering, reward systems, shops, entry fees.

### 8. Plugin Announcements

Let plugins post bot-style messages into the text channel associated with the voice channel.

**Server endpoints:**
```
POST /plugins/{id}/sessions/{sid}/announce    body: {content, embed}
```

**Bridge API (scripted):**
```lua
announce(content)
announce_embed(content, embed)    -- embed: {title, description, color, fields}
```

**Behavior:**
- Posts a message attributed to the plugin (plugin name + icon as author, flagged as `system` type)
- Message appears in the text channel linked to the voice channel where the session is active
- Respects channel permissions — server checks `send_messages` for the plugin's context
- Rate limited: max 5 announcements per session per minute
- Embed format matches the existing message embed schema
- Manifest must include `send_announcements` permission

**Gateway events:**
- Standard `message_create` event — no special handling needed, the message just appears

**Use cases:** "Game Over — Player1 wins!", round summaries, leaderboard snapshots, achievement broadcasts, "Player joined the game" notifications.

### 9. Cross-Session Statistics

Aggregate stats that persist across sessions, feeding leaderboards and achievements automatically.

**Server endpoints:**
```
POST /plugins/{id}/stats/record     body: {stat, value, op}
GET  /plugins/{id}/stats                     # current user
GET  /plugins/{id}/stats/{user_id}
GET  /plugins/{id}/stats/top?stat=wins&limit=10
```

**Operations:** `increment`, `max` (only save if higher), `min` (only save if lower), `set`

**Bridge API (scripted):**
```lua
stat_record(stat_name, value, op)
stat_get(stat_name) -> number
stat_get_all() -> {stat_name: value, ...}
stat_top(stat_name, limit) -> [{user_id, display_name, value, rank}]
```

**Behavior:**
- Stats are simple numeric values identified by string names
- `increment` is the most common — "games_played", "total_kills", "messages_sent"
- `max`/`min` useful for "best score", "fastest time"
- Server can compute derived stats on read (e.g., win rate = wins / games_played)
- Stats feed into leaderboards: manifest can link a stat to a leaderboard for automatic sync
- Stats feed into achievements: manifest can link a stat to a progress achievement

**Manifest linkage:**
```json
{
  "services": {
    "stats": ["games_played", "wins", "total_score"],
    "leaderboards": [
      {"id": "most_wins", "stat": "wins", "sort": "descending", "operator": "set"}
    ],
    "achievements": [
      {"id": "play_100", "stat": "games_played", "target": 100}
    ]
  }
}
```

**Use cases:** lifetime statistics, win/loss records, total play time, skill ratings.

## Database Schema (accordserver)

### plugin_storage
```sql
CREATE TABLE plugin_storage (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    scope TEXT NOT NULL,          -- 'user', 'session', 'global'
    owner_id TEXT NOT NULL,       -- user_id for user scope, session_id for session, '' for global
    collection TEXT NOT NULL,
    key TEXT NOT NULL,
    value TEXT NOT NULL,          -- JSON blob
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    UNIQUE(plugin_id, space_id, scope, owner_id, collection, key)
);
```

### plugin_leaderboard_records
```sql
CREATE TABLE plugin_leaderboard_records (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    board_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    score REAL NOT NULL,
    metadata TEXT,               -- JSON blob
    period TEXT NOT NULL,        -- 'current', '2026-W13', etc.
    updated_at TEXT NOT NULL,
    UNIQUE(plugin_id, space_id, board_id, user_id, period)
);
```

### plugin_achievements
```sql
CREATE TABLE plugin_achievements (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    achievement_id TEXT NOT NULL,
    progress INTEGER NOT NULL DEFAULT 0,
    unlocked_at TEXT,            -- NULL if not yet unlocked
    UNIQUE(plugin_id, space_id, user_id, achievement_id)
);
```

### plugin_stats
```sql
CREATE TABLE plugin_stats (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    stat_name TEXT NOT NULL,
    value REAL NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    UNIQUE(plugin_id, space_id, user_id, stat_name)
);
```

### plugin_wallet
```sql
CREATE TABLE plugin_wallet (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    currency TEXT NOT NULL,
    balance REAL NOT NULL DEFAULT 0,
    UNIQUE(plugin_id, space_id, user_id, currency)
);
```

### plugin_transactions
```sql
CREATE TABLE plugin_transactions (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    space_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    currency TEXT NOT NULL,
    type TEXT NOT NULL,           -- 'credit', 'debit', 'transfer_in', 'transfer_out'
    amount REAL NOT NULL,
    reason TEXT,
    counterparty_id TEXT,
    created_at TEXT NOT NULL
);
```

### plugin_timers
```sql
CREATE TABLE plugin_timers (
    id TEXT PRIMARY KEY,
    plugin_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    timer_id TEXT NOT NULL,
    fires_at TEXT NOT NULL,
    repeat_ms INTEGER,           -- NULL if one-shot
    payload TEXT,                -- JSON blob
    UNIQUE(plugin_id, session_id, timer_id)
);
```

## Implementation Details

### Leaderboard Implementation — Server (accordserver)

**New files to create:**
- `src/db/plugin_leaderboards.rs` — CRUD functions for `plugin_leaderboard_records` table
- Migration file (e.g., `migrations/024_plugin_leaderboards.sql` + `migrations/postgres/008_plugin_leaderboards.sql`)

**Files to modify:**

1. **`src/models/plugin.rs`** — Add structs:
   ```rust
   pub struct LeaderboardSubmit { pub score: f64, pub metadata: Option<serde_json::Value> }
   pub struct LeaderboardRecord { pub user_id: String, pub display_name: String, pub score: f64, pub rank: i64, pub metadata: Option<serde_json::Value> }
   pub struct LeaderboardQuery { pub limit: Option<i64>, pub cursor: Option<String> }
   ```
   Add `services` field to `PluginManifest` (line 6):
   ```rust
   #[serde(default)]
   pub services: Option<serde_json::Value>,
   ```

2. **`src/routes/plugins.rs`** — Add 4 handler functions:
   - `leaderboard_submit()` — POST `/plugins/{id}/leaderboards/{board_id}/submit`
   - `leaderboard_list()` — GET `/plugins/{id}/leaderboards/{board_id}`
   - `leaderboard_around()` — GET `/plugins/{id}/leaderboards/{board_id}/around`
   - `leaderboard_get_user()` — GET `/plugins/{id}/leaderboards/{board_id}/user/{user_id}`

   Submit handler must:
   - Validate the user is a member of the plugin's space
   - Look up the board config from manifest `services.leaderboards`
   - Apply operator logic (`best`/`set`/`increment`)
   - Upsert into `plugin_leaderboard_records`
   - Broadcast `plugin_leaderboard_updated` via `broadcast_plugin_event()` (line 695)

3. **`src/routes/mod.rs`** — Register new routes after line 347:
   ```rust
   .route("/plugins/{plugin_id}/leaderboards/{board_id}/submit", post(plugins::leaderboard_submit))
   .route("/plugins/{plugin_id}/leaderboards/{board_id}", get(plugins::leaderboard_list))
   .route("/plugins/{plugin_id}/leaderboards/{board_id}/around", get(plugins::leaderboard_around))
   .route("/plugins/{plugin_id}/leaderboards/{board_id}/user/{user_id}", get(plugins::leaderboard_get_user))
   ```

4. **`src/db/plugins.rs`** — Add functions:
   - `upsert_leaderboard_record()` — insert or update based on operator
   - `get_leaderboard()` — sorted query with limit/cursor pagination
   - `get_leaderboard_around()` — records around a specific user's rank
   - `get_user_leaderboard_record()` — single user lookup with rank

### Leaderboard Implementation — Client (daccord)

**Files to modify:**

1. **`addons/accordkit/rest/endpoints/plugins_api.gd`** — Add 4 methods after line 118:
   ```gdscript
   func leaderboard_submit(plugin_id: String, board_id: String, score: float, metadata: Dictionary = {}) -> RestResult
   func leaderboard_get(plugin_id: String, board_id: String, limit: int = 50) -> RestResult
   func leaderboard_around(plugin_id: String, board_id: String, limit: int = 10) -> RestResult
   func leaderboard_get_user(plugin_id: String, board_id: String, user_id: String) -> RestResult
   ```

2. **`addons/accordkit/gateway/gateway_socket.gd`** — Add signal after line 78:
   ```gdscript
   signal plugin_leaderboard_updated(data: Dictionary)
   ```

3. **`scripts/plugins/scripted_runtime.gd`** — Add bridge functions in `_inject_bridge_api()` after line 425:
   ```gdscript
   api["leaderboard_submit"] = func(board_id: String, score: float, metadata):
       _bridge_leaderboard_submit(board_id, score, metadata)
   api["leaderboard_get"] = func(board_id: String, limit: int):
       return _bridge_leaderboard_get(board_id, limit)
   api["leaderboard_around_me"] = func(board_id: String, limit: int):
       return _bridge_leaderboard_around_me(board_id, limit)
   api["leaderboard_get_user"] = func(board_id: String, user_id: String):
       return _bridge_leaderboard_get_user(board_id, user_id)
   ```

4. **`scripts/plugins/plugin_context.gd`** — Add matching methods after line 93:
   ```gdscript
   func leaderboard_submit(board_id: String, score: float, metadata: Dictionary = {}) -> void
   func leaderboard_get(board_id: String, limit: int = 50) -> Array
   func leaderboard_around_me(board_id: String, limit: int = 10) -> Array
   func leaderboard_get_user(board_id: String, user_id: String) -> Dictionary
   ```

5. **`scripts/client/client_plugins.gd`** — Add routing for leaderboard REST calls and gateway event handler

6. **`addons/accordkit/models/plugin_manifest.gd`** — Add `services` field (after line 30):
   ```gdscript
   var services: Dictionary = {}  # {leaderboards: [...], achievements: [...], ...}
   ```

### Leaderboard Simulator — Editor (daccord-editor)

**Files to modify:**

1. **`scenes/plugins/scripted_runtime.gd`** — Add in-memory leaderboard state and bridge functions:
   ```gdscript
   var _leaderboards: Dictionary = {}  # board_id -> Array[{user_id, score, rank, metadata}]
   ```

   Add in `_inject_bridge_api()` after line 363:
   ```gdscript
   api["leaderboard_submit"] = func(board_id: String, score: float, metadata):
       _sim_leaderboard_submit(board_id, score, metadata)
   api["leaderboard_get"] = func(board_id: String, limit: int):
       return _sim_leaderboard_get(board_id, limit)
   api["leaderboard_around_me"] = func(board_id: String, limit: int):
       return _sim_leaderboard_around_me(board_id, limit)
   api["leaderboard_get_user"] = func(board_id: String, user_id: String):
       return _sim_leaderboard_get_user(board_id, user_id)
   ```

   Simulator logic:
   - Parse board config from manifest `services.leaderboards` array
   - Maintain sorted arrays per `board_id`
   - Apply operator (`best`/`set`/`increment`) — compare current vs submitted
   - Re-sort and assign ranks after each submit
   - Fire `on_plugin_event("leaderboard_updated", result)` immediately (loopback)
   - Persist across plugin reloads within the same editor session

2. **`scripts/editor.gd`** — No changes needed if simulator is self-contained in ScriptedRuntime. Optionally add leaderboard state display in the status panel.

### Extension Points for Adding Bridge Functions

Both runtimes follow the same pattern (editor at line 254, client at line 313):

```gdscript
func _inject_bridge_api() -> void:
    var api = _lua.create_table()
    # 1. Add lambda to api table
    api["function_name"] = func(args): _bridge_function(args)
    # 2. Inject into Lua globals
    _lua.globals["api"] = api
```

State tracking follows the timer/sound pattern (dictionaries keyed by ID):
- Timers: `_timers: Dictionary = {}` (scripted_runtime.gd line 38)
- Sounds: `_sounds: Dictionary = {}` (scripted_runtime.gd line 42)
- Leaderboards: `_leaderboards: Dictionary = {}` (same pattern)

## Implementation Status

- [x] Plugin manifest model (server: `PluginManifest` struct, client: `AccordPluginManifest`)
- [x] Plugin session lifecycle (create → lobby → running → ended)
- [x] `send_action()` passthrough (REST + gateway broadcast)
- [x] Bridge API — canvas, state, timers, audio, assets
- [x] Editor action loopback and user simulation
- [ ] Manifest `services` block parsing
- [ ] Key-value storage — server endpoints and database
- [ ] Key-value storage — client bridge API
- [ ] **Leaderboards — server endpoints and database**
- [ ] **Leaderboards — client bridge API**
- [ ] **Leaderboards — editor simulator**
- [ ] Achievements — server endpoints and database
- [ ] Achievements — client bridge API and toast
- [ ] Server-authoritative state sync — server
- [ ] Server-authoritative state sync — client bridge
- [ ] Matchmaking — server
- [ ] Matchmaking — client bridge
- [ ] Server-side timers
- [ ] Server-side timers — client bridge
- [ ] Virtual currencies — server
- [ ] Virtual currencies — client bridge
- [ ] Plugin announcements
- [ ] Cross-session statistics — server
- [ ] Cross-session statistics — client bridge
- [ ] Plugin info card — persistent data display
- [ ] Editor simulator — storage
- [ ] Editor simulator — achievements
- [ ] Editor simulator — server-authoritative state
- [ ] Editor simulator — matchmaking (stub)
- [ ] Editor simulator — server-side timers
- [ ] Editor simulator — virtual currencies
- [ ] Editor simulator — announcements
- [ ] Editor simulator — cross-session statistics
- [ ] Editor simulator — inspector panel

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No `services` field in PluginManifest | High | Server `PluginManifest` (models/plugin.rs:6-43) and client `AccordPluginManifest` (plugin_manifest.gd:1-97) have no `services` block — prerequisite for all platform services |
| No leaderboard database table | High | `plugin_leaderboard_records` table missing from migrations/019_plugins.sql — needs new migration |
| No leaderboard REST endpoints | High | `src/routes/plugins.rs` has no submit/query/around handlers; `src/routes/mod.rs` has no leaderboard route registration (currently ends at line 347) |
| No leaderboard bridge functions | High | `scripted_runtime.gd` `_inject_bridge_api()` (line 313) has no `leaderboard_*` functions; `plugin_context.gd` (93 lines) has no leaderboard methods |
| No `plugin_leaderboard_updated` gateway signal | High | `gateway_socket.gd` plugin signals (lines 73-78) don't include leaderboard events |
| No leaderboard REST client methods | High | `plugins_api.gd` (119 lines) has no leaderboard endpoint helpers |
| No editor leaderboard simulator | Medium | Editor `scripted_runtime.gd` has no in-memory leaderboard state or simulator functions |
| No period/reset logic for leaderboards | Medium | Leaderboard reset schedules (daily/weekly) need either background task or on-read archival in server |
| Editor missing `time()`/`ticks_ms()` bridge | Low | Editor scripted_runtime.gd has no time functions — client has them at scripted_runtime.gd:422-425 |
| No plugin info card UI | Low | No UI to display leaderboard ranks, achievements, or stats outside of active sessions |
| No client-side leaderboard caching | Low | `client_plugins.gd` has `_plugin_cache` for manifests but no cache for leaderboard data |

## Tasks

### PPS-1: Key-Value Storage — server endpoints and database
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** server, storage
- **Notes:** Add `plugin_storage` table, CRUD endpoints, scope-based ownership validation. Clear session-scoped data on session delete.

### PPS-2: Key-Value Storage — client bridge API
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** client, storage, bridge
- **Notes:** Add `storage_set/get/delete/list` to ScriptedRuntime bridge and PluginContext. Route through `send_action()` with type prefix. Handle `plugin_storage_updated` gateway event.

### PPS-3: Leaderboards — server endpoints and database
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** server, leaderboard
- **Notes:** Add `plugin_leaderboard_records` table (new migration), submit/query/around-me endpoints in `src/routes/plugins.rs`. Implement `best`/`set`/`increment` operators. Register routes in `src/routes/mod.rs` after line 347. Add upsert and query functions in `src/db/plugins.rs` (or new `src/db/plugin_leaderboards.rs`). Add `LeaderboardSubmit`, `LeaderboardRecord`, `LeaderboardQuery` structs to `src/models/plugin.rs`. Broadcast `plugin_leaderboard_updated` via existing `broadcast_plugin_event()` helper (line 695). Add reset schedule via background task or on-read check.

### PPS-4: Leaderboards — client bridge API
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** client, leaderboard, bridge
- **Notes:** Add `leaderboard_submit/get/around_me/get_user` to `scripted_runtime.gd` `_inject_bridge_api()` (after line 425) and `plugin_context.gd` (after line 93). Add 4 REST endpoint methods to `plugins_api.gd` (after line 118). Add `plugin_leaderboard_updated` signal to `gateway_socket.gd` (after line 78). Add routing in `client_plugins.gd`. Add `services` field to `AccordPluginManifest` (plugin_manifest.gd).

### PPS-5: Achievements — server endpoints and database
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** server, achievements
- **Notes:** Add `plugin_achievements` table, unlock/progress/list/stats endpoints. Auto-unlock when progress reaches target. Parse achievement definitions from manifest on install.

### PPS-6: Achievements — client bridge API and toast
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** client, achievements, bridge, ui
- **Notes:** Add `achievement_unlock/progress/list/stats` to bridge APIs. Show toast notification on `plugin_achievement_unlocked` event. Load achievement icon from plugin bundle assets.

### PPS-7: Server-authoritative state sync — server
- **Status:** open
- **Impact:** 3
- **Effort:** 3
- **Tags:** server, state
- **Notes:** Add state endpoints with atomic operations (set/merge/increment/append/remove). Path-based addressing into JSON document. Role-based write permissions. Broadcast diffs via gateway.

### PPS-8: Server-authoritative state sync — client bridge
- **Status:** open
- **Impact:** 3
- **Effort:** 2
- **Tags:** client, state, bridge
- **Notes:** Add `state_set/merge/increment/append/remove/get/get_all` to bridge APIs. Handle `plugin_state_updated` events and call back into plugin.

### PPS-9: Matchmaking — server
- **Status:** open
- **Impact:** 2
- **Effort:** 3
- **Tags:** server, matchmaking
- **Notes:** Add matchmaking queue data structure (in-memory or database-backed). Group by mode, match when criteria met, auto-create session. Dequeue on voice disconnect. Queue timeout cleanup.

### PPS-10: Matchmaking — client bridge
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** client, matchmaking, bridge
- **Notes:** Add `matchmaking_join/leave/status` to bridge APIs. Handle `plugin_match_found` and `plugin_matchmaking_status` gateway events.

### PPS-11: Server-side timers
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** server, timers
- **Notes:** Add `plugin_timers` table, timer CRUD endpoints. Background tick loop checks `fires_at`, sends `plugin_timer_fired` gateway event. Clear timers on session delete.

### PPS-12: Server-side timers — client bridge
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** client, timers, bridge
- **Notes:** Add `server_timer_create/cancel/list` to bridge APIs. Handle `plugin_timer_fired` events.

### PPS-13: Virtual currencies — server
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** server, economy
- **Notes:** Add `plugin_wallet` and `plugin_transactions` tables. Credit/debit/transfer endpoints with atomic balance checks. Parse currency definitions from manifest.

### PPS-14: Virtual currencies — client bridge
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** client, economy, bridge
- **Notes:** Add `wallet_credit/debit/balance/transfer/history` to bridge APIs. Handle `plugin_wallet_updated` events.

### PPS-15: Plugin announcements
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** server, client, announcements
- **Notes:** Add announce endpoint that creates a message attributed to the plugin. Reuse existing message_create pathway with bot/system author. Rate limit 5/min/session. Add `announce/announce_embed` to bridge APIs.

### PPS-16: Cross-session statistics — server
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** server, stats
- **Notes:** Add `plugin_stats` table, record/query/top endpoints. Implement increment/max/min/set operators. Stat-to-leaderboard and stat-to-achievement linkage from manifest.

### PPS-17: Cross-session statistics — client bridge
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** client, stats, bridge
- **Notes:** Add `stat_record/get/get_all/top` to bridge APIs.

### PPS-18: Manifest services schema
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** server, client, manifest
- **Notes:** Extend `PluginManifest` (models/plugin.rs:6-43) with `services: Option<serde_json::Value>`. Extend `AccordPluginManifest` (plugin_manifest.gd) with `services: Dictionary`. Server validates and pre-creates resources on plugin install. Client displays requested services in plugin info card.

### PPS-19: Plugin info card — persistent data display
- **Status:** open
- **Impact:** 1
- **Effort:** 2
- **Tags:** client, ui
- **Notes:** Extend ActivityCard or create PluginInfoPanel showing user's achievements, leaderboard rank, and stats for a plugin. Accessible from activity modal.

### PPS-20: Editor simulator — storage
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, storage
- **Notes:** Add in-memory KV storage simulator to daccord-editor `scenes/plugins/scripted_runtime.gd`. Inject `storage_set/get/delete/list` bridge functions. Scope user/session/global with session scope cleared on reload.

### PPS-21: Editor simulator — leaderboards
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, leaderboard
- **Notes:** Add in-memory leaderboard simulator to editor `scenes/plugins/scripted_runtime.gd`. Sorted arrays per board, `best/set/increment` operators, `around_me` pagination. Inject `leaderboard_submit/get/around_me/get_user` into bridge (after line 363). Configure from manifest `services.leaderboards`. Persist across reloads within same editor session.

### PPS-22: Editor simulator — achievements
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, achievements
- **Notes:** Add in-memory achievement simulator. Binary and progress-based unlock, auto-unlock on target. Inject `achievement_unlock/progress/list/stats` into bridge. Print unlock events to editor status. Configure from manifest `services.achievements`.

### PPS-23: Editor simulator — server-authoritative state
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** editor, state
- **Notes:** Add in-memory state document with atomic ops (set/merge/increment/append/remove) at dot-separated paths. Inject `state_set/merge/increment/append/remove/get/get_all` into bridge. Loop state diffs back as `_on_event("state_updated", ...)`.

### PPS-24: Editor simulator — matchmaking
- **Status:** open
- **Impact:** 1
- **Effort:** 1
- **Tags:** editor, matchmaking
- **Notes:** Stub matchmaking in editor — `matchmaking_join` immediately returns matched (single-client environment). Inject `matchmaking_join/leave/status` into bridge.

### PPS-25: Editor simulator — server-side timers
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, timers
- **Notes:** Add server timer simulator using Godot Timer nodes. Max 16, min 500ms delay. Fire `_on_event("timer_fired", ...)` to plugin. Inject `server_timer_create/cancel/list` into bridge. Clear on plugin reload.

### PPS-26: Editor simulator — virtual currencies
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, economy
- **Notes:** Add in-memory wallet simulator per user per currency. Server-enforced non-negative balances, transaction log. Inject `wallet_credit/debit/balance/transfer/history` into bridge. Configure initial balances from manifest `services.currencies`.

### PPS-27: Editor simulator — announcements
- **Status:** open
- **Impact:** 1
- **Effort:** 1
- **Tags:** editor, announcements
- **Notes:** Add announcement simulator that prints plugin messages to the editor console/status panel. Rate limit 5/min. Inject `announce/announce_embed` into bridge.

### PPS-28: Editor simulator — cross-session statistics
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, stats
- **Notes:** Add in-memory stats simulator with `increment/max/min/set` operators. Inject `stat_record/get/get_all/top` into bridge. Stats persist across plugin reloads within the same editor session.

### PPS-29: Editor simulator — inspector panel
- **Status:** open
- **Impact:** 2
- **Effort:** 2
- **Tags:** editor, ui
- **Notes:** Add a collapsible "Platform Services" section to the editor right panel showing live counts: storage keys, leaderboard entries, achievements unlocked, wallet balances, active timers, stats, announcements. Refresh on each service operation.
