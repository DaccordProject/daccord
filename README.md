# Daccord (Flutter)

A free, open-source chat app for communities. Connect to one or more [accordserver](https://github.com/DaccordProject/accordserver) instances and chat in real time with your friends, teammates, or community.

This is the **Flutter client** — a fork of [Bonfire](https://github.com/OpenBonfire/bonfire) that reuses its mature Flutter UI and **replaces the Discord networking layer with the Accord protocol** via [`accordkit-dart`](https://github.com/DaccordProject/accordkit-dart). It aims for feature parity with the Godot-based reference client, [`daccord`](https://github.com/DaccordProject/daccord).

> **Status:** early development. The Accord networking foundation, auth, read path, and a first write path are in place.

## Features

- **Real-time messaging** -- Send, edit, delete, and reply to messages instantly over WebSocket
- **Channels & DMs** -- Organize conversations into channels or message people directly
- **Multi-server** -- Connect to multiple servers at the same time
- **Emoji** -- Unicode and custom server emoji with a built-in picker
- **Voice, video & screen sharing** -- Join voice and video channels and share your screen in real time
- **Server admin tools** -- Manage channels, roles, bans, invites, and custom emoji
- **Responsive** -- Works on wide monitors and narrow windows alike
- **Dark theme** -- Easy on the eyes, right out of the box

## Talks only to Accord

This client connects **only** to Daccord/Accord servers -- there is no Discord integration. You enter your Accord server URL at login; gateway and CDN URLs are derived from it.

## Platform support

All platform targets are present (Android, iOS, Windows, macOS, Linux, Web), including voice, video, and screen sharing.

## Getting started

When you first open Daccord, the window will be empty. To start chatting:

1. Click the **+** button in the server bar on the left
2. Enter your server URL (for example: `chat.example.com#general?token=your-token`)
3. That's it -- you'll be connected and can start chatting right away

You can add as many servers as you like. Need a server to connect to? Check out [accordserver](https://github.com/DaccordProject/accordserver) to host your own.

## Building from source

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```bash
flutter pub get
dart run build_runner watch -d   # keep running during dev (Riverpod/Freezed codegen)
flutter run                       # run on a connected device/emulator
flutter analyze                   # lint
flutter test                      # tests
```

`accordkit` is consumed as a git dependency (`DaccordProject/accordkit-dart`). When working on both, a sibling checkout at `../accordkit-dart` is handy.

### Build issues (mostly Linux)

Media playback uses `media_kit` / libmpv. On Linux you may need:

1. **libmpv cannot be found** -- install `libmpv` / `libmpv-devel` (package name varies per distro). On Fedora, if it's installed but not found: `sudo ln -s /usr/lib64/libmpv.so.2 /usr/lib64/libmpv.so.1`.
2. **media_kit build errors** -- install `mpv` / `mpv-devel`.
3. **`undefined symbol: vkCreateXlibSurfaceKHR`** -- run `export LD_LIBRARY_PATH=/lib64:$LD_LIBRARY_PATH` (point this at wherever libmpv lives) in the terminal you launch from.

## Architecture

- **State:** Riverpod 3 (codegen) · **Models:** Freezed + `dart_mappable` · **Routing:** `go_router`
- **Storage:** `hive_ce` · **Media:** `media_kit` / `cached_network_image` / `file_picker`
- **Networking:** `accordkit` (`AccordClient`: REST + gateway WebSocket). The legacy `packages/firebridge` (Discord) layer has been fully retired.

See [`CLAUDE.md`](CLAUDE.md) for the domain mapping (Discord → Accord) and contributor guidance.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request.

## License

GPL-3.0 (inherited from Bonfire). See [`LICENSE`](LICENSE). `accordkit` and the reference `daccord` client are MIT, which GPLv3 may incorporate.
