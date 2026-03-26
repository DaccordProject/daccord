# Plugin Platform Services

Priority: 80
Depends on: Plugin System
Status: Planned

Server-provided backend services that plugin developers can use out of the box: persistent storage, leaderboards, achievements, matchmaking, server-authoritative state, timed events, virtual currencies, plugin announcements, and cross-session statistics. These services eliminate the need for plugin authors to build or host their own backends, enabling richer voice channel activities with minimal effort.

## Key Files

| File | Role |
|------|------|
| `scripts/plugins/scripted_runtime.gd` | Lua bridge — new storage/leaderboard/achievement/etc. functions added here |
| `scripts/plugins/plugin_context.gd` | Native plugin bridge — matching GDScript API surface |
| `scripts/client/client_plugins.gd` | Routes bridge calls to REST, handles gateway events for platform services |
| `addons/accordkit/rest/endpoints/plugins_api.gd` | AccordKit REST endpoint class — new platform service endpoints |
| `addons/accordkit/models/plugin_manifest.gd` | PluginManifest model — `services` block parsing |
| `addons/accordkit/gateway/gateway_socket.gd` | Gateway dispatch for `plugin_storage/leaderboard/achievement/etc.` events |
| `scenes/plugins/activity_card.gd` | Plugin info card — displays achievements, leaderboard rank, stats |
| `accordserver/src/routes/plugins.rs` | Server route handlers for all platform service endpoints |
| `accordserver/src/db/plugin_storage.rs` | Storage table CRUD |
| `accordserver/src/db/plugin_leaderboards.rs` | Leaderboard table queries and ranking |
| `accordserver/src/db/plugin_achievements.rs` | Achievement tracking and progress |
| `accordserver/src/db/plugin_stats.rs` | Cross-session statistics |
| `accordserver/src/db/plugin_wallet.rs` | Currency balances and transactions |

## Overview

Today plugins communicate via `send_action()` (a passthrough REST call) and LiveKit data channels (`send_data()`). Session state is ephemeral — when a session ends, everything is lost. Plugin developers who want persistence, ranking, or server authority must build it themselves. These platform services fill that gap by providing first-class, server-managed primitives that any plugin (scripted or native) can call through the existing bridge API.

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

## Signal Flow

```
Plugin calls bridge function (e.g., leaderboard_submit)
    -> ScriptedRuntime._bridge_leaderboard_submit(board_id, score, metadata)
        -> send_action({type: "leaderboard_submit", board_id, score, metadata})
            -> REST: POST /plugins/{id}/sessions/{sid}/actions
                -> Server routes to leaderboard handler
                -> Updates leaderboard table
                -> Broadcasts plugin_leaderboard_updated via gateway
    -> Gateway: plugin_leaderboard_updated event
        -> client_gateway_events.on_plugin_event()
            -> ClientPlugins._on_plugin_event(event_type, data)
                -> ScriptedRuntime.on_event("leaderboard_updated", data)
                    -> Lua: _on_event("leaderboard_updated", data)
                        -> Plugin updates its UI
```

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
- **Notes:** Add `plugin_leaderboard_records` table, submit/query/around-me endpoints. Implement `best`/`set`/`increment` operators. Add reset schedule via background task or on-read check.

### PPS-4: Leaderboards — client bridge API
- **Status:** open
- **Impact:** 3
- **Effort:** 1
- **Tags:** client, leaderboard, bridge
- **Notes:** Add `leaderboard_submit/get/around_me/get_user` to bridge APIs. Handle `plugin_leaderboard_updated` gateway event.

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
- **Notes:** Extend PluginManifest model with `services` block. Server validates and pre-creates resources on plugin install. Client displays requested services in plugin info card. AccordKit model updated.

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
- **Notes:** Add in-memory KV storage simulator to daccord-editor. Inject `storage_set/get/delete/list` bridge functions into ScriptedRuntime. Scope user/session/global with session scope cleared on reload.

### PPS-21: Editor simulator — leaderboards
- **Status:** open
- **Impact:** 2
- **Effort:** 1
- **Tags:** editor, leaderboard
- **Notes:** Add in-memory leaderboard simulator. Sorted arrays per board, `best/set/increment` operators, `around_me` pagination. Inject `leaderboard_submit/get/around_me/get_user` into bridge. Configure from manifest `services.leaderboards`.

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
