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
| 4 | `docker run $ACCORD_SERVER_IMAGE` (default `ghcr.io/daccordproject/accordserver:latest`) | CI, or any machine without a Rust toolchain. |

If none resolve, every suite **skips** with a message explaining what to set,
rather than failing. Set `ACCORD_TEST_LOG=debug` to surface server logs on a
failed boot.

Servers run with `ACCORD_TEST_MODE=1`, which relaxes the LiveKit requirement so
voice-state paths are reachable without a real SFU. It does **not** relax auth
or rate limits.

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

`ci.yml` runs this suite on Linux via the `ghcr.io` server image. It is a
separate job from `test` so a server-side outage can't redden the unit suite.
