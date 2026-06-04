# Daccord Flutter Client — Technical Specification

> Status: Draft · Owner: Daccord Project · Last updated: 2026-06-04
> Companion to [`product-spec.md`](./product-spec.md). See also the root [`CLAUDE.md`](../CLAUDE.md).

## 1. Strategy

Fork [Bonfire](https://github.com/OpenBonfire/bonfire) and **replace its networking layer** (the `packages/firebridge` Discord SDK) with [`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart), while keeping Bonfire's Flutter UI, Riverpod state, routing, theming, and caching patterns. This is a **port, not a rewrite** — minimize UI churn; concentrate change in data/repository/event layers.

Key constraints (see `CLAUDE.md` for the authoritative list):
- No Discord integration; talk only to Accord servers.
- License remains **GPL-3.0** (Bonfire's). `accordkit`/`daccord` are MIT and may be incorporated.
- Voice/video and plugin/GDExtension work are **deferred**.

## 2. Current architecture (inherited)

- **UI/State:** Flutter + Riverpod 3 (codegen), `go_router`, Freezed + `dart_mappable`.
- **Networking (to retire):** `packages/firebridge` (Nyxx fork) — Discord REST v9 (`discord.com/api/v9`) + gateway WebSocket; `packages/firebridge_extensions` for pagination/sanitization.
- **Events:** `lib/features/events/` subscribes to firebridge's cache/gateway and updates Riverpod providers.
- **Storage:** `hive_ce`.
- **Reusable, protocol-agnostic:** `packages/markdown_viewer`, theming, most `shared/components`, media handling, file picking.

### Discord coupling to remove (audit targets)
- `packages/firebridge/lib/src/api_options.dart` — hardcoded `discord.com`, `cdn.discordapp.com`, API v9.
- `lib/features/authentication/repositories/auth.dart` — `discord.com/api/v9/auth/login`, `/auth/mfa/totp`, CORS proxy host, web gateway tweaks.
- `packages/firebridge/lib/src/gateway/*` — Discord gateway/shard logic.
- Firebase push (`firebase_messaging`, `firebase_core`) and OpenBonfire CI/proxy/signing in `.github/workflows/` and README.

## 3. Target architecture

```
┌──────────────────────────────────────────────┐
│ Flutter UI (REUSED from Bonfire)              │
│  features/*/views, shared/components, theme   │
├──────────────────────────────────────────────┤
│ Riverpod controllers (REUSED, re-typed)       │
├──────────────────────────────────────────────┤
│ Accord repository + event layer (NEW)         │
│  - subscribes to AccordClient gateway streams │
│  - maintains caches, exposes providers        │
├──────────────────────────────────────────────┤
│ accordkit (AccordClient): REST + Gateway WS   │  ← replaces firebridge
├──────────────────────────────────────────────┤
│ accordserver (Rust backend)                   │
└──────────────────────────────────────────────┘
```

### 3.1 Dependency change
`pubspec.yaml`:
```yaml
dependencies:
  accordkit:
    git:
      url: https://github.com/DaccordProject/accordkit-dart
  # firebridge / firebridge_extensions removed once nothing imports them
```

### 3.2 AccordClient integration
Wrap a single `AccordClient` per connected server in a Riverpod provider:
```dart
final client = AccordClient(
  token: session.token,
  tokenType: 'User',
  baseUrl: server.baseUrl,
  gatewayUrl: server.gatewayUrl,
  intents: [GatewayIntents.spaces, GatewayIntents.messages, GatewayIntents.messageContent],
);
client.login();
```
- REST via namespaced APIs (`client.spaces`, `client.channels`, `client.messages`, …) returning `RestResult` (`.ok/.data/.error/.cursor`).
- Gateway via typed streams (`client.onMessageCreate`, `onReady`, `onPresenceUpdate`, …). Mirror `lib/features/events/` wiring: stream → cache update → provider invalidation/state push.

## 4. Domain model mapping

| Bonfire (firebridge / Discord) | accordkit | Migration note |
|---|---|---|
| Guild | `AccordSpace` | rename "guild" feature concepts to "space" gradually |
| Channel | `AccordChannel` | types: text/voice/forum/category |
| Message | `AccordMessage` | |
| Member | `AccordMember` | nested `user`, `roles`, `permissions` |
| User | `AccordUser` | |
| Role | `AccordRole` | permission bitmasks |
| Reaction/Emoji | `AccordReaction` / `AccordEmoji` | |
| Attachment/Embed | `AccordAttachment` / `AccordEmbed` | |
| Snowflake | string|int | accordkit parses leniently |
| Presence/Typing | `AccordPresence` / gateway `onTypingStart` | |

**Adapter vs. replace:** prefer using `Accord*` models directly in repositories/controllers. Where a Bonfire widget is tightly bound to a firebridge model shape, write a thin adapter rather than rewriting the widget — but delete adapters as widgets are migrated.

## 5. Configuration & server connection

- Introduce a **server config model** (base URL, gateway URL, CDN URL; gateway/CDN may be derived from base by convention `wss://<host>/ws`, `<base>/cdn`).
- Replace hardcoded Discord hosts; persist server config in Hive alongside session.
- Support **multiple servers/accounts** (reuse Bonfire's account-switcher).
- CDN/avatar/attachment URL builders re-point at the Accord server (accordkit provides CDN URL helpers).

## 6. Authentication

- Replace `lib/features/authentication/repositories/auth.dart` Discord calls with `client.auth` against the chosen Accord server.
- Flow: enter server URL → credentials (or paste token) → optional MFA → receive token → persist → `login()` gateway.
- Remove the OpenBonfire CORS proxy; web auth/CORS handled per Accord server (open question — may need a proxy).

## 7. Event/real-time layer

- New `accord_event_handler` analogous to `lib/features/events/utils/event_handler.dart`.
- Subscribe to relevant gateway streams; update caches for spaces, channels, messages, members, presence, reactions, typing.
- Handle lifecycle: `onConnected/onDisconnected/onReconnecting/onReady/onResumed` → connection state provider, with auto-reconnect (accordkit already does backoff).

## 8. Media & rendering

- Keep `markdown_viewer`, `media_kit`, `cached_network_image`, `file_picker`.
- Re-point image/attachment URL resolution at Accord CDN.
- Attachments upload via accordkit message-create-with-attachments (multipart supported).

## 9. Notifications

- Remove `firebase_messaging`/`firebase_core` and Discord push registration.
- Phase 1: in-app unread/mention state + `flutter_local_notifications` where applicable.
- Real push for Daccord is a later, separate design (no Firebase).

## 10. Platform & build

- Keep all platform folders (android/ios/web/windows/linux/macos).
- Update app identifiers, names, icons → Daccord branding.
- Rewrite `.github/workflows/` to build Daccord artifacts; drop OpenBonfire deploy/proxy/signing. Build commands unchanged (see `CLAUDE.md`).
- Web: validate CORS against a real Accord server; document any proxy requirement.

## 11. Migration plan (ordered, incremental)

Each step should compile and run; gate Discord removal behind getting the Accord equivalent working.

1. **Rebrand & scaffolding** — names, identifiers, icons, README; create `docs/` (done); add `accordkit` dep.
2. **Server config + auth** — server-URL entry, `client.auth` login, session persistence; remove Discord auth host & CORS proxy.
3. **Connection/event layer** — `AccordClient` provider + Accord event handler; connection-state UI.
4. **Read path** — spaces rail → channel list → message history (REST + gateway `onMessageCreate`), rendered via existing widgets re-typed to `Accord*`.
5. **Write path** — send/edit/delete, attachments, reactions, typing indicators.
6. **Members & roles** — member list, profiles, presence; basic moderation (kick/ban/invites/audit log).
7. **Parity polish** — search, emoji management, settings, local notifications.
8. **Retire firebridge** — remove `packages/firebridge` + `firebridge_extensions`, `firebase_*`, and any dead Discord code once unreferenced.
9. **Deferred** — voice/video (`client.voiceManager` + transport), plugin activities, account sync.

## 12. Testing

- Bonfire's test suite is minimal; add tests as the new layer lands.
- accordkit accepts injectable HTTP/socket factories → unit-test repositories without live network.
- Run `flutter analyze` and `flutter test` in CI; add an integration smoke test against a local `accordserver` where feasible.

## 13. Risks & open questions

- **Web CORS** per Accord server (proxy vs. native CORS) — blocks web auth until resolved.
- **Model-shape coupling** in some Bonfire widgets may require more adapters than expected.
- **Notification delivery** for Daccord without Firebase — undesigned.
- **Feature gaps** between firebridge assumptions (Discord-specific fields) and Accord models — audit per feature.
- **CI/signing** must be rebuilt for Daccord distribution.
- **Voice** deferral means voice-channel UI must be cleanly hidden/disabled, not half-wired.

## 14. References

- SDK source & usage: `../accordkit-dart` (`lib/src/`, `example/`).
- Reference client (features/UX to match): `../daccord` (`scenes/`, `scripts/`, `addons/accordkit/`).
- Backend & protocol: [`accordserver`](https://github.com/DaccordProject/accordserver), [`accordserver-mcp`](https://github.com/DaccordProject/accordserver-mcp).
