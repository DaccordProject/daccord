---
title: Troubleshooting
description: Solutions to common problems with daccord.
order: 1
section: troubleshooting
---

# Troubleshooting

## Can't Connect to a Server

- **Check the URL** -- Make sure you entered the server address correctly. It should look like `chat.example.com` or `chat.example.com:8443`.
- **"Broken pipe" error on a local server** -- When you enter an address with no scheme, the client assumes `https://`. A self-hosted Accord server speaks plain HTTP, so the TLS handshake fails and the connection drops. Add the `http://` prefix explicitly, e.g. `http://localhost:39099` or `http://192.168.1.50:39099`.
- **Server unreachable** -- The server may be down or behind a firewall. Contact the server admin.
- **Wrong credentials** -- Double-check your username and password. Passwords are case-sensitive.

## Connection Lost

daccord automatically attempts to reconnect when the connection drops. If you see a disconnection banner:

- Wait a moment for automatic reconnection.
- Check your internet connection.
- If the problem persists, close and reopen daccord to establish a fresh session.

## Local MCP Tools Not Connecting

- Enable **Developer mode** in App Settings, then open **Developer** and enable the **Client MCP server**. The default endpoint is `http://127.0.0.1:39101/mcp`.
- Configure your MCP client with the bearer token from that page. It is separate from any remote Accord server API key.
- Keep Daccord running and enable the tool groups you need; Read and Navigate are enabled by default.
- A failure at `notifications/initialized` can indicate an older build returning an invalid response. HTTP notifications must receive status 202 with an empty body. Regression coverage: `flutter test test/features/developer/mcp_server_io_test.dart`.

## No Sound in Voice Channels

- Check that your microphone and speakers are selected in **App Settings > Voice & Video**.
- Make sure you aren't muted or deafened (check the voice bar icons).
- Ensure the server's voice backend (LiveKit) is running -- contact the server admin if voice isn't working for anyone.

## Video Playback on Linux

Inline videos use software decoding on Linux to avoid an NVIDIA driver crash
in hardware decoding. Rendering still uses the GPU, but playing large videos
can use more CPU.

## Messages Not Loading

- Check your connection status. A banner at the top of the message area indicates connection issues.
- Try switching to another channel and back.
- If every channel is affected after automatic reconnection, close and reopen daccord.

## App Won't Start

- Make sure you're running a supported version for your operating system.
- On Linux, verify the executable has the right permissions.
- On macOS, right-click and choose "Open" to bypass Gatekeeper on first launch.
- If the app renders far enough to open settings, create or select another profile under **App Settings > Profiles** to isolate profile-specific data. daccord does not currently provide a command-line profile selector.

## Reporting Issues

If you encounter a bug, report it at the [daccord GitHub Issues page](https://github.com/DaccordProject/daccord/issues).

daccord collects no first-party analytics, telemetry, or crash data. It does make documented requests for connected servers, discovery, updates, and user-approved media. See [Network behavior and privacy](../privacy-network.md) for the complete disclosure.
