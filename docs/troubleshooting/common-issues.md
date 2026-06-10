---
title: Troubleshooting
description: Solutions to common problems with daccord.
order: 1
section: troubleshooting
---

# Troubleshooting

## Can't Connect to a Server

- **Check the URL** -- Make sure you entered the server address correctly. It should look like `chat.example.com` or `chat.example.com:8443`.
- **Server unreachable** -- The server may be down or behind a firewall. Contact the server admin.
- **Wrong credentials** -- Double-check your username and password. Passwords are case-sensitive.

## Connection Lost

daccord automatically attempts to reconnect when the connection drops. If you see a disconnection banner:

- Wait a moment for automatic reconnection.
- Check your internet connection.
- If the problem persists, right-click the space icon and select **Reconnect**.

## No Sound in Voice Channels

- Check that your microphone and speakers are selected in **App Settings > Voice & Video**.
- Make sure you aren't muted or deafened (check the voice bar icons).
- Ensure the server's voice backend (LiveKit) is running -- contact the server admin if voice isn't working for anyone.

## Messages Not Loading

- Check your connection status. A banner at the top of the message area indicates connection issues.
- Try switching to another channel and back.
- Right-click the space icon and select **Reconnect**.

## App Won't Start

- Make sure you're running a supported version for your operating system.
- On Linux, verify the executable has the right permissions.
- On macOS, right-click and choose "Open" to bypass Gatekeeper on first launch.
- Try launching with `--profile default` to rule out a corrupted profile.

## Reporting Issues

If you encounter a bug, report it at the [daccord GitHub Issues page](https://github.com/DaccordProject/daccord/issues).

daccord includes optional error reporting that sends crash data (with no personal information) to help developers fix issues. You can enable or disable this in App Settings.
