# Daccord Flutter Client — Product Specification

> Status: Draft · Owner: Daccord Project · Last updated: 2026-06-04

## 1. Summary

A native, cross-platform **Daccord chat client built in Flutter**, created by forking [Bonfire](https://github.com/OpenBonfire/bonfire) (a fast Flutter Discord client) and repointing it at the Accord protocol. It delivers the Daccord community-chat experience — spaces, channels, real-time messaging, members, roles, and moderation — on Android, iOS, web, and desktop, reusing Bonfire's polished UI.

It is **not** a Discord client and contains **no Discord integration**. It connects only to Accord servers ([`accordserver`](https://github.com/DaccordProject/accordserver)) via the [`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart) SDK.

## 2. Background & motivation

Daccord today ships a [Godot/GDScript client](https://github.com/DaccordProject/daccord). Godot is excellent for the game-like and plugin/activity features, but a chat app also benefits from a lightweight, idiomatic, store-friendly mobile/desktop client with native text input, accessibility, and platform integration. Bonfire already provides a fast, mature, multi-platform Flutter chat UI under a compatible (GPLv3) license. Forking it lets us reach a high-quality Daccord client far faster than building from scratch.

## 3. Goals

- Ship a multi-platform Daccord client (Android, iOS, web, Windows, macOS, Linux) that feels native on each.
- Reach **feature parity with the core messaging experience** of the Godot `daccord` client.
- Reuse Bonfire's UI, theming, navigation, and caching wherever possible.
- Support connecting to **arbitrary/self-hosted Accord servers** (configurable base/gateway/CDN URLs), not a single hardcoded host.
- Keep the codebase GPLv3 and open-source.

## 4. Non-goals (for this phase)

- **No Discord support** of any kind.
- **No voice/video/screenshare** yet — deferred until after the text client is solid (depends on transport work / GDExtension-equivalents).
- **No plugin/multiplayer-activity runtime** (the Lua/GDExtension activity platform from the Godot client) yet.
- No bespoke desktop-only features beyond what Bonfire already provides.
- No master-server account sync / licensing integration in this phase.

## 5. Target users

- **Community members** who want a fast, native Daccord app on their phone or desktop.
- **Self-hosters / server admins** who run their own Accord server and need a client that can point anywhere.
- **Power users** who prefer a lightweight alternative to a browser/Electron experience.

## 6. Core user experience

### 6.1 Onboarding & connection
- Choose/enter an **Accord server URL** (base + gateway + CDN derived or entered).
- **Authenticate** with Accord credentials or a token (token type `User`/`Bot`); support MFA if the server requires it.
- Persist session securely (Hive) and reconnect automatically.
- Support **multiple servers/accounts** (Bonfire already supports an account switcher pattern).

### 6.2 Navigation
- **Spaces** rail (list of communities the user belongs to).
- **Channels** list per space (categories, text/forum channels; voice channels shown but disabled/hidden this phase).
- **Direct messages**.
- Responsive layout: collapses to a drawer on mobile, multi-pane on desktop/web (Bonfire behaviour).

### 6.3 Messaging
- Real-time message stream (create/edit/delete) over the Accord gateway.
- Compose with text, attachments/uploads, replies, and mentions.
- **Reactions** (add/remove), emoji picker (Unicode + custom space emoji).
- **Markdown rendering** (reuse Bonfire's `markdown_viewer`), code blocks, embeds, link previews.
- Typing indicators, read state, unread badges.
- Message search within a space/channel.

### 6.4 Members & presence
- Member list per space with roles, nicknames, avatars.
- Presence/status display.
- User profile view.

### 6.5 Roles & moderation (admin)
- View roles and permissions.
- Core moderation actions the Accord API exposes: kick, ban/unban, manage channels, manage roles, invites, audit log viewing.
- Surfaced progressively; mirror the Godot client's admin dialogs where practical.

### 6.6 Notifications
- In-app unread/mention indication.
- Local notifications where the platform supports them. (Firebase/Discord push is removed; any push solution must be Accord/Daccord-native and is a later concern.)

## 7. Platform support targets

| Platform | Target | Notes |
|----------|--------|-------|
| Android  | ✅ Primary | |
| iOS      | ✅ Primary | |
| Web      | ✅ Supported | may need a CORS/proxy story per server |
| Windows  | ✅ Supported | |
| Linux    | ✅ Supported | media_kit deps |
| macOS    | ✅ Supported | needs validation |

## 8. Success criteria

- A user can connect to an Accord server, log in, and exchange messages in real time on at least Android, desktop, and web.
- Spaces, channels, members, reactions, and search work against a live `accordserver`.
- No remaining runtime dependency on `discord.com` or the firebridge package.
- Branding is Daccord, not Bonfire/Discord; license remains GPLv3.

## 9. Phasing (product view)

1. **Foundation** — rebrand, configurable Accord server connection, auth, retire Discord paths.
2. **Read path** — spaces → channels → message history rendering against accordkit.
3. **Write path** — send/edit/delete, attachments, reactions, typing.
4. **Members & roles** — member list, profiles, basic moderation.
5. **Polish & parity** — search, invites, emoji management, notifications, settings.
6. **Deferred** — voice/video, plugin activities, account sync.

## 10. Open questions

- Per-server web CORS strategy (does each Accord server expose CORS, or do we need a proxy?).
- Notification delivery mechanism for Daccord (no Firebase) — push vs. background polling vs. server-sent.
- How much of the Godot client's admin surface to bring over in phase 4 vs. later.
- Account/server discovery UX (directory) — in or out for v1.

See [`technical-spec.md`](./technical-spec.md) for the implementation plan.
