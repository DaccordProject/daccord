# PostgreSQL Support

Priority: 64
Depends on: None
Status: Complete

Dual SQLite/PostgreSQL backend via sqlx's `Any` driver, selected at runtime by `DATABASE_URL` environment variable, with separate migration chains and a SQLite-to-Postgres migration tool.

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
| `migrations/postgres/001_initial_schema.sql` | Postgres-native schema (covers migrations 001–017, includes `read_states` table) |
