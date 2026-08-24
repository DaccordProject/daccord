---
title: Profiles
description: Use multiple profiles to keep different server sets and settings separate.
order: 3
section: customization
---

# Profiles

Profiles let you maintain separate configurations -- each with its own servers, settings, and preferences. This is useful if you use daccord for different purposes (e.g., work and personal).

## Switching Profiles

1. Open **App Settings**.
2. Go to **Profiles**.
3. Select a profile from the list to switch to it.

Profile selection is currently available only through this in-app screen; there
is no command-line profile selector.

## Creating a Profile

1. In the Profiles settings page, click **Create Profile**.
2. Enter a name for the new profile.
3. Optionally set a PIN as a casual in-app screen lock.

Each profile has its own server connections, theme, and preferences. Switching profiles reloads the app with that profile's configuration.

Profile storage is isolated on every supported platform. Native apps store each non-default profile under its own data directory. The Web app stores each non-default profile in profile-specific Hive/IndexedDB box names, because browsers do not expose per-profile filesystem directories. The default profile keeps the original storage names on all platforms so data from installations created before profiles were added remains available.

## Optional PIN Lock

You can add a PIN to make Daccord show an unlock screen before opening a profile. This is only a casual UI lock for situations such as handing an already-unlocked device to someone briefly.

The PIN does **not** encrypt messages, sessions, settings, or other profile data. It does not protect that data from another operating-system user, a process that can read the app data directory, malware, or backups. Use your device's account security and full-disk encryption when you need data-at-rest protection.

## Deleting a Profile

Select a non-default profile and click **Delete** to remove it. This deletes only that profile's configuration, including saved server connections; other profiles and shared app data are left intact. The default profile cannot be deleted.
