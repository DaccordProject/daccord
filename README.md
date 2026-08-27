# Daccord — Flutter Client

### Communication without compromise.

**Daccord** is the free, open-source alternative to Discord — chat, voice, and video with native apps you control. This repository is the **Flutter client**: a fast, beautiful, cross-platform app that talks to *your* server, not someone else's cloud.

No ads. No first-party analytics or tracking. No corporate lock-in. **Your server, your data, your rules.**

<p align="left">
  <img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-blue.svg">
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-027DFD.svg">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-success.svg">
  <img alt="Status: early development" src="https://img.shields.io/badge/status-early%20development-orange.svg">
</p>

> ⚠️ **Early development.** Daccord is moving fast and things may change. Expect rough edges — and help us file them down.

---

## Why Daccord?

Discord is great until it isn't — until your community gets the wrong end of a moderation bot, until features you relied on disappear behind a paywall, until you realize none of it is actually *yours*.

Daccord flips the model. The people who show up are what make a community — not the platform that hosts it.

- 🔒 **Your data, your rules.** No ads, first-party analytics, telemetry, or crash reporting. See the [network and privacy disclosure](docs/privacy-network.md) for the requests normal operation can make.
- 🏠 **Self-hosted by design.** Don't just *join* a server — run your own. Keep full control of your community data, accounts, uploads, and voice traffic; Daccord does not proxy that traffic.
- 🆓 **Free and open source.** GPLv3-licensed and community-driven, with nothing locked behind a paywall.
- 🌍 **Native on every platform.** Lightweight, fast, and built with Flutter, with a responsive UI that adapts from phone to desktop.

This client is the front door: one native app for every screen you own.

---

## ✨ Features

- 💬 **Real-time messaging** — send, edit, delete, and reply over WebSocket, across channels and DMs. Updates that feel alive.
- 🌐 **Multi-server** — connect to many Daccord servers at once and switch between them seamlessly. Your work crew and your gaming crew, side by side.
- 🔗 **Destination-aware app links** — installed clients can open shared server, space, channel, thread, and message destinations after the owning account is ready.
- 😀 **Emoji** — full unicode support plus custom server emoji, all behind a slick built-in picker.
- 🎙️ **Voice, video & screen sharing** — crystal-clear calls powered by **LiveKit/WebRTC**, with camera and screen share built right in.
- 🛡️ **Server admin tools** — manage channels, roles, bans, invites, and custom emoji without ever leaving the app.
- 📱 **Responsive everywhere** — one UI that flows from phone to desktop, sharp at every size.
- 🌙 **Dark theme** — easy on the eyes, right out of the box.

---

## 📦 Platforms

Native apps for every major platform:

| Android | iOS | Windows | macOS | Linux | Web |
|:---:|:---:|:---:|:---:|:---:|:---:|
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

All platform targets are present in the repository (`android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`).

---

## 🚀 Getting started

Daccord connects only to **Daccord/Accord servers** — there is no Discord integration of any kind. You don't sign in to a central service; you connect directly to a server.

1. Open the app.
2. Click the **`+`** in the server bar on the left.
3. Enter a server address — including your channel and token — like this:

   ```
   chat.example.com#general?token=your-token
   ```

4. That's it — you're in. 🎉

You can add as many servers as you like.

### Don't have a server yet?

Run your own. **AccordServer** is the open-source, Rust-powered backend that powers every Daccord community — your infrastructure, your rules.

