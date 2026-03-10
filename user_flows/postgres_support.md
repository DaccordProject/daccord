# PostgreSQL Support

## Overview
accordserver currently uses SQLite as its sole database backend. Adding PostgreSQL support enables production deployments with concurrent connections, better write performance under load, and standard operational tooling (backups, replication, monitoring). This flow covers the full migration path: dual-driver support in sqlx, schema translation, query rewriting, and runtime database selection via `DATABASE_URL`.

## User Steps
1. Instance admin installs PostgreSQL and creates a database (e.g. `accord`).
2. Admin sets `DATABASE_URL=postgres://user:pass@host/accord` in the environment.
3. Admin starts accordserver — migrations run automatically against Postgres.
4. Server operates identically to the SQLite path; no client changes required.

## Key Files
| File | Role |
|------|------|
| `Cargo.toml` | sqlx feature flags (`sqlite` and/or `postgres`) |
| `src/config.rs` | Reads `DATABASE_URL`, default is `sqlite:data/accord.db?mode=rwc` (line 100) |
| `src/db/mod.rs` | `create_pool()` — SQLite-specific pool options (WAL, FK pragma, create_if_missing) |
| `src/state.rs` | `pub db: SqlitePool` hardcoded pool type (line 27) |
| `src/main.rs` | `strip_prefix("sqlite:")` for directory creation |
| `src/bin/seed.rs` | Test seeder, hardcoded `SqlitePool` |
| `src/db/users.rs` | User CRUD queries |
| `src/db/channels.rs` | Channel CRUD queries |
| `src/db/messages.rs` | Message CRUD queries, `MIN(rowid)` in reaction aggregation (line 419) |
| `src/db/spaces.rs` | Space CRUD queries |
| `src/db/roles.rs` | Role CRUD queries |
| `src/db/members.rs` | Member/member_role queries, `INSERT OR IGNORE` |
| `src/db/bans.rs` | Ban queries, `INSERT OR REPLACE` |
| `src/db/emojis.rs` | Emoji CRUD queries |
| `src/db/soundboard.rs` | Soundboard sound queries |
| `src/db/settings.rs` | Server settings singleton |
| `src/db/admin.rs` | Admin management queries |
| `src/db/dm_participants.rs` | DM participant queries |
| `src/db/permission_overwrites.rs` | Permission overwrite upserts (already uses `ON CONFLICT ... DO UPDATE`) |
| `src/db/attachments.rs` | Attachment queries |
| `src/routes/auth.rs` | Auth routes with inline `INSERT OR IGNORE` queries |
| `src/routes/reactions.rs` | Reaction routes with `INSERT OR IGNORE` |
| `src/gateway/mod.rs` | Token expiry check using `datetime('now')` |
| `src/middleware/auth.rs` | Token timestamp string comparison |
| `migrations/` | 13 migration files with SQLite DDL |

## Implementation Details

