---
title: Self-Hosting Overview
description: The two ways to run your own Accord server — the desktop app or a full server deployment — and how to choose between them.
order: 1
section: self-hosting
---

# Self-Hosting Overview

daccord connects to servers running [accordserver](https://github.com/DaccordProject/accordserver). Self-hosting keeps your community's accounts, messages, uploads, and voice traffic on infrastructure you control; daccord does not proxy them (see the [network and privacy disclosure](../privacy-network.md) for the client's other requests).

## Choose your path

### Accord desktop app — the easy way

The [Accord desktop app](desktop-app.md) is a tray app for Windows, macOS, and Linux. It bundles the server and voice server, configures itself on first launch, and updates itself. Best for friends, family, or a small community on a computer you already own.

The trade-offs: the server is only online while your computer is, and people outside your network need router port forwarding.

### Server deployment — the always-on way

[Deploying a server](deploying-a-server.md) with Docker (or from source) on a Linux machine or VPS suits a public or 24/7 community, with your own domain, automatic HTTPS, SQLite or PostgreSQL, and optional listing in the public server directory.

The trade-off: you manage the host, DNS, and updates.

## At a glance

| | Desktop app | Server deployment |
|---|---|---|
| Install | Run an installer | Docker / command line |
| Configuration | Automatic | Compose file / environment variables |
| Availability | While your computer is on | 24/7 |
| HTTPS / domain | Optional (LAN by default) | Built in via Caddy |
| Database | SQLite | SQLite or PostgreSQL |
| Updates | Automatic | `docker compose pull` |
| Voice & video | Bundled LiveKit | Bundled LiveKit |

Both run the same accordserver, so you can start with the desktop app and move later. Either way, members connect by clicking **+** in daccord and entering the server's address; see [Adding a Server](../getting-started/adding-a-server.md).
