---
title: Self-Hosting Overview
description: The two ways to run your own Accord server — the desktop app or a full server deployment — and how to choose between them.
order: 1
section: self-hosting
---

# Self-Hosting Overview

daccord connects to servers running [accordserver](https://github.com/DaccordProject/accordserver). When you self-host, you run that server yourself, which means you keep full control of your community's data, accounts, uploads, and voice traffic. Nothing passes through a third party.

There are two supported ways to host, depending on how much you want to manage.

## Choose your path

### Accord desktop app — the easy way

The [Accord desktop app](desktop-app.md) is a small tray application you install like any other program (`.dmg`, `.deb`/`.AppImage`, or `.msi`). It bundles the server and the voice server together, generates all its own configuration on first launch, and keeps itself up to date. There is nothing to configure and no command line involved.

This is the best choice if you want to:

- Try self-hosting without touching Docker or a terminal.
- Run a server for friends or family on a machine you already own.
- Host a small community on a home computer or a spare desktop.

The trade-off is that the server is only online while your computer is on, and letting people outside your home network connect requires a little router configuration.

### Server deployment — the always-on way

[Deploying a server](deploying-a-server.md) with Docker (or from source) on a Linux machine or VPS is the right choice for a community that needs to be reachable around the clock. You get automatic HTTPS, a choice of SQLite or PostgreSQL, and the ability to register your server in the public server list.

This is the best choice if you want to:

- Run a public or always-available community.
- Use a real domain name with HTTPS.
- Scale to many members on dedicated hardware or a cloud host.

The trade-off is that you manage the host, DNS, and updates yourself.

## At a glance

| | Desktop app | Server deployment |
|---|---|---|
| Install effort | Run an installer | Docker / command line |
| Configuration | Automatic | Environment variables |
| Best for | Friends, small or home communities | Public or always-on communities |
| Availability | While your computer is on | 24/7 |
| HTTPS / domain | Optional (LAN by default) | Built in via Caddy |
| Database | SQLite | SQLite or PostgreSQL |
| Updates | Automatic, in the background | `docker compose pull` |
| Voice & video | Bundled automatically | Bundled LiveKit |

Both paths run the same accordserver, so you can start with the desktop app and move to a full deployment later without changing how the daccord client connects.

## Connecting once you're hosting

However you host, members connect the same way: open daccord, click the **+** button in the sidebar, and enter your server's address. See [Adding a Server](../getting-started/adding-a-server.md) for the client side.
