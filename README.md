# Daccord

A fast, cross-platform **Flutter client for [Daccord](https://github.com/DaccordProject)** — a free,
open-source chat platform for communities.

This project is a fork of [Bonfire](https://github.com/OpenBonfire/bonfire) (a Flutter
Discord client). We reuse Bonfire's mature Flutter UI, state management, routing, and
theming, and **replace its Discord networking layer with the Accord protocol** via
[`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart). The goal is feature
parity with the Godot-based reference client, [`daccord`](https://github.com/DaccordProject/daccord).

> **Status:** early development. The Accord networking foundation, auth, read path, and a
> first write path are in place. See [`docs/PROGRESS.md`](docs/PROGRESS.md) for the
> migration status and [`docs/technical-spec.md`](docs/technical-spec.md) for the plan.

## Talks only to Accord

This client connects **only** to Daccord/Accord servers — there is no Discord integration.
You enter your Accord server URL at login; gateway and CDN URLs are derived from it.

## Platform support

All platform targets are present (Android, iOS, Windows, macOS, Linux, Web). As the port is
in progress, parity varies by platform and feature; voice/video is **deferred and out of scope**
for now.

## Developing

Requires the Flutter SDK.

```bash
flutter pub get
dart run build_runner watch -d   # keep running during dev (Riverpod/Freezed codegen)
flutter run                       # run on a connected device/emulator
flutter analyze                   # lint
flutter test                      # tests
```

`accordkit` is consumed as a git dependency (`DaccordProject/accordkit-dart`). When working on
both, a sibling checkout at `../accordkit-dart` is handy.

### Build issues (mostly Linux)

Media playback uses `media_kit` / libmpv. On Linux you may need:

1. **libmpv cannot be found** — install `libmpv` / `libmpv-devel` (package name varies per
   distro). On Fedora, if it's installed but not found:
   `sudo ln -s /usr/lib64/libmpv.so.2 /usr/lib64/libmpv.so.1`.
2. **media_kit build errors** — install `mpv` / `mpv-devel`.
3. **`undefined symbol: vkCreateXlibSurfaceKHR`** — run
   `export LD_LIBRARY_PATH=/lib64:$LD_LIBRARY_PATH` (point this at wherever libmpv lives)
   in the terminal you launch from.

## Architecture

- **State:** Riverpod 3 (codegen) · **Models:** Freezed + `dart_mappable` · **Routing:** `go_router`
- **Storage:** `hive_ce` · **Media:** `media_kit` / `cached_network_image` / `file_picker`
- **Networking:** `accordkit` (`AccordClient`: REST + gateway WebSocket) — replacing the
  legacy `packages/firebridge` (Discord) layer, which is being retired feature by feature.

See [`CLAUDE.md`](CLAUDE.md) for the domain mapping (Discord → Accord) and contributor
guidance.

## License

GPL-3.0 (inherited from Bonfire). See [`LICENSE`](LICENSE). `accordkit` and the reference
`daccord` client are MIT, which GPLv3 may incorporate.
