---
title: Profiles
description: Use multiple profiles to keep different server sets and settings separate.
order: 3
section: customization
---

# Profiles

Device profiles keep separate sets of servers, settings, and preferences on one device (for example, work and personal).

## Managing Profiles

Open **Settings → Account → Device profiles**.

- **Create:** click **New profile**, enter a name, and optionally set a PIN.
- **Switch, rename, set or remove a PIN, delete:** use the menu next to a profile. Switching restarts the app with that profile.

Profile selection is available only through this in-app screen; there is no command-line profile selector.

Deleting a profile removes only that profile's data, including its saved server connections. The default profile cannot be deleted.

Each profile's storage is isolated on every platform (separate data directories on native apps, profile-specific browser storage on the web). The default profile keeps the original storage, so data from before profiles existed remains available.

## Optional PIN Lock

A PIN makes daccord show an unlock screen before opening the profile. It is only a casual screen lock, for example when briefly handing someone an unlocked device.

The PIN does **not** encrypt messages, sessions, settings, or other profile data, and doesn't protect them from other OS users, processes that can read the app data directory, malware, or backups. Use your device's account security and full-disk encryption for that.
