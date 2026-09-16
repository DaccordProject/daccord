---
title: Running Accord on Your Desktop
description: Install the Accord desktop app to run your own server from your computer — no Docker, no command line, no configuration.
order: 2
section: self-hosting
---

# Running Accord on Your Desktop

The **Accord desktop app** runs in your system tray (or menu bar) and bundles `accordserver` and a LiveKit voice server. It generates its own configuration on first run and updates itself. For an always-on, internet-facing server, see [Deploying a Server](deploying-a-server.md) and the [Self-Hosting Overview](overview.md).

## Install

Download the installer from the [accordserver releases page](https://github.com/DaccordProject/accordserver/releases/latest):

| Platform | File |
|----------|------|
| macOS | `.dmg` (drag Accord to Applications) |
| Windows | `.msi`, or `-setup.exe` (per-user, no admin rights needed) |
| Linux (Debian/Ubuntu) | `.deb` |
| Linux (other) | `.AppImage` (mark executable, then run) |

> **First-launch security warnings:** builds are not yet code-signed. On macOS, right-click the app and choose **Open**; on Windows SmartScreen, click **More info → Run anyway**. This only happens once.

## First Launch

There is no main window; an icon appears in the system tray or menu bar. On first launch Accord generates a random LiveKit key, a two-factor encryption key, and default ports.

| Tray menu item | What it does |
|-----------|--------------|
| **Open in browser** | Opens `http://localhost:39099` |
| **Open data folder** | Opens the folder with config, database, and logs |
| **View logs** | Opens `accord.log` |
| **Check for updates** | Checks now, or restarts to apply a downloaded update |
| **Start on login** | Launch Accord when you sign in |
| **Quit Accord** | Stops the server and voice server |

## Connecting the daccord Client

In daccord, click **+** and add:

- `http://localhost:39099` on the same computer, or
- `http://<your-local-ip>:39099` (e.g. `http://192.168.1.50:39099`) from another device on your network.

> **Include `http://`.** Without it the client tries HTTPS against the plain-HTTP server and fails with a "Broken pipe" error.

Then [create an account](../getting-started/creating-an-account.md).

## Inviting People from Outside Your Network

The server is reachable on your local network by default. For internet access, forward these ports on your router to the computer running Accord, then share your public IP and port `39099` (a dynamic-DNS hostname helps if your IP changes):

| Port | Protocol | Purpose |
|------|----------|---------|
| 39099 | TCP | Chat (HTTP + WebSocket) |
| 7880, 7881 | TCP | LiveKit voice signalling |
| 50000–60000 | UDP | LiveKit voice/video media |

## Where Your Data Lives

| Platform | Data folder |
|----------|-------------|
| macOS | `~/Library/Application Support/gg.daccord.Accord/` |
| Linux | `$XDG_DATA_HOME/accord/` (usually `~/.local/share/accord/`) |
| Windows | `%APPDATA%\Accord\Accord\` |

It contains `config.toml` (ports and keys), `livekit.yaml`, `accord.db` (accounts, spaces, messages), `cdn/` (uploads, emoji, avatars), and `logs/` (`accord.log`, `livekit.log`, `desktop.log`).

**Back up** by copying the folder while Accord is quit. **Reset** by deleting it. Keep it across reinstalls to preserve your community.

## Automatic Updates

Accord checks for updates shortly after launch and every six hours, downloads them in the background, and applies them the next time the app restarts; the running server keeps serving until then. The tray menu shows progress, and choosing **Check for updates** with an update ready restarts Accord to apply it.

> **Linux:** in-place updates work for the `.AppImage`. Update a `.deb` install through your package manager or by reinstalling.

## Moving to a Full Deployment

The desktop app only serves while your computer is awake and online. For guaranteed uptime, a domain with HTTPS, PostgreSQL, or a public directory listing, move to a [server deployment](deploying-a-server.md). Both run the same accordserver.

## Package-manager distribution

WinGet, Scoop, Chocolatey, Homebrew, and Flathub recipes are in preparation and
not yet listed; see [packaging status](../packaging.md). Package-manager installs
leave updates to the manager, while direct GitHub downloads keep the in-app
updater. Packagers build with `--dart-define=PACKAGE_MANAGER=true`, which doesn't
affect Developer Mode or local MCP tools.
