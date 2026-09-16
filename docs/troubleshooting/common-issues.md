---
title: Troubleshooting
description: Solutions to common problems with daccord.
order: 1
section: troubleshooting
---

# Troubleshooting

## Can't Connect to a Server

- **Check the URL**, e.g. `chat.example.com` or `chat.example.com:8443`.
- **"Broken pipe" on a local server** -- without a scheme the client assumes `https://`, but self-hosted Accord servers speak plain HTTP. Add `http://`, e.g. `http://localhost:39099` or `http://192.168.1.50:39099`.
- **Server unreachable** -- the server may be down or firewalled; contact its admin.
- **Wrong credentials** -- passwords are case-sensitive.

## Connection Lost

daccord reconnects automatically. While a server is unreachable, its icon in the space bar changes and the channel and member lists show a **Retry** button. If the problem persists after checking your internet connection, close and reopen daccord to establish a fresh session.

## Messages Not Loading

Switch to another channel and back. If every channel is affected after reconnecting, close and reopen daccord.

## Local MCP Tools Not Connecting

- Enable **Developer Mode** in **Settings → Advanced**, then enable the **Client MCP server**. The default endpoint is `http://127.0.0.1:39101/mcp`.
- Configure your MCP client with the bearer token from that page. It is separate from any remote Accord server API key.
- Keep daccord running and enable the tool groups you need; Read and Navigate are on by default.
- A failure at `notifications/initialized` can mean an older build returning an invalid response: HTTP notifications must get status 202 with an empty body. Regression coverage: `flutter test test/features/developer/mcp_server_io_test.dart`.

## No Sound in Voice Channels

- Check your devices in **Settings → Voice & Video**.
- Make sure you aren't muted or deafened in the voice bar.
- If voice fails for everyone, the server's voice backend (LiveKit) may be down; contact the server admin.

## Video Playback on Linux

Inline videos use software decoding on Linux to avoid an NVIDIA driver crash in hardware decoding, so large videos can use more CPU.

## App Won't Start

- On Linux, check the portable executable has execute permission.
- On macOS, right-click and choose **Open** to get past Gatekeeper on first launch.
- If you can reach settings, create or switch to another profile under **Settings → Account → Device profiles** to rule out profile-specific data. There is no command-line profile selector.

## Unexpected Sign-out

- **A saved credential is missing from the OS vault** -- sign in again; the session is repaired in place.
- **Same account on two device profiles** -- each profile has its own credential, so signing out of one doesn't affect the other.
- **Credentials disappear on Linux with two app windows open** -- vault writes are serialized within one app process only; avoid running two instances at once.

## Reporting Issues

Report bugs on [GitHub Issues](https://github.com/DaccordProject/daccord/issues). daccord collects no first-party analytics, telemetry, or crash data; see [Network behavior and privacy](../privacy-network.md) for what it does contact.
