---
title: Deploying Your Own Server
description: Set up and run your own accordserver instance with Docker or from source.
order: 1
section: self-hosting
---

# Deploying Your Own Server

daccord connects to servers running [accordserver](https://github.com/DaccordProject/accordserver). You can host your own server to keep full control of your community's data.

## Requirements

- A Linux machine or VPS (1 GB RAM minimum)
- [Docker](https://docs.docker.com/get-docker/) and Docker Compose (recommended), or Rust 1.88+ to build from source
- A domain name with DNS pointed at your server (for HTTPS)

## Quick Start with Docker Compose

This is the simplest way to get a server running. It includes accordserver, a LiveKit voice server, and a Caddy reverse proxy for automatic HTTPS.

1. Clone the repository:

   ```bash
   git clone https://github.com/DaccordProject/accordserver.git
   cd accordserver
   ```

2. Create a `.env` file with your configuration:

   ```bash
   # Required -- replace with your actual domains
   LIVEKIT_EXTERNAL_URL=wss://livekit.example.com
   LIVEKIT_INTERNAL_URL=http://livekit:7880
   LIVEKIT_API_KEY=your-api-key
   LIVEKIT_API_SECRET=your-api-secret
   ```

3. Start the stack:

   ```bash
   docker compose up -d
   ```

The server listens on port **39099** by default. Caddy handles HTTPS termination automatically if your DNS is configured.

## Using PostgreSQL (Recommended for Production)

For production deployments, use the PostgreSQL compose file instead of the default SQLite backend:

```bash
docker compose -f docker-compose.postgres.yml up -d
```

This adds a PostgreSQL 17 database with persistent storage. Set the database connection in your `.env`:

```bash
DATABASE_URL=postgres://accord:your-password@postgres/accord
```

The server automatically creates the database and runs migrations on first startup.

**Note:** Special characters in the PostgreSQL password must be URL-encoded (e.g., `!` becomes `%21`, `@` becomes `%40`).

## Configuration Reference

All configuration is done through environment variables.

### Core

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `39099` | HTTP listen port |
| `DATABASE_URL` | `sqlite:data/accord.db?mode=rwc` | Database connection string |
| `ACCORD_STORAGE_PATH` | `./data/cdn` | Path for uploaded files and plugin bundles |
| `RUST_LOG` | `accordserver=debug,tower_http=debug` | Log level filter |

### Voice and Video (LiveKit)

| Variable | Description |
|----------|-------------|
| `LIVEKIT_INTERNAL_URL` | Internal LiveKit URL (e.g., `http://livekit:7880`) |
| `LIVEKIT_EXTERNAL_URL` | Public LiveKit URL that clients connect to (e.g., `wss://livekit.example.com`) |
| `LIVEKIT_API_KEY` | LiveKit API key |
| `LIVEKIT_API_SECRET` | LiveKit API secret |

Voice and video features require all four LiveKit variables to be set. Without them, voice channels will not work.

### Security

| Variable | Description |
|----------|-------------|
| `TOTP_ENCRYPTION_KEY` | Encryption key for two-factor authentication secrets |
| `MCP_API_KEY` | API key for the MCP management endpoint |

### Master Server (Optional)

Register your server with the daccord master server so users can discover it in the public server list.

| Variable | Default | Description |
|----------|---------|-------------|
| `MASTER_SERVER_PUBLIC_URL` | *(none)* | Your server's public URL (required to enable) |
| `MASTER_SERVER_URL` | `https://master.daccord.gg` | Master server endpoint |
| `MASTER_SERVER_NAME` | `Accord Server` | Display name in the server list |
| `MASTER_HEARTBEAT_INTERVAL` | `60` | Heartbeat interval in seconds |

## Building from Source

If you prefer not to use Docker:

```bash
git clone https://github.com/DaccordProject/accordserver.git
cd accordserver
cargo build --release
./target/release/accordserver
```

The server creates its SQLite database and data directory automatically on first run.

## Ports

Make sure the following ports are accessible:

| Port | Service |
|------|---------|
| 39099 | accordserver (HTTP + WebSocket) |
| 7880 | LiveKit (HTTP) |
| 7881 | LiveKit (TCP) |
| 7882/UDP | LiveKit (UDP, media) |
| 443, 80 | Caddy reverse proxy (HTTPS) |

## Connecting from daccord

Once your server is running, open daccord and click the **+** button in the sidebar to add a new server. Enter your server's address (e.g., `chat.example.com` or `your-ip:39099`) and create an account.

## Updating

Pull the latest image and restart:

```bash
docker compose pull
docker compose up -d
```

Migrations run automatically on startup, so the database schema is always kept up to date.
