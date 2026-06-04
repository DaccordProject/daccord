# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## What this project is

This repository is a **Flutter/Dart client for [Daccord](https://github.com/DaccordProject)** — a free, open-source chat platform for communities. It is a **fork of [Bonfire](https://github.com/OpenBonfire/bonfire)**, a fast cross-platform Discord client written in Flutter.

We are repurposing Bonfire's mature, well-structured Flutter UI and reusing as much of it as possible, while **replacing its Discord networking layer with the Accord protocol**. The goal is a native, multi-platform Daccord client that reaches feature parity with the existing Godot-based [`daccord`](https://github.com/DaccordProject/daccord) client.

### Hard requirements (do not violate)

- **No Discord integration.** This client talks **only** to Daccord/Accord servers. All `discord.com`, `cdn.discordapp.com`, Discord gateway, Discord OAuth/token, and Firebase-push code paths are to be removed or replaced. Do not add Discord endpoints back.
- **License stays GPLv3.** Bonfire is licensed GPL-3.0 and we retain it. See `LICENSE`. AccordKit-Dart and the Godot daccord client are MIT — GPLv3 may incorporate MIT-licensed code, so depending on `accordkit` is fine. Keep the `LICENSE` file as GPL-3.0; any new files inherit GPLv3.
- **Reuse Bonfire.** Prefer adapting existing Bonfire widgets, controllers, routing, theming, and caching over rewriting. The networking/models swap is the bulk of the work; the UI should change as little as possible.
- **Defer GDExtensions / native voice.** Voice/video (LiveKit, WebRTC, GDExtension-backed transport) is **out of scope for now**. Stub or hide voice UI; do not build native transport integrations yet.

## The three repositories involved

| Repo | What it is | Language | License | Role here |
|------|-----------|----------|---------|-----------|
| **this repo** (was `bonfire`) | Flutter UI we're adapting | Dart/Flutter | GPL-3.0 | The client we ship |
| [`daccord`](https://github.com/DaccordProject/daccord) (`../daccord`) | Existing reference client | GDScript / Godot 4.5 | MIT | Feature/UX reference to match |
| [`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart) (`../accordkit-dart`) | Accord protocol SDK | Dart | MIT | Our networking layer (replaces firebridge) |

The Accord server backend is [`accordserver`](https://github.com/DaccordProject/accordserver) (Rust). The protocol is documented via [`accordserver-mcp`](https://github.com/DaccordProject/accordserver-mcp).

## Architecture (inherited from Bonfire)

- **State management:** Riverpod 3 (`flutter_riverpod`, `riverpod_annotation` with codegen → `*.g.dart`).
- **Models / serialization:** Freezed + `dart_mappable` (+ some `json_serializable`).
- **Routing:** `go_router`.
- **Local storage:** `hive_ce` (token/session/settings persistence).
- **Networking (TO BE REPLACED):** `packages/firebridge` — a fork of Nyxx that speaks Discord's REST v9 + gateway WebSocket. This is the layer we are swapping out for `accordkit`.
- **Media:** `media_kit` / `cached_network_image` / `file_picker` — reusable as-is, just re-point CDN URLs at the Accord server.
- **Code generation is required during development:** `dart run build_runner watch -d`.

### Layout

```
lib/
  features/        # feature modules (auth, channels, messaging, guild, member, overview, sidebar, user, ...)
    <feature>/
      controllers/ # Riverpod controllers
      repositories/# data access (currently firebridge-backed → migrate to accordkit)
      views/       # screens
      models/      # feature models
  shared/          # shared components, models, repositories, utils
  theme/           # theming
  router/          # go_router config
  main.dart
packages/
  firebridge/            # Discord client lib — being retired in favour of accordkit
  firebridge_extensions/ # pagination/sanitization helpers over firebridge
  markdown_viewer/       # custom markdown rendering — KEEP (protocol-agnostic)
docs/                    # product + technical specs (see below)
android/ ios/ web/ windows/ linux/ macos/   # all platform targets present
```

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

Add as a git dependency in `pubspec.yaml`:

```yaml
dependencies:
  accordkit:
    git:
      url: https://github.com/DaccordProject/accordkit-dart
```

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

- **REST:** namespaced APIs on the client — `client.spaces`, `client.channels`, `client.messages`, `client.members`, `client.roles`, `client.users`, `client.invites`, `client.reactions`, `client.emojis`, `client.auth`, etc. Each call returns a `RestResult` with `.ok`, `.data`, `.error`, `.statusCode`, `.cursor` (cursor pagination). Rate-limit (429) retry is built in.
- **Gateway:** ~50 typed `Stream` properties — `client.onMessageCreate`, `onMessageUpdate`, `onMessageDelete`, `onPresenceUpdate`, `onTypingStart`, `onMemberJoin`, `onChannelCreate`, `onReady`, `onReconnecting`, … plus `onRawEvent`. Wire these into Riverpod controllers the same way Bonfire wires firebridge cache events today (see `lib/features/events/`).
- **Voice:** `client.voiceManager` exists but is **deferred** (see scope rules). Don't integrate native transport yet.

Mirror Bonfire's existing pattern: a thin repository layer subscribes to gateway streams, updates a cache, and exposes Riverpod providers to the UI.

## Build / run / test

```bash
flutter pub get
dart run build_runner watch -d        # keep running during dev (codegen)

flutter run                            # run on a connected device/emulator
flutter analyze                        # lint (analysis_options.yaml)
flutter test                           # tests (currently minimal)

# Release builds
flutter build apk     --no-tree-shake-icons -v          # Android
flutter build web     --no-tree-shake-icons --release   # Web (WASM)
flutter build windows -v
flutter build linux   -v                                # needs libmpv/media_kit deps
flutter build ios     --release --no-tree-shake-icons --no-codesign -v
```

CI lives in `.github/workflows/`. Note the legacy CI deploys to Bonfire infrastructure (`app.openbonfire.dev`) and references OpenBonfire signing/proxy — these must be updated for Daccord before relying on them.

## Migration approach

The recommended sequence (details in `docs/technical-spec.md`):

1. **Rebrand & config** — app name, identifiers, server config (base/gateway/cdn URLs), strip Discord-specific README/CI/Firebase.
2. **Auth** — replace credential/MFA/token login against `discord.com` with `client.auth` against an Accord server; add a server-URL field.
3. **Networking swap** — introduce an `accordkit`-backed repository/event layer paralleling `lib/features/events/`; map gateway events → Riverpod.
4. **Models** — replace firebridge model usage with `Accord*` models (or thin adapters) feature by feature, starting with Space/Channel/Message lists.
5. **Feature parity passes** — messaging, members, roles/admin, invites, reactions, emojis, search — matching the Godot `daccord` client.
6. **Retire firebridge** — once nothing imports it, delete `packages/firebridge` and `firebridge_extensions`.
7. **Voice/GDExtension** — deferred.

When in doubt about Accord behaviour, read `../accordkit-dart` (the SDK source) and `../daccord` (the reference client's scenes/scripts).

## Conventions

- Match the surrounding code's style; Bonfire is feature-modular — keep new code inside the relevant `lib/features/<feature>/` module.
- Run `dart run build_runner build -d` after changing any `@freezed`/`@riverpod`/mappable-annotated file.
- Keep changes minimal and reuse-first; this is a port, not a rewrite.
- Don't reintroduce Discord endpoints, Discord branding, or Firebase push without explicit instruction.
