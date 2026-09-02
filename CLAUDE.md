# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

This repository is a **Flutter/Dart client for [Daccord](https://github.com/DaccordProject)** — a free, open-source chat platform for communities. It is a **fork of [Bonfire](https://github.com/OpenBonfire/bonfire)**, a fast cross-platform Discord client written in Flutter.

We are repurposing Bonfire's mature, well-structured Flutter UI and reusing as much of it as possible, while **replacing its Discord networking layer with the Accord protocol**. The goal is a native, multi-platform Daccord client that reaches feature parity with the existing Godot-based [`daccord`](https://github.com/DaccordProject/daccord) client.

### Hard requirements (do not violate)

- **No Discord integration.** This client talks **only** to Daccord/Accord servers. All `discord.com`, `cdn.discordapp.com`, Discord gateway, Discord OAuth/token, and Firebase-push code paths are to be removed or replaced. Do not add Discord endpoints back.
- **License stays GPLv3.** Bonfire is licensed GPL-3.0 and we retain it. See `LICENSE`. AccordKit-Dart and the Godot daccord client are MIT — GPLv3 may incorporate MIT-licensed code, so depending on `accordkit` is fine. Keep the `LICENSE` file as GPL-3.0; any new files inherit GPLv3.
- **Reuse Bonfire.** Prefer adapting existing Bonfire widgets, controllers, routing, theming, and caching over rewriting. The networking/models swap is the bulk of the work; the UI should change as little as possible.
- **Voice, video & screen sharing are implemented.** Real-time voice, video, and screen sharing (LiveKit/WebRTC transport) are fully supported. Maintain and extend the existing voice stack; don't stub or hide voice UI.

## The three repositories involved

| Repo | What it is | Language | License | Role here |
|------|-----------|----------|---------|-----------|
| **this repo** (was `bonfire`) | Flutter UI we're adapting | Dart/Flutter | GPL-3.0 | The client we ship |
| [`daccord`](https://github.com/DaccordProject/daccord) (`../daccord`) | Existing reference client | GDScript / Godot 4.5 | MIT | Feature/UX reference to match |
| [`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart) (`../accordkit-dart`) | Accord protocol SDK | Dart | MIT | Our networking layer (replaces firebridge) |

The Accord server backend is [`accordserver`](https://github.com/DaccordProject/accordserver) (Rust). The protocol is documented via [`accordserver-mcp`](https://github.com/DaccordProject/accordserver-mcp).

## Architecture (inherited from Bonfire)

- **State management:** Riverpod 3 (`flutter_riverpod`, `riverpod_annotation` with codegen → `*.g.dart`).
- **Models / serialization:** primarily provided by `accordkit` (`Accord*` types). The handful of client-local models (server config, session, device profile, space folders, settings) hand-roll `fromJson`/`toJson` — they're small and Hive-backed, so codegen serializers aren't used. The only generated files in `lib/` are Riverpod's `*.g.dart` files.
- **Routing:** `go_router`.
- **Local storage:** `hive_ce` — boxes opened in `setupHive()`: `auth`, `last-location`, `added-accounts`, `accord-session`, `accord-settings`.
- **Networking:** `accordkit` (vendored in-tree at `packages/accordkit`, maintained here). **The firebridge → accordkit swap is complete** — `packages/firebridge` and `firebridge_extensions` no longer exist and nothing in `lib/` imports them (a few doc comments still mention "firebridge" to describe what a controller replaced). Do not try to re-add firebridge.
- **Voice/video/screen share:** `livekit_client` (a local fork at `packages/livekit_client`, see #68) over WebRTC; credentials fetched via accordkit's `client.voice`. See `lib/features/voice/`.
- **Media:** `media_kit` (+ `media_kit_video`, `video_player_media_kit`, pinned git forks) / `cached_network_image` / `file_picker` — re-point CDN URLs at the Accord server.
- **Riverpod generation is required after changing annotated providers:** run
  `dart run build_runner build -d` once, or keep
  `dart run build_runner watch -d` running while editing them. Client model
  serialization is handwritten; there is no JSON-model generation step.

### Layout

```
lib/
  features/        # feature modules: authentication, spaces, channels, messaging,
    <feature>/     #   member, user, admin, server, events, voice, notifications,
      controllers/ #   settings, developer, profiles, updates, ...
      repositories/# data access (accordkit-backed)
      views/       # screens
      models/      # feature models
  shared/          # shared components, models, repositories, utils
  theme/           # theming
  router/          # go_router config
  main.dart        # startup: media_kit, Hive, ProviderScope, ProfileGate, deep links
packages/
  accordkit/       # Accord protocol SDK (REST + gateway + models) — networking layer, maintained here
  livekit_client/  # local fork of livekit_client 2.8.0 (#68 native-release fix) — voice transport
  markdown_viewer/ # custom markdown rendering — protocol-agnostic, KEEP
docs/              # product + technical specs (see below)
android/ ios/ web/ windows/ linux/ macos/   # all platform targets present
```

Cross-cutting startup features wired in `lib/main.dart`:
- **Server config:** `lib/features/server/models/accord_server.dart` defines `AccordServer` (`baseUrl`/`gatewayUrl`/`cdnUrl`, derived from a base URL). The live per-server `AccordClient` instances are owned by `AccordAuth` (`lib/features/authentication/repositories/accord_auth.dart`, exposed as `accordAuthProvider`); `lib/features/server/controllers/connections.dart` holds the rail's per-connection UI state (session + status + cached spaces), not the clients.
- **Multi-profile:** the app is wrapped in `ProfileGate`/`AppRestart` for switching between accounts.
- **Deep links:** `daccord://` URLs (navigate / connect / invite) are parsed via `ServerUri.parseDeepLink()`. Qualified navigation is held by `pendingDeepLinkProvider` until authentication and the owning connection's live space cache are ready; the `/spaces` route then hands channel/message targeting to `AccordHomeScreen`.
- **Developer mode:** an MCP server (`mcpServerControllerProvider`) for in-app tooling.

## Domain mapping: Discord → Accord

Bonfire's code uses Discord vocabulary; Accord uses similar-but-distinct terms. When migrating a feature, translate:

| Discord (Bonfire / firebridge) | Accord (accordkit) | Notes |
|--------------------------------|--------------------|-------|
| Guild | **Space** (`AccordSpace`) | server/community |
| Channel | **Channel** (`AccordChannel`) | types: text, voice, forum, category |
| Message | **Message** (`AccordMessage`) | |
| Member | **Member** (`AccordMember`) | |
| User | **User** (`AccordUser`) | |
| Role | **Role** (`AccordRole`) | |
| Snowflake | snowflake (string or int) | accordkit parses leniently |
| Gateway (Discord) | Gateway (Accord) | `wss://<server>/ws?v=1&encoding=json` |
| CDN `cdn.discordapp.com` | `<server>/cdn` | configurable per-server |
| User token / OAuth | Accord token (`Bot`/`User` token type) | sent in REST headers + gateway IDENTIFY |

## AccordKit-Dart: the new networking layer

Vendored in-tree and wired via a path dependency in `pubspec.yaml`:

```yaml
dependencies:
  accordkit:
    path: packages/accordkit
```

The SDK source now lives at `packages/accordkit` and is maintained in this repo (no longer a git dependency on `DaccordProject/accordkit-dart`). Edit it directly here.

Entry point is `AccordClient` (`package:accordkit/accordkit.dart`):

```dart
final client = AccordClient(
  token: token,
  tokenType: 'User',            // or 'Bot'
  baseUrl: 'https://your.accord.server',
  gatewayUrl: 'wss://your.accord.server/ws',
  intents: [GatewayIntents.spaces, GatewayIntents.messages, GatewayIntents.messageContent],
);
client.login(); // opens the gateway
```

- **REST:** namespaced APIs on the client — `client.spaces`, `client.channels`, `client.messages`, `client.members`, `client.roles`, `client.users`, `client.invites`, `client.reactions`, `client.emojis`, `client.auth`, etc. Each call returns a `RestResult` with `.ok`, `.data`, `.error`, `.statusCode`, `.cursor` (cursor pagination). Rate-limit (429) retry is built in, as is a per-attempt request timeout (`AccordConfig.defaultRequestTimeout`, overridable via `AccordClient(requestTimeout: …)`) that surfaces as a normal `RestResult` failure. Endpoint paths are bare — the `/api/v1` prefix lives on the `AccordRest` base URL.
- **Gateway:** ~50 typed `Stream` properties — `client.onMessageCreate`, `onMessageUpdate`, `onMessageDelete`, `onPresenceUpdate`, `onTypingStart`, `onMemberJoin`, `onChannelCreate`, `onReady`, `onReconnecting`, … plus `onRawEvent`. Wire these into Riverpod controllers the same way Bonfire wires firebridge cache events today (see `lib/features/events/`).
- **Voice:** `client.voice.join(channelId)` / `client.voice.leave(channelId)` return LiveKit credentials (`AccordVoiceServerUpdate` with `livekitUrl` + `token`); the `livekit_client` SDK (`packages/livekit_client`) is the actual transport. State lives in `VoiceConnection` (Riverpod) over a `VoiceSession` that wraps a LiveKit `Room`. Gateway `voice.server_update` events drive credential-refresh reconnects. See `lib/features/voice/`.

The actual wiring: a single gateway dispatcher (`lib/features/events/controllers/accord_event_handler.dart`) subscribes to every gateway stream and calls imperative mutators on the per-feature Riverpod cache controllers (`accord_messages`, `accord_members`, `accord_channels`, …). Those same controllers own the REST reads/writes for their domain, and screens `watch` them. A dedicated per-feature `repositories/` layer exists only for `authentication` (`AccordAuth`, which owns the clients) — elsewhere data access lives in the controllers (and, for some admin/moderation screens, directly in the views).

## Build / run / test

```bash
flutter pub get
dart run build_runner watch -d        # keep running during dev (codegen)
scripts/codegen.sh --check             # regenerate + verify committed *.g.dart

flutter run --flavor github            # run on a connected device/emulator (Android needs a flavor)
flutter analyze --no-fatal-infos       # lint; --no-fatal-infos keeps inherited Bonfire-style infos non-fatal
flutter test                           # full unit/widget suite; use its reported total
flutter test test/features/voice/voice_logic_test.dart   # run a single test file

# Release builds
# Android has two product flavors (see android/app/build.gradle): `github` (sideload
# APK, keeps the in-app self-updater) and `play` (Play AAB, no self-updater). Android
# builds/runs MUST pass --flavor; other platforms have no flavors.
flutter build apk       --flavor github --no-tree-shake-icons -v          # Android sideload APK
flutter build appbundle --flavor play  --dart-define=APP_STORE=true       # Play Store AAB
flutter build web     --no-tree-shake-icons --release   # Web (JavaScript)
flutter build windows -v
flutter build linux   -v                                # needs libmpv/media_kit deps
flutter build ios     --release --no-tree-shake-icons --no-codesign -v
```

CI lives in `.github/workflows/` and is Daccord-native (no OpenBonfire infra):
- `ci.yml` — blocking jobs cover root codegen/analyze/tests, vendored `accordkit`, the full `markdown_viewer` suite, and LiveKit's Android native unit tests. Broader server/UI scenarios remain advisory. The `build` job is a Web (JavaScript)/Android/Linux/Windows matrix.
- `release.yml` — tag-driven (`v*`); validates the tag matches `pubspec.yaml` version, gates on `ci.yml`, builds all platforms, publishes a GitHub Release.
- `windows-signing-smoke.yml` — manual, non-publishing validation of the real Certum SimplySign login, timestamping, and Authenticode trust path.

## Migration status

The Discord → Accord migration is **essentially complete**: firebridge is gone, all 50+ feature files use `accordkit`, auth/spaces/channels/messaging/members/roles/voice are implemented, and there are no Discord/Firebase code paths left. Remaining work is **feature-parity polish** against the Godot `daccord` client (reactions, emojis, search, admin edge cases) rather than the wholesale swap.

When in doubt about Accord behaviour, read `packages/accordkit` (the vendored SDK source) and `../daccord` (the reference client's scenes/scripts).

## Conventions

- Match the surrounding code's style; Bonfire is feature-modular — keep new code inside the relevant `lib/features/<feature>/` module.
- Run `scripts/codegen.sh --check` after changing any `@riverpod`-annotated
  file. It regenerates `*.g.dart` and fails with the tracked or untracked paths
  that still need to be committed.
- Documentation is part of the change: authors who alter dependencies,
  generation, build/test commands, CI, or supported behavior must update
  `README.md`, this file, and relevant `docs/` pages in the same PR. Reviewers
  should verify commands against `pubspec.yaml` and workflows rather than copy
  volatile dependency versions or test counts.
- Keep changes minimal and reuse-first; this is a port, not a rewrite.
- Don't reintroduce Discord endpoints, Discord branding, or Firebase push without explicit instruction.