### Current Database Stack
- **ORM:** None. Raw SQL via [sqlx](https://github.com/launchbadge/sqlx) with runtime query strings (`sqlx::query(...)`, not compile-time `query!()` macros).
- **Pool:** `SqlitePoolOptions::new().max_connections(5)` with WAL journal mode and FK enforcement (line 10–25 of `src/db/mod.rs`).
- **Migrations:** sqlx's built-in `sqlx::migrate!()` macro reads the `migrations/` directory at compile time.
- **Row extraction:** Manual `row.get("column")` on `sqlx::sqlite::SqliteRow` in 6 db modules (`messages`, `channels`, `spaces`, `members`, `users`, `attachments`).
- **Config:** Single env var `DATABASE_URL`, default `sqlite:data/accord.db?mode=rwc`.

### SQLite-Specific Constructs to Replace

#### 1. Bind parameter placeholders: `?` → `$1, $2, ...`
SQLite uses `?` for positional bind params. PostgreSQL uses `$1`, `$2`, etc. This is the most pervasive change — roughly 150+ bind sites across all 16 db modules, route files, and the gateway. Using sqlx's `query!()` macros would make this automatic, but the codebase currently uses runtime strings exclusively.

#### 2. `datetime('now')` → `NOW()`
Found in every db module and the gateway (20+ occurrences). SQLite stores timestamps as TEXT with `datetime('now')`; Postgres uses native `TIMESTAMPTZ` with `NOW()`.

**Source locations:**
- `src/db/users.rs` — 3 occurrences
- `src/db/channels.rs` — 1
- `src/db/messages.rs` — 2
- `src/db/spaces.rs` — 1
- `src/db/roles.rs` — 1
- `src/db/emojis.rs` — 1
- `src/db/soundboard.rs` — 2
- `src/db/settings.rs` — 1
- `src/db/admin.rs` — 2
- `src/gateway/mod.rs` — 1 (token expiry check)

#### 3. `INSERT OR IGNORE INTO` → `INSERT INTO ... ON CONFLICT DO NOTHING`
Used in 7 locations: `db/messages.rs` (pinned), `db/members.rs` (members, member_roles), `db/dm_participants.rs`, `db/admin.rs`, `routes/auth.rs`, `routes/reactions.rs`, `bin/seed.rs`.

#### 4. `INSERT OR REPLACE INTO` → `INSERT INTO ... ON CONFLICT (...) DO UPDATE SET ...`
Used in `db/bans.rs` and `migrations/011_server_settings.sql`.

#### 5. `MIN(rowid)` — SQLite virtual column
`src/db/messages.rs` (line 419) uses `ORDER BY message_id, MIN(rowid)` for reaction aggregation ordering. `rowid` does not exist in Postgres. Replace with `MIN(created_at)` or add a serial column to `reactions`.

#### 6. `PRAGMA foreign_keys`
`migrations/003_space_invites_and_public.sql` uses `PRAGMA foreign_keys = OFF/ON` to disable FK checks during table recreation. Postgres enforces FKs natively and uses `ALTER TABLE ... DISABLE TRIGGER ALL` or deferred constraints instead. For Postgres migrations, the table recreation pattern isn't needed — Postgres supports `ALTER TABLE ... ALTER COLUMN` and `ALTER TABLE ... DROP COLUMN` natively.

#### 7. Type differences in schema DDL
| SQLite | PostgreSQL | Columns affected |
|--------|-----------|-----------------|
| `INTEGER` for booleans | `BOOLEAN` | `bot`, `system`, `is_admin`, `disabled`, `force_password_reset`, `tts`, `pinned`, `mention_everyone`, `nsfw`, `hoist`, `managed`, `mentionable`, `pending`, `deaf`, `mute`, `temporary`, `animated`, `available`, `require_colons`, `public`, `archived`, `bot_public` |
| `TEXT` for timestamps | `TIMESTAMPTZ` | All `created_at`, `updated_at`, `edited_at`, `expires_at`, `joined_at`, `pinned_at`, `premium_since`, `timed_out_until` |
| `TEXT DEFAULT (datetime('now'))` | `TIMESTAMPTZ DEFAULT NOW()` | All auto-timestamped columns |
| `INTEGER DEFAULT 0` (bool) | `BOOLEAN DEFAULT FALSE` | All boolean columns with defaults |

#### 8. Timestamp string comparison in Rust
`src/middleware/auth.rs` and `src/routes/auth.rs` compare token expiry timestamps as strings (e.g., `if row.1 < now`). With Postgres native timestamps, the Rust layer should use `chrono::DateTime` types for proper comparison.

### Hardcoded SQLite Types in Rust

| Location | Current | Postgres equivalent |
|----------|---------|-------------------|
| `src/state.rs:27` | `pub db: SqlitePool` | `PgPool` (or `AnyPool`) |
| `src/db/mod.rs` | `SqliteConnectOptions`, `SqliteJournalMode`, `SqlitePoolOptions` | `PgConnectOptions`, `PgPoolOptions` |
| `src/db/messages.rs` | `fn row_to_message(row: SqliteRow)` | `PgRow` (or generic `Row`) |
| `src/db/channels.rs` | `fn row_to_channel(row: SqliteRow)` | `PgRow` |
| `src/db/spaces.rs` | `fn row_to_space(row: SqliteRow)` | `PgRow` |
| `src/db/members.rs` | `fn row_to_member(row: SqliteRow)` | `PgRow` |
| `src/db/users.rs` | `fn row_to_user(row: SqliteRow)` | `PgRow` |
| `src/db/attachments.rs` | `fn row_to_attachment(row: SqliteRow)` | `PgRow` |
| `src/main.rs` | `strip_prefix("sqlite:")` directory creation | Skip or use Postgres-aware startup |
| `src/bin/seed.rs` | `SqlitePool` | `PgPool` |

### Approach: sqlx `Any` Driver vs Dual-Driver

**Option A — `sqlx::Any` (runtime polymorphism):**
- sqlx provides `AnyPool`, `AnyRow`, and `AnyConnectOptions` that work with any supported backend at runtime.
- Pros: Single codebase, database chosen entirely by `DATABASE_URL` format.
- Cons: No compile-time query checking even with macros; `AnyRow` has limited type mapping; some database-specific features (e.g., Postgres `RETURNING`, `LISTEN/NOTIFY`) unavailable through the `Any` abstraction.
- Bind parameter syntax: `Any` driver normalizes to `?` placeholders, so existing queries would NOT need rewriting.

**Option B — Feature-flag compilation (e.g., `#[cfg(feature = "postgres")]`):**
- Compile the server for one backend at a time using Cargo features.
- Pros: Full access to backend-specific features; compile-time query checking possible.
- Cons: Conditional compilation throughout; two sets of migrations; more maintenance.

**Option C — Postgres-only (drop SQLite):**
- Replace SQLite entirely with Postgres.
- Pros: Simplest code; no conditional logic.
- Cons: Removes easy single-binary deployment that SQLite provides.

**Recommended: Option A (`sqlx::Any`)** for the initial migration. It minimizes code changes (no placeholder rewriting, no conditional compilation), keeps SQLite available for development/small deployments, and lets the `DATABASE_URL` determine the backend at runtime. Database-specific SQL (`INSERT OR IGNORE`, `datetime('now')`) would need abstraction into helper functions that emit the correct SQL per backend.

### Migration Strategy for Schema Files

The existing 13 migration files use SQLite DDL. Two approaches:

**Approach 1 — Parallel migration directories:**
sqlx supports `migrations/sqlite/` and `migrations/postgres/` with a custom migrator. Each backend gets its own migration files with native DDL.

**Approach 2 — Compatible SQL migrations:**
Write new migrations in a subset of SQL that works on both SQLite and Postgres. Use helper migration logic where they diverge. This is harder because the existing migrations use `PRAGMA`, `INSERT OR IGNORE`, and SQLite type conventions.

**Approach 3 — Fresh Postgres schema + data migration tool:**
Write a single `001_initial_schema.sql` for Postgres that creates all tables with correct types. Provide a separate `migrate_sqlite_to_postgres` CLI tool for existing deployments. New Postgres deployments start clean.

**Recommended: Approach 3** for clean separation. Existing SQLite deployments keep their migration chain. New Postgres deployments get a fresh, idiomatic schema.

### Tables (Complete List — 23 tables)

| Table | Primary Key | Notes |
|-------|-------------|-------|
| `users` | `id TEXT` | Boolean columns stored as `INTEGER` |
| `spaces` | `id TEXT` | `slug UNIQUE`, `owner_id` FK |
| `channels` | `id TEXT` | `space_id` FK, `parent_id` self-ref |
| `messages` | `id TEXT` | JSON columns: `mentions`, `mention_roles`, `embeds` |
| `roles` | `id TEXT` | JSON `permissions` column |
| `members` | `(user_id, space_id)` | Composite PK |
| `member_roles` | `(user_id, space_id, role_id)` | Composite PK |
| `permission_overwrites` | `(id, channel_id)` | JSON `allow`/`deny` columns |
| `invites` | `code TEXT` | Nullable `channel_id` |
| `user_tokens` | `token_hash TEXT` | String timestamp comparison in auth |
| `bot_tokens` | `token_hash TEXT` | — |
| `applications` | `id TEXT` | — |
| `bans` | `(user_id, space_id)` | Uses `INSERT OR REPLACE` |
| `attachments` | `id TEXT` | — |
| `reactions` | `(message_id, user_id, emoji_name)` | `MIN(rowid)` used for ordering |
| `pinned_messages` | `(channel_id, message_id)` | — |
| `dm_participants` | `(channel_id, user_id)` | — |
| `emojis` | `id TEXT` | Image metadata columns |
| `emoji_roles` | `(emoji_id, role_id)` | — |
| `soundboard_sounds` | `id TEXT` | `volume REAL` |
| `relationships` | `id TEXT` | `UNIQUE(user_id, target_user_id)` |
| `server_settings` | `id INTEGER CHECK(id=1)` | Singleton pattern |

## Signal Flow

No client-side signal changes. The daccord Godot client communicates with accordserver via REST + WebSocket — the database backend is transparent to the client.

```
DATABASE_URL env var
        │
        ▼
  src/config.rs ──► detect prefix ("sqlite:" vs "postgres://")
        │
        ▼
  src/db/mod.rs ──► create_pool()
        │            ├── SQLite path: SqlitePoolOptions + WAL + FK pragma
        │            └── Postgres path: PgPoolOptions + standard options
        │
        ▼
  sqlx::migrate!() ──► run correct migration set
        │
        ▼
  src/state.rs ──► AppState { db: AnyPool }
        │
        ▼
  All db modules ──► sqlx::query(...) with AnyPool
  All routes         (helper fns abstract SQL dialect differences)
  Gateway
```

## Implementation Status
- [x] SQLite backend fully functional
- [x] sqlx migration system in place (13 migrations)
- [x] All queries use parameterized binds (no SQL injection risk)
- [x] `DATABASE_URL` env var already configurable
- [ ] `postgres` feature in `Cargo.toml`
- [ ] `AnyPool` / `PgPool` support in pool creation
- [ ] `AnyRow` / `PgRow` support in row extraction functions
- [ ] `datetime('now')` → `NOW()` abstraction
- [ ] `INSERT OR IGNORE` → `ON CONFLICT DO NOTHING` abstraction
- [ ] `INSERT OR REPLACE` → `ON CONFLICT ... DO UPDATE` abstraction
- [ ] `MIN(rowid)` removal in reaction query
- [ ] Postgres-native migration set (all 23 tables)
- [ ] Boolean columns as `BOOLEAN` in Postgres schema
- [ ] Timestamp columns as `TIMESTAMPTZ` in Postgres schema
- [ ] `chrono::DateTime` for timestamp comparison in auth middleware
- [ ] SQLite → Postgres data migration tool
- [ ] CI test matrix for both backends
- [ ] Documentation for Postgres deployment

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| `Cargo.toml` only enables `sqlite` feature | High | Add `postgres` (and optionally `any`) feature to sqlx dependency |
| `SqlitePool` hardcoded in `state.rs:27` | High | Change to `AnyPool` or use feature-gated type alias |
| `SqliteRow` in 6 `row_to_*` functions | High | Change to `AnyRow` or `PgRow`; affects `messages`, `channels`, `spaces`, `members`, `users`, `attachments` |
| `?` bind placeholders everywhere | High | ~150+ sites; `AnyPool` normalizes these automatically, but direct Postgres would need `$1..$N` |
| `datetime('now')` in 20+ query strings | High | Abstract into helper fn returning correct SQL per backend |
| `INSERT OR IGNORE` in 7 locations | High | Abstract into `ON CONFLICT DO NOTHING` for Postgres |
| `INSERT OR REPLACE` in `bans.rs` | Medium | Rewrite as `ON CONFLICT ... DO UPDATE SET` |
| `MIN(rowid)` in `messages.rs:419` | Medium | Replace with `MIN(created_at)` or add serial column to `reactions` |
| `PRAGMA` in migration 003 | Medium | Postgres migrations must not use `PRAGMA`; use native DDL instead |
| Timestamp string comparison in auth | Medium | `middleware/auth.rs` and `routes/auth.rs` compare timestamps as strings; use `chrono` types with Postgres |
| `strip_prefix("sqlite:")` in `main.rs` | Low | Postgres URLs don't need directory creation; guard with URL prefix check |
| `create_if_missing(true)` in pool setup | Low | SQLite-only option; Postgres databases must be created externally |
| No Postgres CI test job | Low | Add a GitHub Actions job with a Postgres service container |
| `server_settings` singleton `CHECK(id=1)` | Low | Works in Postgres but `INSERT OR IGNORE` in migration 011 needs rewriting |
| `seed.rs` hardcodes `SqlitePool` | Low | Update test seeder for `AnyPool`/`PgPool` |
