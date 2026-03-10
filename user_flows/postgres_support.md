# PostgreSQL Support

Priority: 64
Depends on: None

## Overview
accordserver supports both SQLite and PostgreSQL as database backends via sqlx's `Any` driver. The backend is selected at runtime by the `DATABASE_URL` environment variable — SQLite remains the default for easy single-binary deployment, while PostgreSQL enables production deployments with concurrent connections, better write performance under load, and standard operational tooling (backups, replication, monitoring). This flow covers the dual-driver architecture, remaining gaps, and what's needed for full production readiness.

## User Steps
1. Instance admin installs PostgreSQL and creates a database (e.g. `accord`).
2. Admin sets `DATABASE_URL=postgres://user:pass@host/accord` in the environment.
3. Admin starts accordserver — migrations run automatically against Postgres.
4. Server operates identically to the SQLite path; no client changes required.

## Key Files
| File | Role |
|------|------|
| `Cargo.toml` | sqlx feature flags (`sqlite`, `postgres`, `any`) |
| `src/config.rs` | Reads `DATABASE_URL`, default is `sqlite:data/accord.db?mode=rwc` |
| `src/db/mod.rs` | `create_pool()` — detects backend via `url_is_postgres()`, creates `AnyPool` with backend-appropriate options. Provides `now_sql(is_postgres)` helper |
| `src/state.rs` | `pub db: AnyPool` + `db_is_postgres: bool` runtime flag |
| `src/main.rs` | Uses `db::url_is_postgres()` to set the `db_is_postgres` flag |
| `src/bin/seed.rs` | Test seeder, uses `create_pool()` for `AnyPool` |
| `src/db/users.rs` | User CRUD queries (migrated to `AnyRow`, `is_postgres` param) |
| `src/db/channels.rs` | Channel CRUD queries (migrated) |
| `src/db/messages.rs` | Message CRUD queries (migrated, `MIN(rowid)` replaced with `MIN(created_at)`) |
| `src/db/spaces.rs` | Space CRUD queries (migrated) |
| `src/db/roles.rs` | Role CRUD queries (migrated) |
| `src/db/members.rs` | Member/member_role queries (migrated, conditional `INSERT OR IGNORE` / `ON CONFLICT`) |
| `src/db/bans.rs` | Ban queries (migrated) |
| `src/db/emojis.rs` | Emoji CRUD queries (migrated) |
| `src/db/soundboard.rs` | Soundboard sound queries (migrated) |
| `src/db/settings.rs` | Server settings singleton (migrated) |
| `src/db/admin.rs` | Admin management queries (migrated) |
| `src/db/dm_participants.rs` | DM participant queries (migrated) |
| `src/db/read_states.rs` | Read state queries (migrated to `AnyPool`, `is_postgres` param, `now_sql()`) |
| `src/db/permission_overwrites.rs` | Permission overwrite upserts (uses `ON CONFLICT ... DO UPDATE`) |
| `src/db/attachments.rs` | Attachment queries (migrated) |
| `src/routes/read_states.rs` | REST endpoints for read state ack + unread channels |
| `src/bin/migrate_to_postgres.rs` | SQLite → PostgreSQL data migration CLI tool |
| `tests/common/mod.rs` | Test infrastructure with `DATABASE_URL`-driven backend selection |
| `.github/workflows/test.yml` | CI workflow with SQLite + PostgreSQL test matrix |
| `migrations/` | SQLite migration files |
| `migrations/017_read_states.sql` | SQLite read_states table migration |
| `migrations/postgres/001_initial_schema.sql` | Postgres-native schema (covers migrations 001–017, includes `read_states` table) |

## Implementation Details

