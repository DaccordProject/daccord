# One-Click Deploy

## Overview

One-click deploy enables users to spin up their own accordserver instance on popular hosting platforms with minimal configuration. The server ships as a single Docker image (`ghcr.io/daccordproject/accordserver`) that auto-creates its database, runs migrations, and generates a default invite on first boot — making it ideal for push-button deployment.

## User Steps

1. User clicks a "Deploy" button on a hosting platform (or the daccord website)
2. Platform provisions a container from the Docker image and prompts for environment variables
3. User fills in required config (domain, optional LiveKit credentials, optional Postgres URL)
4. Platform builds/pulls the image, starts the container, and assigns a public URL
5. Server starts, auto-creates the SQLite database (or connects to Postgres), runs migrations, and prints a default invite code
6. User connects their daccord client to the server URL and registers an account using the invite

## Platform Support Matrix

| Platform | Method | Voice Support | Persistent Storage | TLS | Complexity |
|----------|--------|---------------|-------------------|-----|------------|
| Railway | `railway.toml` + Deploy button | Via external LiveKit | Volume mount | Automatic | Low |
| Render | `render.yaml` blueprint | Via external LiveKit | Persistent disk | Automatic | Low |
| Fly.io | `fly.toml` + `fly launch` | Via external LiveKit | Volume | Automatic | Low |
| DigitalOcean App Platform | `app.yaml` spec | Via external LiveKit | N/A (use managed PG) | Automatic | Low |
| Docker Compose (VPS) | `docker-compose.yml` | Built-in LiveKit sidecar | Volume mount | Via Caddy | Medium |
| Coolify | Docker Compose import | Built-in LiveKit sidecar | Volume mount | Automatic | Low |

## Signal Flow

```
User clicks "Deploy to X"
    → Platform pulls ghcr.io/daccordproject/accordserver:latest
    → Container starts with env vars (PORT, DATABASE_URL, etc.)
    → main.rs: Config::from_env() reads environment (config.rs:61-131)
    → main.rs: run_main_server() creates DB pool, runs migrations (main.rs:61-189)
    → main.rs: ensure_default_invite() generates invite code (main.rs:156-163)
    → Server binds 0.0.0.0:PORT (main.rs:177-188)
    → Platform assigns public URL + TLS
    → User connects daccord client to the URL
```

## Key Files

| File | Role |
|------|------|
| `../accordserver/Dockerfile` | Multi-stage Rust build → slim Debian runtime image |
| `../accordserver/docker-compose.yml` | Full stack: accordserver + LiveKit + Caddy (SQLite) |
| `../accordserver/docker-compose.postgres.yml` | Full stack with PostgreSQL backend |
| `../accordserver/.github/workflows/docker-publish.yml` | CI pipeline publishing image to GHCR on version tags |
| `../accordserver/src/config.rs` | All env var parsing — `Config::from_env()` (line 61) |
| `../accordserver/src/main.rs` | Server startup, DB init, default invite, banner (line 12) |
| `../accordserver/Cargo.toml` | Rust dependencies, binary targets (v0.1.17) |
| `../accordserver/README.md` | Existing Docker/config documentation |

## Implementation Details

### Docker Image

The `Dockerfile` uses a two-stage build (line 1-46):
- **Build stage**: `rust:1.88-bookworm`, dependency caching via dummy `src/`, real build with `GIT_SHA` arg
- **Runtime stage**: `debian:bookworm-slim` with only `ca-certificates` and `libsqlite3-0`
- Default env: `PORT=39099`, SQLite at `/app/data/accord.db`, debug logging
- Single `CMD ["./accordserver"]` — no entrypoint scripts needed

The image is published to `ghcr.io/daccordproject/accordserver` via GitHub Actions on `v*` tags (docker-publish.yml). Tags include semver, major.minor, SHA, and `latest`.

### Environment Variables

All configuration is via env vars parsed in `config.rs:from_env()` (line 61-131):

| Variable | Default | Required | Notes |
|----------|---------|----------|-------|
| `PORT` | `39099` | No | Server listen port |
| `DATABASE_URL` | `sqlite:data/accord.db?mode=rwc` | No | SQLite or `postgres://` connection string |
| `ACCORD_STORAGE_PATH` | `./data/cdn` | No | CDN file storage path |
| `RUST_LOG` | `accordserver=debug,tower_http=debug` | No | Log filter |
| `LIVEKIT_INTERNAL_URL` | — | No | LiveKit server-to-server URL |
| `LIVEKIT_EXTERNAL_URL` | — | No | LiveKit client-facing URL |
| `LIVEKIT_API_KEY` | — | No | Required if LiveKit URL set |
| `LIVEKIT_API_SECRET` | — | No | Required if LiveKit URL set |
| `MASTER_SERVER_PUBLIC_URL` | — | No | Public URL for master server discovery |
| `MASTER_SERVER_NAME` | `Accord Server` | No | Display name in master server directory |
| `TOTP_ENCRYPTION_KEY` | — | No | AES key for TOTP secret encryption |
| `MCP_API_KEY` | — | No | API key for MCP endpoint |

### Zero-Config Startup

The server is designed for zero-config operation (main.rs:61-189):
1. Creates database directory if using SQLite (line 65-77)
2. Creates DB pool and runs migrations automatically (line 79-81)
3. Creates CDN storage subdirectories (line 116-121)
4. Generates a default invite code on first boot (line 156-163)
5. Voice is optional — server works without LiveKit, just logs a warning (line 85-112)

