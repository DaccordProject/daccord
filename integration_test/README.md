# UI end-to-end tests

Layer 2 of #217: the real app shell on a real device against a real `accordserver`. `integration/` proves caches update; these prove the screen does (lists not rebuilding, routes not resolving, empty channels).

```bash
flutter test integration_test/messaging_ui_test.dart -d linux
xvfb-run -a flutter test integration_test/smoke_test.dart -d linux   # headless

for f in integration_test/*_test.dart; do flutter test "$f" -d linux; done
```

**One file per invocation.** Running the directory fails on the second app launch with *"Error waiting for a debug connection: The log reader stopped unexpectedly, or never started"*. CI loops. Plain `flutter test` does not pick these up.

`video_playback_test.dart` needs no Accord server, but needs Linux desktop build deps and `ffmpeg` with `libx264` on `PATH`. It generates an H.264 clip and exercises inline playback, seeking, disposal, and reopening. The NVIDIA hardware-decode crash path only reproduces on an NVIDIA desktop, not headless.

## How it works

Server fixture and account harness are shared with `integration/support/` (see `integration/README.md`: server resolution, skip behaviour, registration budget).

`harness.scopeFor(account, child: ...)` wraps a `ProviderScope` that reports the account as signed in, so tests pump the real `MainWindow` and navigate with `routerController.go(...)`. Hive points at a throwaway directory, never your profile.

## Things that will bite you

- **Pump order.** Attach the event handler to the tree's container *before* the gateway connects; the shell hydrates from READY, so a late handler renders empty. `pumpApp` cycles the connection for this reason.
- **`pumpAndSettle` doesn't wait for the network.** Use `pumpUntilFound`.
- **Message bodies aren't `Text`.** Use `find.text('...', findRichText: true)`.
- **Background work escaping the test body.** `harness.setupHive()` seeds settings to suppress the onboarding tour, release-notes dialog, error-reporting consent, notifications, and `autoUpdateCheck`. With the updater live, a download failure lands as an unhandled async error after the test finishes and is blamed on whichever test is running ("first test fails, later ones pass"). Suspect escaped background work before the widget under test.

## CI

Advisory `ui-e2e` job in `ci.yml`: Linux under `xvfb` against the `ghcr.io` server image.
