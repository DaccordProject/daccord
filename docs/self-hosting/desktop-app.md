---
title: Running Accord on Your Desktop
description: Install the Accord desktop app to run your own server from your computer — no Docker, no command line, no configuration.
order: 2
section: self-hosting
---

# Running Accord on Your Desktop

The **Accord desktop app** is the simplest way to host your own server. It is a small application that runs quietly in your system tray (or menu bar) and takes care of everything the server needs: it bundles `accordserver` and a LiveKit voice server, generates its own configuration the first time it runs, and updates itself in the background.

There is no command line, no Docker, and nothing to configure. Install it, launch it, and your server is running.

## Is the desktop app right for me?

Use the desktop app when you want to run a server for yourself, friends, or a small community on a computer you already own. It is perfect for trying daccord out or for a home or LAN community. If you need a server that is online around the clock and reachable from anywhere, see [Deploying a Server](deploying-a-server.md) instead — and read the [Self-Hosting Overview](overview.md) for a side-by-side comparison.

## Install

Download the installer for your platform from the [accordserver releases page](https://github.com/DaccordProject/accordserver/releases/latest).

| Platform | File |
|----------|------|
| macOS | `.dmg` |
| Windows | `.msi` or `-setup.exe` (NSIS) |
| Linux (Debian/Ubuntu) | `.deb` |
| Linux (other) | `.AppImage` |

Then install it the same way you would any other app:

- **macOS** — open the `.dmg` and drag Accord to Applications.
- **Windows** — run the installer. The NSIS (`-setup.exe`) build installs per-user and needs no administrator rights.
- **Linux** — install the `.deb` with your package manager, or mark the `.AppImage` as executable and run it.

> **First-launch security warnings:** current builds are not yet code-signed, so macOS Gatekeeper and Windows SmartScreen will warn you the first time. On macOS, right-click the app and choose **Open**. On Windows, click **More info → Run anyway**. This only happens once.

## First launch

Accord has no main window — when it starts, an icon appears in your system tray (Windows/Linux) or menu bar (macOS). On the very first launch it generates everything it needs in a data folder, including a random LiveKit voice key, a two-factor encryption key, and its default ports.

Click the tray icon to open the menu:

| Menu item | What it does |
|-----------|--------------|
| **Open in browser** | Opens `http://localhost:39099` — your running server |
| **Open data folder** | Opens the folder holding your config, database, and logs |
| **View logs** | Opens `accord.log` |
| **Check for updates** | Shows update status; click to check now, or to restart and apply a staged update |
| **Start on login** | Toggles whether Accord launches automatically when you sign in |
| **Quit Accord** | Gracefully stops the server and voice server |

## Connecting the daccord client

With Accord running, open the daccord client, click the **+** button in the sidebar, and add a server.

- **On the same computer:** use `localhost:39099`.
- **From another device on your network:** use your computer's local IP address and port, for example `192.168.1.50:39099`.

Create an account on your new server and you're in. See [Creating an Account](../getting-started/creating-an-account.md) and [Adding a Server](../getting-started/adding-a-server.md) for the client-side steps.

## Inviting people from outside your network

By default the server is reachable on your local network only. To let friends connect over the internet, forward these ports on your router to the computer running Accord:

| Port | Protocol | Purpose |
|------|----------|---------|
| 39099 | TCP | Chat (HTTP + WebSocket) |
| 7880, 7881 | TCP | LiveKit voice signaling |
| 50000–60000 | UDP | LiveKit voice/video media |

Then share your public IP address (and port `39099`) with the people you want to invite. If your home IP address changes over time, a dynamic-DNS hostname makes this easier.

> If port-forwarding isn't an option, or you want a server that's always reachable, a full [server deployment](deploying-a-server.md) on a VPS is the better fit.

## Where your data lives

On first launch, Accord creates a data folder for your server:

| Platform | Data folder |
|----------|-------------|
| macOS | `~/Library/Application Support/gg.daccord.Accord/` |
| Linux | `$XDG_DATA_HOME/accord/` (usually `~/.local/share/accord/`) |
| Windows | `%APPDATA%\Accord\Accord\` |

Inside you'll find:

- `config.toml` — generated ports and voice/security keys.
- `livekit.yaml` — configuration for the bundled voice server.
- `accord.db` — the SQLite database with your accounts, spaces, and messages.
- `cdn/` — uploaded emoji, avatars, and file attachments.
- `logs/` — `accord.log`, `livekit.log`, and the app's own `desktop.log`.

**Backing up:** copy this folder while Accord is quit to back up your entire server. **Resetting:** delete the folder to start completely fresh. Keep it across reinstalls to preserve your community.

## Automatic updates

Accord keeps itself current. It checks for a new release shortly after launch and every few hours while it runs. When a newer signed version is available, it downloads in the background without interrupting your server. The update is applied the next time you restart the app — your running server keeps serving the old version until then.

The tray menu reflects the progress (`Checking…`, `Downloading…`, `Update ready — restart to apply`), and a banner appears on the server's landing page while an update is downloading or ready. When an update is staged, choosing **Check for updates** restarts Accord to apply it.

> **Linux note:** in-place automatic updates work for the `.AppImage` build. If you installed the `.deb`, update it through your package manager or by reinstalling. macOS and Windows builds update in place.

## When to move to a full deployment

The desktop app is ideal for getting started and for smaller communities, but it only serves while your computer is awake and online. When you outgrow it — you want guaranteed uptime, a real domain with HTTPS, PostgreSQL, or a listing in the public server browser — move to a [server deployment](deploying-a-server.md). Both run the same accordserver, so members reconnect to the new address and carry on.