➡️ **[github.com/DaccordProject/accordserver](https://github.com/DaccordProject/accordserver)**

---

## 🧱 How it's built

Daccord stands on the shoulders of giants. It's a fork of **[Bonfire](https://github.com/OpenBonfire/bonfire)** — a mature, fast, cross-platform Discord client written in Flutter. We reuse Bonfire's polished UI, theming, routing, and caching, and **replace its Discord networking layer entirely** with the **Accord protocol** via **[accordkit-dart](https://github.com/DaccordProject/accordkit-dart)**.

The result: Bonfire's battle-tested experience pointed at a platform that's actually free and open. The Flutter client is actively working toward feature parity with the Godot client; it has not reached it yet.

### Current limitations

The core messaging, administration, and LiveKit calling paths are implemented, but early-development gaps still affect day-to-day expectations:

- Background push delivery is not implemented; notifications are currently foreground-only ([#81](https://github.com/DaccordProject/daccord/issues/81)).
- DM calls still lack some mid-call state propagation and picture-in-picture behavior available elsewhere ([#141](https://github.com/DaccordProject/daccord/issues/141)).
- `@everyone` / `@here` permission checks, autocomplete, and suppression behavior are incomplete ([#213](https://github.com/DaccordProject/daccord/issues/213)–[#216](https://github.com/DaccordProject/daccord/issues/216)).
- Device-profile storage isolation on Web does not yet match native platforms ([#247](https://github.com/DaccordProject/daccord/issues/247)).
- Store signing and distribution setup is still being completed for some release targets ([#90](https://github.com/DaccordProject/daccord/issues/90), [#123](https://github.com/DaccordProject/daccord/issues/123)).

See the [open issue tracker](https://github.com/DaccordProject/daccord/issues) for the current backlog rather than treating this list as exhaustive.

A thin repository layer subscribes to Accord gateway streams, updates a local cache, and exposes Riverpod providers to the UI.

### Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language / framework | Dart / Flutter | |
| State management | [Riverpod 3](https://riverpod.dev/) | `flutter_riverpod` + `riverpod_annotation` codegen (`*.g.dart`) |
| Routing | [`go_router`](https://pub.dev/packages/go_router) | |
| Local storage | [`hive_ce`](https://pub.dev/packages/hive_ce) | boxes: `auth`, `last-location`, `added-accounts`, `accord-session`, `accord-settings` |
| Networking | [`accordkit`](https://github.com/DaccordProject/accordkit-dart) | Accord protocol SDK — REST + gateway WebSocket + models. Vendored in-tree at `packages/accordkit` |
| Voice / video / screen share | [`livekit_client`](https://pub.dev/packages/livekit_client) | local fork at `packages/livekit_client`, over WebRTC |
| Media | [`media_kit`](https://pub.dev/packages/media_kit) / `cached_network_image` | CDN URLs point at the Accord server |
| Markdown | `markdown_viewer` | custom renderer at `packages/markdown_viewer` |
| Serialization | Hand-written JSON | most model types come from `accordkit` (`Accord*`) |

### Domain model

Accord uses similar-but-distinct vocabulary from Discord:

| Term | accordkit type | Meaning |
|---|---|---|
| **Space** | `AccordSpace` | a server / community |
| **Channel** | `AccordChannel` | text, voice, forum, or category |
| **Message** | `AccordMessage` | |
| **Member** | `AccordMember` | a user within a space |
| **User** | `AccordUser` | |
| **Role** | `AccordRole` | |

---

## 🛠️ Building from source

You'll need the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.

```bash
flutter pub get
dart run build_runner watch -d        # keep running during dev (Riverpod codegen)
flutter run --flavor github            # Android device/emulator (a flavor is required)
flutter run -d chrome                  # browser; non-Android platforms have no flavor
```

`build_runner watch -d` regenerates Riverpod `*.g.dart` files. Keep it running
while developing, or run the same one-shot generation check as CI after editing
any `@riverpod`-annotated file:

```bash
scripts/codegen.sh --check
```

`scripts/codegen.sh --check` is the same check CI runs: it performs a
deterministic one-shot build and lists any tracked or untracked `*.g.dart`
outputs that still need to be committed.

### Lint & test

```bash
flutter analyze --no-fatal-infos       # --no-fatal-infos keeps inherited Bonfire-style infos non-fatal
flutter test                           # unit/widget tests (voice/settings/server logic)
(cd packages/accordkit && dart analyze && dart test)
(cd packages/markdown_viewer && \
  flutter analyze --no-fatal-infos && flutter test)
gradle --project-dir android :livekit_client:testDebugUnitTest \
  --tests io.livekit.plugin.AudioResamplerTest
```

CI treats the full vendored-package suites, including all Markdown renderer
corpus cases, and the Android native seam as merge and release gates.

### Release builds

```bash
flutter build apk     --flavor github --no-tree-shake-icons   # Android sideload APK
flutter build appbundle --flavor play --dart-define=APP_STORE=true   # Play Store AAB
flutter build web     --no-tree-shake-icons --release   # Web (JavaScript)
flutter build windows
flutter build macos
flutter build linux                               # needs libmpv / media_kit deps
flutter build ios     --release --no-tree-shake-icons --no-codesign
```

Before a tagged release, maintainers can run the manual **Windows signing smoke
test** workflow to validate the Certum cloud certificate and Authenticode trust
path without publishing an artifact. See [release signing](docs/release-signing.md).

---

## ❓ FAQ

**Is Daccord really free?**
Yes — completely free and open source under the GPLv3. Nothing is locked behind a paywall.

**Does Daccord connect to Discord?**
No. This client talks *only* to Daccord/Accord servers. There is no Discord integration — none of your data goes to Discord, and the app never connects to Discord's services.

**Where is my data stored?**
Community data is stored on whichever Accord server you connect to — including one you host yourself. Daccord does not proxy that server or voice traffic. The client can still make ancillary requests for discovery, updates, and explicitly approved external media; see [Network behavior and privacy](docs/privacy-network.md).

**Do I need to run a server to use Daccord?**
No — you can join any Accord server you have an address and token for. But hosting your own gives you full control. See [Don't have a server yet?](#dont-have-a-server-yet)

**Which platforms are supported?**
Android, iOS, Windows, macOS, Linux, and the Web.

---

## 🤝 Be part of it

> This only works if we do it together.

Daccord grows because people like you show up. It's open source and community-driven — every contribution, bug report, and pull request makes it better for everyone.

- 🐛 **Report bugs** — open an [issue](https://github.com/DaccordProject/daccord/issues) and help us improve.
- 💻 **Contribute code** — pull requests are welcome.
- 🚀 **Launch a server** — host your own [AccordServer](https://github.com/DaccordProject/accordserver) and grow a community.
- 💖 **Sponsor the project** — [back it on Ko-fi](https://ko-fi.com/krazyjakee) and keep development moving.

If you're contributing code, a few house rules keep this a port rather than a rewrite:

- Keep changes **minimal and reuse-first** — prefer adapting existing Bonfire widgets, controllers, routing, and theming.
- Keep new code inside the relevant `lib/features/<feature>/` module and match the surrounding style.
- Run `dart run build_runner build -d` after touching any `@riverpod`-annotated file.
- Update contributor and user documentation in the same PR when changing dependencies, generation, build/test commands, CI, supported platforms, or feature behavior. Reviewers should verify those instructions against `pubspec.yaml` and the workflows instead of preserving volatile version or test-count claims.
- **No Discord.** Don't reintroduce Discord endpoints, branding, or Firebase push. This client talks only to Accord servers.
- Run `flutter analyze --no-fatal-infos` and `flutter test` before opening a PR.

---

## 💖 Support the project

Hi! I'm **Jacob Cattrall** 🎮 — creator and maintainer of the **Daccord Project**: the Accord protocol, [AccordServer](https://github.com/DaccordProject/accordserver), and this cross-platform client. Together they give communities chat, voice, and video that they actually own — free, ad-free, and self-hosted.

I'm looking for sponsors to help sustain and grow it: more development time, better documentation, more features, and deeper support for the people running their own servers. Sponsorship is what keeps Daccord independent — no ads, no paywalled features, no investor deciding what your community gets to keep.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/krazyjakee)

Every contribution — however small — goes straight into maintaining and improving the project. Thank you. 🙏

---

## Related repositories

| Repo | What it is | Language | License |
|---|---|---|---|
| **this repo** | Flutter client (what you ship) | Dart / Flutter | GPL-3.0 |
| [`accordserver`](https://github.com/DaccordProject/accordserver) | Accord server backend | Rust | — |

`accordkit`, `livekit_client`, and `markdown_viewer` are vendored in-tree under `packages/` and maintained in this repository.

---

## 📄 License

Licensed under the **[GNU General Public License v3.0](LICENSE)** (GPLv3), inherited from Bonfire. AccordKit-Dart is MIT-licensed; GPLv3 may incorporate MIT-licensed code, so depending on `accordkit` is fine.
