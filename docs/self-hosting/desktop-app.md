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

- **On the same computer:** use `http://localhost:39099` (or `http://127.0.0.1:39099`).
- **From another device, on your network or over the internet:** use an `https://` address. See "Reaching the server from other devices" below.

> **Plain HTTP works only on the same computer.** Accord serves plain HTTP on port `39099`. The daccord client accepts `http://` only for loopback addresses (`localhost`, `127.0.0.1`, `::1`), so your password and session token never travel over a network unencrypted. Include the `http://` prefix for a local server. Without it, the client assumes `https://`, and the connection fails with a "Broken pipe" error. A LAN or public address over `http://`, such as `http://192.168.1.50:39099`, is rejected with "Accord server URL must use HTTPS. HTTP is allowed only for loopback development."

## Reaching the server from other devices

To connect from a phone, a second computer, or a friend's machine, put an HTTPS reverse proxy in front of Accord and give it a certificate that those devices trust. Common options:

- **A domain name with automatic HTTPS (recommended).** Point a domain, or a dynamic-DNS hostname if your home IP changes, at your network. Forward TCP ports `80` and `443` to the computer running Accord. Then run [Caddy](https://caddyserver.com/) with a minimal `Caddyfile`:

  ```
  chat.example.com {
      reverse_proxy localhost:39099
  }
  ```

  Caddy obtains and renews a Let's Encrypt certificate automatically. Members then add `chat.example.com`.
- **A private mesh network.** Tools such as Tailscale can publish the server over HTTPS with a trusted certificate (for example `tailscale serve --bg 39099`). Only devices on your tailnet can reach it.
- **LAN only, with your own certificate authority.** Caddy's `tls internal` directive (or a tool such as `mkcert`) can issue a certificate for a local hostname. You must install and trust that root certificate on every device that connects, or the TLS handshake fails.

WebSocket traffic (`/ws`) goes through the same proxy. Caddy forwards it with no extra configuration.

> **Voice and video work only on the computer running Accord, for now.** The desktop app always tells clients to reach its voice server (LiveKit) at `http://127.0.0.1:7880`, and there is no setting to change that address. Members on any other device can chat through the setups above but cannot join voice channels. That includes the LAN, a public domain and Tailscale (`tailscale serve` publishes only the chat port). Configurable voice is tracked in [accordserver#84](https://github.com/DaccordProject/accordserver/issues/84). If your community needs voice from other devices today, use a [server deployment](deploying-a-server.md), which serves voice over its own `wss://` hostname.

Create an account on your new server and you're in. See [Creating an Account](../getting-started/creating-an-account.md) and [Adding a Server](../getting-started/adding-a-server.md) for the client-side steps.

## Inviting people from outside your network

To let friends connect over the internet, follow the domain-name option in "Reaching the server from other devices" above. Forward these ports on your router to the computer running Accord:

| Port | Protocol | Purpose |
|------|----------|---------|
| 80, 443 | TCP | HTTPS reverse proxy (chat HTTP + WebSocket to Accord on `39099`) |

Don't forward port `39099` directly. The client won't connect to a public IP over plain `http://`. Share your `https://` domain name with the people you invite instead.

Don't forward the voice ports either (`7880` LiveKit signaling, `7881` TCP media fallback, `50000–60000` UDP media). As explained above, remote members can't use voice on a desktop-app server yet, and forwarding `7880` would expose unencrypted signaling.

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

## Package-manager distribution

WinGet, Scoop, Chocolatey, Homebrew and Flathub recipes are being prepared. They
are not yet live catalogue listings. See [packaging status](../packaging.md) for
the release, platform validation and submission requirements.

When installed through a supported package-manager recipe, Daccord leaves updates
to that manager. Direct GitHub downloads keep the in-app updater. Packagers can
build with `--dart-define=PACKAGE_MANAGER=true`; this does not change access to
desktop Developer Mode or local MCP tools.
