# CLAUDE.md

Flutter/Dart client for Daccord (Accord protocol chat), forked from
[Bonfire](https://github.com/OpenBonfire/bonfire) with its Discord networking
replaced by `accordkit`. The migration is complete; remaining work is feature
polish.

## Hard rules

- **No Discord.** Talk only to Accord servers. Never add Discord endpoints,
  branding, OAuth, or Firebase push.
- **GPL-3.0.** Keep `LICENSE` as is. MIT deps (accordkit) are fine.
- **Reuse, don't rewrite.** Adapt existing Bonfire widgets/controllers/routing;
  keep new code in `lib/features/<feature>/` and match surrounding style.
- **Voice/video/screen share are real features** (LiveKit). Don't stub or hide them.
- **Don't wrap `MainWindow` in another `MaterialApp`/Navigator** — go_router's
  navigator must stay root (#324). `ProfileGate` and the call banner are hosted
  via `buildAppShell` (`lib/shared/components/app_shell.dart`).
- If you change dependencies, codegen, build/test commands, CI, or user-visible
  behavior, update `README.md` / `docs/` in the same change.

## Stack

- Riverpod 3 with codegen (`*.g.dart` are the only generated files). After
  editing any `@riverpod` file run `scripts/codegen.sh --check`.
- `go_router`; `hive_ce` storage (boxes opened in `setupHive()`); client-local
  models hand-roll `fromJson`/`toJson`.
- Vendored packages, edited in place:
  - `packages/accordkit` — Accord REST + gateway + models (has its own CLAUDE.md).
  - `packages/livekit_client` — fork for a Linux native-release crash (#68).
  - `packages/media_kit` — fork for a libmpv dispose SIGABRT.
  - `packages/markdown_viewer` — markdown renderer.
- Terminology: Discord guild → **Space** (`AccordSpace`); channel/message/
  member/user/role map to `Accord*` equivalents.

## Where things live

- Clients: `AccordAuth` (`lib/features/authentication/repositories/accord_auth.dart`,
  `accordAuthProvider`) owns one `AccordClient` per server.
  `lib/features/server/controllers/connections.dart` holds per-connection UI state.
- Gateway events: `lib/features/events/services/accord_event_handler.dart`
  dispatches to per-feature cache controllers (`accord_messages`,
  `accord_members`, `accord_channels`, …), which also own REST calls for their
  domain. Messages → `accord_message_events.dart`; READY → `accord_ready_sync.dart`.
- Voice: `lib/features/voice/` (`VoiceConnection` over `VoiceSession`/LiveKit
  `Room`; credentials from `client.voice.join`).
- Deep links (`daccord://`): `ServerUri.parseDeepLink()`, held in
  `pendingDeepLinkProvider` until the connection is ready.
- Read state: use `ReadStateController.acknowledge`
  (`lib/features/channels/controllers/read_state.dart`) for local reads (handles
  retries, monotonic cursors, notification dismissal).
- AutoMod: `lib/features/automod/`, contract in `docs/automod.md`. Moderator
  mutations opt out of 429 retry; private evidence uses the authenticated SDK
  endpoint and is cleared on account change.
- Credential vault ops share an isolate-wide queue (Linux backend rewrites the
  whole vault).
- `tool/store_capture/` — App Store screenshot harness, not part of `flutter test`.
- Links: Universal Links use `https://www.daccord.gg/open/`; before shipping the
  iOS entitlement verify the site association file, signing profile, and a
  physical-device launch (`docs/app-store-deploy.md`).
- Saved-account joins: `AccordAuth.ensureConnectionForBaseUrl` +
  `joinOnConnection` before asking for credentials; `pendingServerJoinProvider`
  keeps the invite through login. Endpoint identity keeps scheme/port/path distinct.
- Voice `voiceRelayOnly`: opt-in, applied on connect and every reconnect; TURN
  only, never falls back to direct candidates.
- YouTube embeds: official iframe API on web (via `web` dep), external link on
  native. Poster/player requests stay behind explicit consent; release players
  on visibility/lifecycle changes. `showEmbeds` is local; server suppression is #352.
- Space media: `SpaceMediaCache` evicts only replaced assets and revisions URLs
  so mounted images refresh. Web composer leaves paste to the browser.
- MCP `space_management` tools: `lib/features/developer/services/mcp_tools/space_management.dart`
  (fetch fresh permissions before mutating); see `docs/developer/mcp-space-management.md`.
- Package managers: `docs/packaging.md`. Builds use
  `--dart-define=PACKAGE_MANAGER=true` (or `DACCORD_PACKAGE_MANAGER` /
  `daccord.package-manager` marker); `isSelfUpdateEnabled` gates the updater, not
  Developer Mode. Don't advertise catalogue install commands before acceptance.
  Test: `python3 -m unittest discover -s test/packaging -p 'test_*.py'`.

Accord behavior reference: `packages/accordkit` source. The old Godot client is
on the `legacy-godot` branch (`../daccord` is this repo, not the Godot client).

## Commands

```bash
flutter pub get
scripts/codegen.sh --check                   # regenerate + verify *.g.dart
flutter analyze --no-fatal-infos
flutter test [path/to/file_test.dart]
(cd packages/accordkit && dart analyze && dart test)
flutter run --flavor github                  # Android requires --flavor (github|play)
flutter build apk --flavor github            # sideload APK (self-updater)
flutter build appbundle --flavor play --dart-define=APP_STORE=true
flutter build web --no-tree-shake-icons --release   # Web (JavaScript)
```

Release/store builds and signing: `docs/release-signing.md`,
`docs/app-store-deploy.md`. CI: `.github/workflows/`.
