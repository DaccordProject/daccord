---
title: Deploying a Server
description: Set up and run your own always-on accordserver instance with Docker or from source.
order: 3
section: self-hosting
---

# Deploying a Server

This guide runs an always-on [accordserver](https://github.com/DaccordProject/accordserver) on a Linux machine or VPS. To host from your own computer instead, use the [Accord desktop app](desktop-app.md); see the [Self-Hosting Overview](overview.md) to compare.

## Requirements

- A Linux machine or VPS (1 GB RAM minimum)
- [Docker](https://docs.docker.com/get-docker/) with Docker Compose, or Rust 1.88+ to build from source
- Domain names pointed at the server for chat and for LiveKit (e.g. `chat.example.com` and `livekit.example.com`)

## Quick Start with Docker Compose

The compose file runs accordserver, a LiveKit voice server, and a Caddy reverse proxy with automatic HTTPS.

1. Clone the repository:

   ```bash
   git clone https://github.com/DaccordProject/accordserver.git
   cd accordserver
   ```

2. Edit `docker-compose.yml`. Settings are written directly in the file:
   - Replace `chat.example.com` and `livekit.example.com` (the `caddy` labels, `LIVEKIT_EXTERNAL_URL`, and `MASTER_SERVER_PUBLIC_URL`).
   - Replace the LiveKit `devkey`/`secret` pair in both the `livekit` command and the server's `LIVEKIT_API_KEY`/`LIVEKIT_API_SECRET`.
   - Remove `MASTER_SERVER_PUBLIC_URL` if you don't want to be listed in the public server directory.

3. Create the shared network (the compose file expects it to exist), then start the stack:

   ```bash
   docker network create app-network
   docker compose up -d
   ```

accordserver listens on port **39099** inside the stack; Caddy serves it over HTTPS on your domain once DNS resolves.

## Using PostgreSQL

For production, use `docker-compose.postgres.yml` instead of the SQLite default. Change `POSTGRES_PASSWORD` and the matching password in `DATABASE_URL` first; URL-encode special characters in `DATABASE_URL` (`!` → `%21`, `@` → `%40`, `#` → `%23`).

```bash
docker compose -f docker-compose.postgres.yml up -d
```

The server creates the database schema and runs migrations on startup.

## Configuration Reference

### Core

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `39099` | HTTP listen port |
| `DATABASE_URL` | `sqlite:data/accord.db?mode=rwc` | Database connection string |
| `ACCORD_STORAGE_PATH` | `./data/cdn` | Uploaded files and plugin bundles |
| `RUST_LOG` | `accordserver=debug,tower_http=debug` | Log level filter |

### Voice and Video (LiveKit)

All four are required; without them voice channels don't work.

| Variable | Description |
|----------|-------------|
| `LIVEKIT_INTERNAL_URL` | LiveKit URL the server uses (e.g. `http://livekit:7880`) |
| `LIVEKIT_EXTERNAL_URL` | Public LiveKit URL clients use (e.g. `wss://livekit.example.com`) |
| `LIVEKIT_API_KEY` | LiveKit API key |
| `LIVEKIT_API_SECRET` | LiveKit API secret |

### Security

| Variable | Description |
|----------|-------------|
| `TOTP_ENCRYPTION_KEY` | Encrypts two-factor secrets; without it they are stored in plaintext |
| `MCP_API_KEY` | API key for the MCP management endpoint |

### Server Directory (Optional)

Setting `MASTER_SERVER_PUBLIC_URL` registers the server in the public server list.

| Variable | Default | Description |
|----------|---------|-------------|
| `MASTER_SERVER_PUBLIC_URL` | *(none)* | Your server's public URL (enables registration) |
| `MASTER_SERVER_URL` | `https://master.daccord.gg` | Directory endpoint |
| `MASTER_SERVER_NAME` | `Accord Server` | Name shown in the list |
| `MASTER_HEARTBEAT_INTERVAL` | `60` | Heartbeat interval in seconds |

## Building from Source

```bash
git clone https://github.com/DaccordProject/accordserver.git
cd accordserver
cargo build --release
./target/release/accordserver
```

It creates its SQLite database and data directory on first run. You'll need to run LiveKit and an HTTPS reverse proxy yourself.

## Ports

| Port | Service |
|------|---------|
| 443, 80 | Caddy (HTTPS for chat and LiveKit signalling) |
| 7881/TCP | LiveKit (TCP media) |
| 7882/UDP | LiveKit (UDP media) |
| 39099 | accordserver, only if exposed directly without Caddy |

## Connecting from daccord

Add the server with its domain (e.g. `chat.example.com`). When connecting directly over a local network, include the scheme (`http://your-ip:39099`); see [Adding a Server](../getting-started/adding-a-server.md).

## Updating

```bash
docker compose pull
docker compose up -d
```

Migrations run automatically on startup.
