---
title: Installing daccord
description: Download and install daccord on Linux, Windows, macOS, or Android.
order: 1
section: getting-started
---

# Installing daccord

daccord is available for Linux, Windows, macOS, Android, and the web.

## Download

Download the latest release from the [GitHub Releases page](https://github.com/DaccordProject/daccord/releases).

Choose the right file for your platform:

| Platform | File |
|----------|------|
| Linux (x86_64, recommended) | `daccord-linux-x86_64.deb` |
| Linux (x86_64, portable) | `daccord-linux-x86_64.tgz` |
| Windows (installer) | `daccord-windows-x86_64-setup.exe` |
| Windows (portable) | `daccord-windows-x86_64.zip` |
| macOS | `daccord-macos-universal.dmg` |
| Android | `daccord-android.apk` |
| Web | `daccord-web.zip` |

## Linux

**Package (recommended):** download `daccord-linux-x86_64.deb` and install it with `sudo dpkg -i daccord-linux-x86_64.deb` (or open it in your software centre). This is the build that keeps working with the in-app updater.

**Portable:**

1. Extract `daccord-linux-x86_64.tgz`.
2. Run the `daccord` executable.
3. On some distributions you may need to mark it as executable first: right-click the file, open Properties, and enable "Allow executing file as program".

> **Already on v0.2.6 or earlier?** Those builds could not replace a system
> (`.deb`) install and failed silently, so the app never updated itself. Install
> the `.deb` above by hand once; from v0.2.7 onward the in-app updater handles it
> for you.

## Windows

**Installer:** Download and run `daccord-windows-x86_64-setup.exe`. It installs daccord to Program Files, adds a Start Menu shortcut, and registers the `daccord://` URL scheme so invite links open automatically. A per-user install (no admin rights required) is also supported.

**Portable:** Download and extract `daccord-windows-x86_64.zip`, then double-click `daccord.exe` to launch without installing.

## macOS

1. Open the downloaded `.dmg` file.
2. Drag daccord to your Applications folder.
3. Launch from Applications. On first launch, you may need to right-click and choose "Open" to bypass Gatekeeper.

## Android

1. Download the `.apk` file to your device.
2. Open it and follow the installation prompts. You may need to allow installation from unknown sources in your device settings.
3. Launch daccord from your app drawer.

## Web

The web build runs entirely in your browser with no installation required. Extract `daccord-web.zip` and open it from a web server, or visit a hosted instance if your server operator provides one. Voice and video are supported via the web audio stack. Note that some features (such as automatic updates and file system access) are not available in the web build.

## Updates

daccord checks for updates automatically on startup. When a new version is available, a banner appears at the top of the window. Click it to download and install the update. You can also check manually from the user menu.