This means deploying with just `PORT` and `DATABASE_URL` produces a working server.

### Existing Docker Compose Stacks

**SQLite stack** (`docker-compose.yml`): accordserver + LiveKit + Caddy reverse proxy with auto-TLS. Uses Docker labels for Caddy routing (line 22-23). Requires an external `app-network` Docker network.

**PostgreSQL stack** (`docker-compose.postgres.yml`): Adds Postgres 17 with healthcheck-based startup ordering (line 32-34). Documents password handling and volume lifecycle.

### Platform-Specific Deploy Configs

The following configs need to be created in the accordserver repo to enable one-click deploys:

#### Railway (`railway.toml`)
```toml
[build]
dockerfilePath = "Dockerfile"

[deploy]
startCommand = "./accordserver"
healthcheckPath = "/api/v1/health"
healthcheckTimeout = 30
restartPolicyType = "ON_FAILURE"

[[volumes]]
mountPath = "/app/data"
```

#### Render (`render.yaml`)
```yaml
services:
  - type: web
    name: accordserver
    runtime: docker
    dockerfilePath: ./Dockerfile
    healthCheckPath: /api/v1/health
    disk:
      name: accord-data
      mountPath: /app/data
      sizeGB: 1
    envVars:
      - key: PORT
        value: "39099"
      - key: DATABASE_URL
        value: "sqlite:/app/data/accord.db?mode=rwc"
      - key: ACCORD_STORAGE_PATH
        value: "/app/data/cdn"
```

#### Fly.io (`fly.toml`)
```toml
app = "accordserver"
primary_region = "iad"

[build]
  dockerfile = "Dockerfile"

[http_service]
  internal_port = 39099
  force_https = true

[mounts]
  source = "accord_data"
  destination = "/app/data"

[checks]
  [checks.health]
    type = "http"
    port = 39099
    path = "/api/v1/health"
    interval = "10s"
    timeout = "5s"
```

#### DigitalOcean (`app.yaml`)
```yaml
name: accordserver
services:
  - name: accordserver
    dockerfile_path: Dockerfile
    http_port: 39099
    health_check:
      http_path: /api/v1/health
    envs:
      - key: DATABASE_URL
        value: "${db.DATABASE_URL}"
      - key: PORT
        value: "39099"
databases:
  - engine: PG
    name: db
    size: db-s-dev-database
```

### Deploy Button for README / Website

Standard deploy buttons link to platform-specific URLs that reference the GitHub repo:

```markdown
[![Deploy on Railway](https://railway.app/button.svg)](https://railway.app/template/accordserver)
[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/DaccordProject/accordserver)
[![Deploy to DO](https://www.deploytodo.com/do-btn-blue.svg)](https://cloud.digitalocean.com/apps/new?repo=https://github.com/DaccordProject/accordserver)
```

For Fly.io, a CLI command is standard: `fly launch --from https://github.com/DaccordProject/accordserver`

## Implementation Status

- [x] Docker image with multi-stage build and GHCR publishing
- [x] Environment variable configuration (all settings via env)
- [x] Zero-config SQLite startup (auto-create DB, migrations, default invite)
- [x] PostgreSQL support with auto-migration
- [x] Docker Compose stack with LiveKit + Caddy (SQLite)
- [x] Docker Compose stack with PostgreSQL + LiveKit + Caddy
- [x] Health endpoint (`/api/v1/health`) for platform health checks
- [ ] Railway deploy config (`railway.toml`)
- [ ] Render blueprint (`render.yaml`)
- [ ] Fly.io config (`fly.toml`)
- [ ] DigitalOcean App Platform spec (`app.yaml`)
- [ ] Deploy buttons in accordserver README
- [ ] Deploy buttons on accordwebsite
- [ ] Heroku `app.json` (Heroku uses ephemeral filesystems — requires Postgres)
- [ ] Coolify one-click template

## Gaps / TODO

| Gap | Severity | Notes |
|-----|----------|-------|
| No platform deploy configs exist | High | `railway.toml`, `render.yaml`, `fly.toml`, `app.yaml` need to be created in the accordserver repo |
| No deploy buttons in README | High | accordserver README has Docker instructions but no one-click deploy badges |
| No deploy page on accordwebsite | Medium | The website (`../accordwebsite/`) should have a "Host Your Own" page with deploy buttons and a quick-start guide |
| LiveKit requires separate hosting | Medium | One-click deploys only cover the core server; voice/video requires a separate LiveKit instance. Document LiveKit Cloud as the easy path for voice |
| Ephemeral filesystem platforms | Medium | Railway/Render/Fly volumes work, but Heroku and some platforms lack persistent disk — must use Postgres, and CDN storage needs an object store (S3/R2) |
| No `ACCORD_STORAGE_PATH` S3 backend | Low | CDN storage is local-disk-only; platforms without persistent volumes can't store uploads without an S3-compatible backend in accordserver |
| `app-network` external network in compose | Low | `docker-compose.yml` requires `docker network create app-network` before first run — should document or auto-create |
| No ARM64 Docker image | Low | The Dockerfile builds x86_64 only; ARM64 hosts (Apple Silicon, Graviton) need a multi-arch build in the CI pipeline |
