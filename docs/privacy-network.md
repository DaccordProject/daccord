---
title: Network Behavior and Privacy
description: The services daccord can contact, what is sent, and when each request happens.
order: 3
section: troubleshooting
---

# Network Behavior and Privacy

daccord has no first-party analytics, telemetry, advertising, or automatic crash-reporting SDK. That does not mean the client is offline except for chat. Normal features can make the network requests below.

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

Server operators control the Accord and LiveKit endpoints they configure and may have their own logging and privacy policies. Operators of public directories, GitHub, web hosts, CDNs, and external sites can likewise observe requests that reach them.

## Fonts and local files

The app uses platform-provided fonts. It does not fetch Google Fonts or another font service at runtime. Message content cannot silently load `file:`, `data:`, `blob:`, `content:`, asset, UNC, or custom-scheme image URLs.

## Stored sign-in credentials

On Android, iOS, macOS, Windows, and Linux, reusable session tokens are stored through the operating system's credential service. The ordinary Hive profile database contains only random opaque references and non-secret account metadata. Older plaintext session records are migrated by committing the token to the credential service before the Hive copy is removed. Linux builds require a Secret Service provider such as GNOME Keyring or KWallet; if no credential vault is available, Daccord does not fall back to plaintext storage.

Web browsers do not expose an OS credential vault to Flutter applications. On Web, the secure-storage plugin uses a non-exportable WebCrypto key to protect values kept in origin-scoped local storage. This reduces offline portability but does not protect a token from script executing in the same origin or from a compromised browser profile. Web deployments must use HTTPS and strong security headers, and users should treat the browser profile as part of the trust boundary.

## What self-hosting controls

Self-hosting keeps community accounts, messages, uploads, and the configured voice service under infrastructure you choose. daccord does not proxy those services. You can also replace the default public directory URL in settings. Ancillary update checks and explicitly initiated external requests remain separate from your server traffic as described above.