### Current Database Stack
- **ORM:** None. Raw SQL via [sqlx](https://github.com/launchbadge/sqlx) with runtime query strings (`sqlx::query(...)`, not compile-time `query!()` macros).
- **Driver:** `sqlx::Any` — runtime polymorphism via `AnyPool`, `AnyRow`, `AnyConnectOptions`. Backend determined by `DATABASE_URL` prefix at startup.
- **Pool:** `AnyPoolOptions` in `src/db/mod.rs`. SQLite path uses WAL journal mode and FK enforcement. Postgres path uses standard `PgConnectOptions`.
- **Migrations:** Separate migration directories — `migrations/` for SQLite, `migrations/postgres/` for Postgres. `create_pool()` selects the correct set based on the URL.
- **Row extraction:** Manual `row.get("column")` on `sqlx::any::AnyRow` in all migrated db modules.
- **SQL dialect abstraction:** `now_sql(is_postgres: bool)` helper returns `"NOW()"` or `"datetime('now')"`. Most db modules accept `is_postgres` and use conditional SQL for `INSERT OR IGNORE` vs `ON CONFLICT DO NOTHING`.
- **Config:** Single env var `DATABASE_URL`, default `sqlite:data/accord.db?mode=rwc`.

### Remaining SQLite-Specific Code

No remaining SQLite-specific code. All db modules use `AnyPool` with `is_postgres` conditionals where needed.

### Architecture Decisions (Adopted)

**Driver approach: `sqlx::Any` (runtime polymorphism)**
- Single codebase, database chosen entirely by `DATABASE_URL` format.
- Bind parameter syntax: `Any` driver normalizes to `?` placeholders, so existing queries did not need rewriting.
- Database-specific SQL (`INSERT OR IGNORE`, `datetime('now')`) abstracted into helper functions that emit the correct SQL per backend.

**Migration strategy: Fresh Postgres schema + separate SQLite chain**
- Existing SQLite deployments keep their incremental migration chain under `migrations/`.
- Postgres deployments get a single idiomatic `001_initial_schema.sql` under `migrations/postgres/`.

### Tables (Complete List — 26 tables)

| Table | Primary Key | Notes |
|-------|-------------|-------|
| `users` | `id TEXT` | Boolean columns stored as `INTEGER` (SQLite) / `BOOLEAN` (Postgres) |
| `spaces` | `id TEXT` | `slug UNIQUE`, `owner_id` FK |
| `channels` | `id TEXT` | `space_id` FK, `parent_id` self-ref |
| `messages` | `id TEXT` | JSON columns: `mentions`, `mention_roles`, `embeds` |
| `roles` | `id TEXT` | JSON `permissions` column |
| `members` | `(user_id, space_id)` | Composite PK |
| `member_roles` | `(user_id, space_id, role_id)` | Composite PK |
| `permission_overwrites` | `(id, channel_id)` | JSON `allow`/`deny` columns |
| `invites` | `code TEXT` | Nullable `channel_id` |
| `user_tokens` | `token_hash TEXT` | — |
| `bot_tokens` | `token_hash TEXT` | — |
| `applications` | `id TEXT` | — |
| `bans` | `(user_id, space_id)` | — |
| `attachments` | `id TEXT` | — |
| `reactions` | `(message_id, user_id, emoji_name)` | Uses `MIN(created_at)` for ordering |
| `pinned_messages` | `(channel_id, message_id)` | — |
| `dm_participants` | `(channel_id, user_id)` | — |
| `emojis` | `id TEXT` | Image metadata columns |
| `emoji_roles` | `(emoji_id, role_id)` | — |
| `soundboard_sounds` | `id TEXT` | `volume REAL` |
| `relationships` | `id TEXT` | `UNIQUE(user_id, target_user_id)` |
| `server_settings` | `id INTEGER CHECK(id=1)` | Singleton pattern |
| `backup_codes` | `id TEXT` | 2FA backup codes per user |
| `channel_mutes` | `(user_id, channel_id)` | Per-user channel mutes |
| `read_states` | `(user_id, channel_id)` | — |
| `reports` | `id TEXT` | — |

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
        │            ├── SQLite path: AnyConnectOptions + WAL + FK pragma
        │            └── Postgres path: AnyConnectOptions + standard options
        │
        ▼
  sqlx::migrate!() ──► run correct migration set
        │                ├── SQLite: migrations/
        │                └── Postgres: migrations/postgres/
        │
        ▼
  src/state.rs ──► AppState { db: AnyPool, db_is_postgres: bool }
        │
        ▼
  All db modules ──► sqlx::query(...) with AnyPool
  All routes         (now_sql() + conditional SQL for dialect differences)
  Gateway
```

## Implementation Status
- [x] SQLite backend fully functional
- [x] sqlx migration system in place
- [x] All queries use parameterized binds (no SQL injection risk)
- [x] `DATABASE_URL` env var configurable
- [x] `postgres` and `any` features in `Cargo.toml`
- [x] `AnyPool` support in pool creation (`src/db/mod.rs`)
- [x] `AnyRow` in all row extraction functions
- [x] `now_sql(is_postgres)` helper for `datetime('now')` / `NOW()` abstraction
- [x] `INSERT OR IGNORE` → `ON CONFLICT DO NOTHING` conditional in all db modules
- [x] `INSERT OR REPLACE` → `ON CONFLICT ... DO UPDATE` migration
- [x] `MIN(rowid)` replaced with `MIN(created_at)` in reaction query
- [x] Postgres-native migration (`migrations/postgres/001_initial_schema.sql`) with `BOOLEAN`, `TIMESTAMPTZ`, `NOW()`
- [x] `state.rs` uses `AnyPool` + `db_is_postgres` runtime flag
- [x] Migrate `read_states.rs` to `AnyPool` with `is_postgres` param
- [x] Add `read_states` table to Postgres migration
- [x] Fix conditional `INSERT OR IGNORE` / `ON CONFLICT DO NOTHING` in `seed.rs` reactions query
- [x] SQLite → Postgres data migration tool (`src/bin/migrate_to_postgres.rs`)
- [x] CI test matrix for both backends (`.github/workflows/test.yml`)
- [x] REST endpoints for read states (`src/routes/read_states.rs`)
- [x] Documentation for Postgres deployment

## Postgres Deployment Guide

### Prerequisites
- PostgreSQL 16+ installed and running
- An empty database created for accordserver (e.g. `accord`)
- A database user with full privileges on that database

### Fresh Postgres Deployment

1. **Create the database and user:**
   ```sql
   CREATE USER accord WITH PASSWORD 'your_secure_password';
   CREATE DATABASE accord OWNER accord;
   ```

2. **Set the `DATABASE_URL` environment variable:**
   ```bash
   export DATABASE_URL="postgres://accord:your_secure_password@localhost:5432/accord"
   ```
   Both `postgres://` and `postgresql://` prefixes are accepted.

3. **Start accordserver:**
   ```bash
   ./accordserver
   ```
   Migrations run automatically on startup — no manual SQL is needed. The server detects the Postgres URL prefix and applies `migrations/postgres/001_initial_schema.sql`, which creates all 26 tables with Postgres-native types (`BOOLEAN`, `TIMESTAMPTZ`, `NOW()`).

4. **Verify:** The server logs should show successful migration and pool creation. The API behaves identically to the SQLite path — no client changes are required.

### Migrating from SQLite to Postgres

For existing deployments that want to switch from SQLite to Postgres:

1. **Ensure Postgres is set up** (database created, empty, no prior data).

2. **Run the migration tool:**
   ```bash
   SQLITE_URL="sqlite:data/accord.db?mode=rwc" \
   POSTGRES_URL="postgres://accord:your_secure_password@localhost:5432/accord" \
   cargo run --bin accord-migrate-pg
   ```

3. **What it does:**
   - Connects to both databases and runs migrations on each
   - Copies all 26 tables in dependency order (users → spaces → channels → … → reports)
   - Uses `ON CONFLICT DO NOTHING` to skip duplicates safely
   - Reports per-table row counts and warns on any insert failures
   - Prints a total rows-transferred summary at the end

4. **After migration:** Update `DATABASE_URL` to point to Postgres and restart the server.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite:data/accord.db?mode=rwc` | Database connection URL. Prefix determines backend |
| `PORT` | `39099` | HTTP server port |
| `ACCORD_TEST_MODE` | unset | Set to `true` or `1` for test mode |
| `TOTP_ENCRYPTION_KEY` | unset | Optional key for encrypting TOTP secrets |
| `ACCORD_STORAGE_PATH` | `./data/cdn` | File storage path for uploads |

### Connection Pool

- Pool size: 5 max connections (for both backends)
- Postgres path uses standard `PgConnectOptions` via `AnyConnectOptions`
- No additional tuning is required for typical deployments

### CI Reference

The GitHub Actions workflow (`.github/workflows/test.yml`) provides a working Postgres setup example:
```yaml
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_USER: accord
      POSTGRES_PASSWORD: accord_test
      POSTGRES_DB: accord_test
    options: >-
      --health-cmd pg_isready
      --health-interval 10s
      --health-timeout 5s
      --health-retries 5
    ports:
      - 5432:5432
env:
  DATABASE_URL: "postgres://accord:accord_test@localhost:5432/accord_test"
```

## Gaps / TODO
| Gap | Severity | Notes |
|-----|----------|-------|
| — | — | No remaining gaps |
