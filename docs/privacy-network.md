---
title: Network Behavior and Privacy
description: The services daccord can contact, what is sent, and when each request happens.
order: 3
section: troubleshooting
---

# Network Behavior and Privacy

daccord has no first-party analytics, telemetry, advertising, or automatic crash-reporting SDK, but normal features make the network requests below.

## Destinations

| Destination | When it is contacted | Data involved |
|---|---|---|
| Accord servers you add | Sign-in, messaging, administration, uploads, and live gateway events | Account credentials or token and the community data required by the action |
| A server-configured LiveKit service | When you join or receive a voice/video call | A short-lived room token plus WebRTC signalling and media; direct media paths can also reveal participant IP addresses as normal for WebRTC |
| The configured server directory (default `https://master.daccord.gg`) | When you browse public servers or use directory-backed federation features | The directory query and ordinary connection metadata such as IP address and user agent |
| GitHub (`api.github.com` and release downloads) | Desktop update checks and downloads; release notes for the installed version | App version, platform request metadata, and the download request. Store builds do not use the GitHub self-updater |
| The origin hosting the Web build | Loading the app and checking its service worker for an updated deployment | Ordinary web request metadata |
| A connected server's configured CDN | Rendering server-provided avatars, emoji, attachments, and message media | Requested media URL and ordinary connection metadata |
| External media hosts named in messages | Only after an explicit load/open action; compact third-party decorative media fails closed | The requested URL plus ordinary connection metadata, including your IP address |
| Links you open | Only after your action and confirmation where applicable | Whatever the external browser sends to that destination |

Operators of each destination (servers, LiveKit, directories, GitHub, web hosts, CDNs, external sites) can observe requests that reach them and may have their own logging and privacy policies.

## Relay-only voice

Voice & Video settings offers **Relay-only voice**, off by default. When enabled,
voice, video and screen sharing use only TURN relay candidates, including on
reconnect. Leave and rejoin an existing call to apply a changed preference.
The server's LiveKit deployment must provide a reachable TURN relay; without one,
the connection fails with an explanation and never falls back to direct media.
Relaying can increase latency. The Accord, LiveKit and TURN operators still see
connection metadata, including your IP address.

## Fonts and local files

The app uses platform-provided fonts. It does not fetch Google Fonts or another font service at runtime. Message content cannot silently load `file:`, `data:`, `blob:`, `content:`, asset, UNC, or custom-scheme image URLs.

## Stored sign-in credentials

On Android, iOS, macOS, Windows, and Linux, reusable session tokens are stored through the operating system's credential service. The profile database holds only random opaque references and non-secret account metadata. Linux builds require a Secret Service provider such as GNOME Keyring or KWallet; if no credential vault is available, Daccord does not fall back to plaintext storage.

Browsers have no OS credential vault, so on Web tokens are kept in origin-scoped local storage protected by a non-exportable WebCrypto key. This does not protect a token from script running in the same origin or from a compromised browser profile: web deployments must use HTTPS and strong security headers, and the browser profile is part of the trust boundary.

## What self-hosting controls

Self-hosting keeps accounts, messages, uploads, and voice on infrastructure you choose; daccord does not proxy them. You can replace the default directory URL in settings. Update checks and requests you initiate to external sites still happen as described above.

## YouTube previews

YouTube posters follow external-media consent. On Web, choosing **Play · load
from YouTube** loads the official `www.youtube.com/iframe_api` script and the
`www.youtube-nocookie.com` player, which may make further media requests.
Viewing history alone loads neither. **Open in YouTube** uses your external
browser. Embeds can be hidden in appearance settings.
