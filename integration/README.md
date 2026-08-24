# Integration tests

End-to-end coverage of this client against a **real `accordserver`** — the seam
that unit and widget tests can't reach. See #217 for the wider plan.

These do not run as part of `flutter test`; that command only picks up `test/`.
Run them explicitly:

```bash
flutter test integration/                              # whole suite
flutter test integration/accordkit_protocol_test.dart  # one file
```

## Getting a server

The fixture (`support/accord_test_server.dart`) resolves one in this order, and
each spawned server gets a fresh temp SQLite DB, a fresh CDN dir, and an
ephemeral port:

| | How | When it's used |
|---|---|---|
| 1 | `ACCORD_TEST_SERVER_URL=http://host:port` | Point at an already-running server. Nothing is spawned or torn down. |
| 2 | `ACCORD_SERVER_BIN=/path/to/accordserver` | Spawn an explicit build. |
| 3 | `../accordserver/target/{release,debug}/accordserver` | Auto-detected sibling checkout — the usual local path. |
| 4 | `docker run $ACCORD_SERVER_IMAGE` (default is the reviewed digest in `support/accord_test_server.dart`) | CI, or any machine without a Rust toolchain. |

If none resolve, every suite **skips** with a message explaining what to set,
rather than failing. Set `ACCORD_TEST_LOG=debug` to surface server logs on a
failed boot.

Servers run with `ACCORD_TEST_MODE=1`, which relaxes the LiveKit requirement so
voice-state paths are reachable without a real SFU. It does **not** relax auth
or rate limits.

Set `ACCORD_TEST_LIVEKIT=1` to replace that bypass with a real, managed LiveKit
container. The fixture removes `ACCORD_TEST_MODE`, gives accordserver an
internal HTTP endpoint and clients an external WebSocket endpoint, and uses
randomized host-network signaling, RTC TCP, and RTC UDP ports. Its default
image is an immutable reviewed digest; `ACCORD_TEST_LIVEKIT_IMAGE` may override
it for explicit candidate testing. This mode requires Linux Docker host
networking and is intended for `multi_instance/livekit_voice_test.dart`, not
the cheap protocol/controller suite.

## Layout

- `support/accord_test_server.dart` — boots and tears down the server.
- `support/harness.dart` — accounts, connected clients, Riverpod containers,
  and the `waitForEvent` / `waitForState` helpers.
- `accordkit_protocol_test.dart` — **protocol seam.** Asserts accordkit's
  request shapes, response parsing, and gateway event names match what the
  server actually sends.
- `messaging_cache_test.dart` — **controller seam.** Asserts the app's own
  caches react to live gateway events, via the real `handleAccordEvents` →
  `accordMessagesControllerProvider` path. This is where the stale-UI class of
  bug lives.

## Writing a test

```dart
Future<void> main() async {
  final harness = await IntegrationHarness.resolve();

  group('my feature', () {
    late TestAccount alice;

    setUpAll(() async {
      await harness.setupHive();                            // only if using containerFor
      alice = await harness.newAccount('alice', connect: false);
      // …create spaces / join, then:
      await harness.connectGateway(alice);
    });
    tearDownAll(harness.dispose);

    test('…', () async { … });
  }, skip: harness.skipReason);   // skips cleanly when no server is available
}
```

Two rules that are easy to get wrong:

- **Open gateways last.** The server snapshots a session's space memberships at
  IDENTIFY and never refreshes them (#218), so a gateway opened before the joins
  receives nothing for those spaces. Create accounts with `connect: false`, set
  up membership, then `connectGateway`.
- **Budget your registrations.** The server allows 5 per IP per 15 minutes and
  `ACCORD_TEST_MODE` does not bypass it. Create accounts in `setUpAll`, reuse
  them across tests, and split into another file (which gets its own server) if
  you need more. The harness throws with an explanation rather than letting you
  hit an opaque 429.

Never assert on state immediately after an action that travels through the
gateway — use `waitForEvent` (streams) or `waitForState` (caches), both of which
fail with a timeout instead of hanging.

## CI

`ci.yml` runs `accordkit_protocol_test.dart` as a blocking merge and release
gate against an immutable `ghcr.io` image digest. The full integration,
desktop UI, and multi-instance suites remain separate advisory jobs while
their broader external-toolchain flakes are removed.

To update the fixture, review the candidate accordserver image, replace the
digest in both `ci.yml` and `support/accord_test_server.dart`, then run this on
a machine where the fixture selects Docker (without an explicit or sibling
server binary):

```bash
ACCORD_SERVER_IMAGE=ghcr.io/daccordproject/accordserver@sha256:<digest> \
  flutter test integration/accordkit_protocol_test.dart
```

Do not replace the digest with a mutable tag: releases reuse `ci.yml`, so this
protocol job is part of the release gate as well as the pull-request gate.

The real-SFU scenario is deliberately advisory and manual because native
WebRTC, UDP, xvfb, and host audio are materially less reliable than the REST /
gateway seam. Run **CI → Run workflow → Real LiveKit SFU** or locally:

```bash
flutter build linux --release
ACCORD_TEST_LIVEKIT=1 \
  xvfb-run -a flutter test multi_instance/livekit_voice_test.dart --reporter expanded
```

The Linux app must see usable input/output devices. CI starts a PulseAudio null
sink and uses its monitor as the default source so both clients publish real
audio tracks without depending on runner hardware.
