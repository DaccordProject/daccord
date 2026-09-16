---
title: Installing daccord
description: Download and install daccord on Linux, Windows, macOS, Android, or iOS.
order: 1
section: getting-started
---

# Installing daccord

## Download

Get iOS from the [App Store](https://apps.apple.com/app/id6779929284) and Android from [Google Play](https://play.google.com/store/apps/details?id=com.daccord_projects.daccord). Desktop builds and the Android APK are on the [GitHub Releases page](https://github.com/DaccordProject/daccord/releases):

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

**Package (recommended):** `sudo dpkg -i daccord-linux-x86_64.deb`, or open it in your software centre. This build works with the in-app updater and registers `daccord://` links.

**Portable:** extract `daccord-linux-x86_64.tgz` and run `daccord` (you may need to mark it executable first). It doesn't register `daccord://` links.

## Windows

**Installer:** run `daccord-windows-x86_64-setup.exe`. It adds a Start Menu shortcut and registers `daccord://` links; per-user install without admin rights is supported.

**Portable:** extract `daccord-windows-x86_64.zip` and run `daccord.exe`. It doesn't register `daccord://` links.

## macOS

Open the `.dmg` and drag daccord to Applications. If Gatekeeper blocks the first launch, right-click the app and choose **Open**.

## iOS

Install from the [App Store](https://apps.apple.com/app/id6779929284). Requires iOS 15.6 or later.

## Android

Install from [Google Play](https://play.google.com/store/apps/details?id=com.daccord_projects.daccord), or open the downloaded `.apk` (you may need to allow installs from unknown sources).

## Web (JavaScript)

Serve the extracted `daccord-web.zip` from a web server, or use a hosted instance if your server operator provides one. Voice and video work, but screen sharing, audio output selection, and the self-updater are not available on the web.

## Updates

App Store and Google Play installs update through the store.

Other desktop and Android builds check GitHub for updates on startup (turn this off in **Settings → Updates**, where you can also check manually). A banner at the top of the window shows when an update is available or ready to install. The web build shows a **Reload** banner when a new deployment is available.
