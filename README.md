# Daccord — Flutter Client

### Communication without compromise.

**Daccord** is the free, open-source alternative to Discord — chat, voice, and video with native apps you control. This repository is the **Flutter client**: a fast, beautiful, cross-platform app that talks to *your* server, not someone else's cloud.

No ads. No first-party analytics or tracking. No corporate lock-in. **Your server, your data, your rules.**

<p align="left">
  <img alt="License: GPLv3" src="https://img.shields.io/badge/license-GPLv3-blue.svg">
  <a href="https://github.com/DaccordProject/daccord/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/DaccordProject/daccord"></a>
  <img alt="Built with Flutter" src="https://img.shields.io/badge/built%20with-Flutter-027DFD.svg">
  <img alt="Platforms" src="https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Web-success.svg">
  <img alt="Status: early development" src="https://img.shields.io/badge/status-early%20development-orange.svg">
</p>

> ⚠️ **Early development.** Daccord is moving fast and things may change. Expect rough edges — and help us file them down.

📖 **[User documentation](docs/index.md)** · 📥 **[Download](https://github.com/DaccordProject/daccord/releases/latest)** · 🐛 **[Issues](https://github.com/DaccordProject/daccord/issues)**

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

**Messaging**

- 💬 **Real-time messaging** — send, edit, delete, and reply over the Accord gateway, with typing indicators and live presence.
- 🧵 **Threads, forums & pins** — branch a conversation into a thread, run forum-style channels, and pin what matters.
- 😀 **Reactions & emoji** — full unicode support plus custom server emoji, all behind a slick built-in picker.
- 📎 **Files & media** — drag and drop attachments, with inline images, video, and audio playback and a full-screen lightbox.
- 🔍 **Search** — space-scoped message search that jumps you straight to the hit.
- ✉️ **Direct messages & DM calls** — private conversations, one-to-one and group, with voice and video.

**Voice & video**

- 🎙️ **Voice, video & screen sharing** — crystal-clear calls powered by **LiveKit/WebRTC**, with camera and screen share built right in.

**Servers & communities**

- 🌐 **Multi-server** — connect to many Daccord servers at once and switch between them seamlessly. Your work crew and your gaming crew, side by side.
- 🧭 **Discovery** — browse public spaces from the server directory and join them, even before you've signed in anywhere.
- 🛡️ **Server admin tools** — manage channels, roles, permissions, bans, invites, and custom emoji without ever leaving the app.
- 🔗 **Destination-aware app links** — `daccord://` links open the right server, space, channel, thread, or message once the owning account is ready.

**The app itself**

- 🎨 **Themes** — Dark, Light, Nord, Monokai, and Solarized built in, plus fully custom colors you can copy, paste, and share in chat.
- 👥 **Multiple profiles** — keep separate local profiles on one device and switch between them without signing out.
- 🔐 **Secure sign-in** — session tokens live in the OS credential vault, with optional TOTP two-factor authentication.
- ⬆️ **In-app updates** — desktop and sideloaded Android builds check for, download, and install new releases themselves.
- 📱 **Responsive everywhere** — one UI that flows from phone to desktop, sharp at every size.

---

## 📥 Download

Grab the latest build from the **[Releases page](https://github.com/DaccordProject/daccord/releases/latest)**:

| Platform | File |
|---|---|
| Linux (recommended) | `daccord-linux-x86_64.deb` |
| Linux (portable) | `daccord-linux-x86_64.tgz` |
| Windows (installer) | `daccord-windows-x86_64-setup.exe` |
| Windows (portable) | `daccord-windows-x86_64.zip` |
| macOS | `daccord-macos-universal.dmg` |
| Android | `daccord-android.apk` |
| Web | `daccord-web.zip` |

Every release ships a `SHA256SUMS.txt` so you can verify what you downloaded. Step-by-step instructions per platform live in [Installing daccord](docs/getting-started/installation.md).

iOS and the store channels are built and submitted by the release workflow; public store listings aren't live yet, so the downloads above are the way in today.

### Platform support

| Android | iOS | Windows | macOS | Linux | Web |
|:---:|:---:|:---:|:---:|:---:|:---:|
| ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

All platform targets are present in the repository (`android/`, `ios/`, `windows/`, `macos/`, `linux/`, `web/`).

---

## 🚀 Getting started

Daccord connects only to **Daccord/Accord servers** — there is no Discord integration of any kind. You don't sign in to a central service; you connect directly to a server.

1. Open the app.
2. Click the **`+`** at the bottom of the space bar on the left.
3. Enter the server's address — a hostname is enough:

   ```
   chat.example.com
   ```

   Self-hosting on your own machine or LAN? Include the scheme, e.g. `http://localhost:39099`.

4. Sign in with your username and password, or switch to **Register** to create an account on that server.
5. That's it — you're in. 🎉

You can add as many servers as you like; each gets its own icon in the space bar.

The address also accepts extras: a port (`chat.example.com:8443`), a space (`chat.example.com#my-space`), an invite code (`?invite=…`), or a pre-issued token (`?token=…`, which signs you straight in). See [Adding a Server](docs/getting-started/adding-a-server.md) for the full format.

No address at all? Open **Discovery** and browse public spaces from the server directory.

### Don't have a server yet?

Run your own. **AccordServer** is the open-source, Rust-powered backend that powers every Daccord community — your infrastructure, your rules.

The easiest route is the **Accord desktop app**: a tray application that bundles the server and a LiveKit voice server, configures itself on first launch, and keeps itself updated — no Docker, no command line. For an always-on public server, deploy `accordserver` with Docker or from source.

➡️ **[github.com/DaccordProject/accordserver](https://github.com/DaccordProject/accordserver)** · [Self-hosting guide](docs/self-hosting/overview.md)

---

## 📚 Documentation

End-user documentation lives in [`docs/`](docs/index.md):

- [Installing daccord](docs/getting-started/installation.md) · [Adding a server](docs/getting-started/adding-a-server.md) · [Creating an account](docs/getting-started/creating-an-account.md)
- [Spaces and channels](docs/navigation/spaces-and-channels.md) · [Sending messages](docs/messaging/sending-messages.md) · [Voice and video](docs/voice-and-video/voice-channels.md)
- [Themes and appearance](docs/customization/themes.md) · [Profiles](docs/customization/profiles.md)
- [Managing your space](docs/administration/managing-your-space.md) · [Moderation](docs/administration/moderation.md) · [Invites](docs/administration/invites.md)
- [Self-hosting](docs/self-hosting/overview.md) · [Network behavior and privacy](docs/privacy-network.md) · [Troubleshooting](docs/troubleshooting/common-issues.md)

Maintainer-facing notes: [release signing](docs/release-signing.md) and [store deployment](docs/app-store-deploy.md).

---

## 🧱 How it's built

Daccord stands on the shoulders of giants. It's a fork of **[Bonfire](https://github.com/OpenBonfire/bonfire)** — a mature, fast, cross-platform Discord client written in Flutter. We reuse Bonfire's polished UI, theming, routing, and caching, and **replaced its Discord networking layer entirely** with the **Accord protocol** via **accordkit**.

The result: Bonfire's battle-tested experience pointed at a platform that's actually free and open. This client has replaced the original Godot client as the Daccord app — that codebase is frozen on the [`legacy-godot`](https://github.com/DaccordProject/daccord/tree/legacy-godot) branch.

A single gateway dispatcher subscribes to Accord's event streams, updates per-feature caches, and exposes Riverpod providers to the UI.

### Current limitations

The core messaging, administration, and LiveKit calling paths are implemented, but early-development gaps still affect day-to-day expectations:

- Background push delivery is not implemented; notifications are currently foreground-only ([#81](https://github.com/DaccordProject/daccord/issues/81)).
- Attaching MP3 files fails on Windows ([#196](https://github.com/DaccordProject/daccord/issues/196)).
- Bearer tokens can still be embedded in server URLs instead of exchanged for one-time codes ([#269](https://github.com/DaccordProject/daccord/issues/269)), and self-update integrity verification does not yet fail closed against a signed manifest ([#264](https://github.com/DaccordProject/daccord/issues/264)).
- Store signing and distribution setup is still being completed for some release targets ([#90](https://github.com/DaccordProject/daccord/issues/90), [#123](https://github.com/DaccordProject/daccord/issues/123)), and the iOS App Store submission is still working through review ([#285](https://github.com/DaccordProject/daccord/issues/285), [#286](https://github.com/DaccordProject/daccord/issues/286)).

See the [open issue tracker](https://github.com/DaccordProject/daccord/issues) for the current backlog rather than treating this list as exhaustive.

### Tech stack

| Concern | Choice | Notes |
|---|---|---|
| Language / framework | Dart / Flutter | |
| State management | [Riverpod 3](https://riverpod.dev/) | `flutter_riverpod` + `riverpod_annotation` codegen (`*.g.dart`) |
| Routing | [`go_router`](https://pub.dev/packages/go_router) | |
| Local storage | [`hive_ce`](https://pub.dev/packages/hive_ce) | device boxes `auth`, `last-location`, `added-accounts`, `space-cache`, `window-state`; `accord-session` / `accord-settings` are opened per local profile |
| Credentials | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) | session tokens live in the OS credential vault; Hive keeps only opaque references |
| Networking | `accordkit` | Accord protocol SDK — REST + gateway WebSocket + models. Vendored in-tree at `packages/accordkit` and maintained here |
| Voice / video / screen share | [`livekit_client`](https://pub.dev/packages/livekit_client) | local fork at `packages/livekit_client`, over WebRTC |
| Media | [`media_kit`](https://pub.dev/packages/media_kit) / [`video_player`](https://pub.dev/packages/video_player) / `cached_network_image` | media_kit everywhere except iOS, which uses AVFoundation via `video_player`; CDN URLs point at the Accord server |
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

You'll need the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed. The helper scripts in [`scripts/`](scripts/README.md) wrap the common flows and prefer [fvm](https://fvm.app) when it's available:

```bash
scripts/setup.sh                 # deps + one-shot codegen (also installs Linux desktop build deps)
scripts/codegen.sh --watch       # keep this open while developing
scripts/start.sh --flavor github # run on an Android device/emulator
scripts/start.sh -d chrome       # run in Chrome
```

Or drive Flutter directly:

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

CI treats the root analyze/test job, the full vendored-package suites (including
all Markdown renderer corpus cases), the Android native seam, and the accordkit
protocol-integration job as merge and release gates. Broader client ↔ server,
UI end-to-end, multi-instance, and LiveKit SFU scenarios run advisory
(`continue-on-error`).

### Release builds

```bash
scripts/build.sh                 # Web (JavaScript) release -> build/web/
scripts/build.sh apk             # Android sideload APK (github flavor)
scripts/build.sh appbundle       # Play Store AAB
scripts/build.sh linux           # needs libmpv / media_kit deps
scripts/build.sh windows
scripts/build.sh macos
scripts/build.sh ios -- --no-codesign
```

The equivalent raw Flutter invocations:

```bash
flutter build apk     --flavor github --no-tree-shake-icons   # Android sideload APK
flutter build appbundle --flavor play --dart-define=APP_STORE=true   # Play Store AAB
flutter build web     --no-tree-shake-icons --release   # Web (JavaScript)
flutter build windows
flutter build macos
flutter build linux                               # needs libmpv / media_kit deps
flutter build ios     --release --no-tree-shake-icons --no-codesign
```

Store builds are compiled with `--dart-define=APP_STORE=true`, which disables the
in-app self-updater (store guidelines forbid it). Tagging `v<version>` (matching
`pubspec.yaml`) runs the release workflow: it gates on CI, builds and signs every
platform, publishes the GitHub Release, and submits the store builds. See
[store deployment](docs/app-store-deploy.md).

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
Community data is stored on whichever Accord server you connect to — including one you host yourself. Daccord does not proxy that server or voice traffic. Your session tokens are kept in your operating system's credential vault. The client can still make ancillary requests for discovery, updates, and explicitly approved external media; see [Network behavior and privacy](docs/privacy-network.md).

**Do I need one account per server?**
Yes. Accounts live on the server you register with, so each server you add has its own sign-in. You can be signed in to many at once, and switch local profiles to keep identities separate on a shared device.

**Do I need to run a server to use Daccord?**
No — you can join any Accord server you have an address for, or find one through Discovery. But hosting your own gives you full control. See [Don't have a server yet?](#dont-have-a-server-yet)

**How do I update?**
Desktop and sideloaded Android builds check on startup and can install the update for you. Otherwise grab the newest build from [Releases](https://github.com/DaccordProject/daccord/releases/latest).

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
- Run `scripts/codegen.sh --check` after touching any `@riverpod`-annotated file.
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
| [`accordserver`](https://github.com/DaccordProject/accordserver) | Accord server backend and desktop host app | Rust | — |
| [`daccord-editor`](https://github.com/DaccordProject/daccord-editor) | Author and test Lua-based activity plugins for your server | — | — |
| [`legacy-godot`](https://github.com/DaccordProject/daccord/tree/legacy-godot) | The retired Godot client this app replaced | GDScript | MIT |

`accordkit`, `livekit_client`, and `markdown_viewer` are vendored in-tree under `packages/` and maintained in this repository.

---

## 📄 License

Licensed under the **[GNU General Public License v3.0](LICENSE)** (GPLv3), inherited from Bonfire. AccordKit-Dart is MIT-licensed; GPLv3 may incorporate MIT-licensed code, so depending on `accordkit` is fine.
