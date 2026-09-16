# Integration tests

Client ↔ real `accordserver` tests (layer 1 of #217). Not picked up by plain `flutter test` (that only walks `test/`).

```bash
flutter test integration/
flutter test integration/accordkit_protocol_test.dart
```

## Getting a server

`support/accord_test_server.dart` resolves one in this order (spawned servers get a fresh temp SQLite DB, CDN dir, and ephemeral port):

1. `ACCORD_TEST_SERVER_URL=http://host:port` — use a running server; nothing spawned.
2. `ACCORD_SERVER_BIN=/path/to/accordserver`.
3. `../accordserver/target/{release,debug}/accordserver` (sibling checkout).
4. `docker run $ACCORD_SERVER_IMAGE` (default: the reviewed digest in `support/accord_test_server.dart`).

If none resolve, suites **skip** with a message. `ACCORD_TEST_LOG=debug` surfaces server logs on a failed boot.

Servers run with `ACCORD_TEST_MODE=1`, which relaxes the LiveKit requirement (voice-state paths work without an SFU, using placeholder `LIVEKIT_*` values). It does **not** relax auth or rate limits.

`ACCORD_TEST_LIVEKIT=1` instead starts a managed LiveKit container (digest-pinned; override with `ACCORD_TEST_LIVEKIT_IMAGE`) and drops `ACCORD_TEST_MODE`. Needs Linux Docker host networking; intended for `multi_instance/livekit_voice_test.dart`.

## Layout

- `support/accord_test_server.dart` — boots/tears down the server.
- `support/harness.dart` — accounts, connected clients, Riverpod containers, `waitForEvent` / `waitForState`.
- `accordkit_protocol_test.dart` — protocol seam: accordkit request shapes, response parsing, gateway event names.
- `messaging_cache_test.dart` — controller seam: app caches react to live gateway events via `handleAccordEvents` → `accordMessagesControllerProvider` (stale-UI bugs live here).

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
  }, skip: harness.skipReason);
}
```

Gotchas:

- **Open gateways last.** The server snapshots a session's space memberships at IDENTIFY and never refreshes them (#218). Create accounts with `connect: false`, set up membership, then `connectGateway`.
- **Registration budget: 5 per IP per 15 minutes**, not bypassed by test mode. Create accounts in `setUpAll` and reuse them; split into another file (own server) if you need more. The harness throws an explanatory error instead of an opaque 429.
- Never assert immediately after a gateway-bound action — use `waitForEvent` (streams) or `waitForState` (caches); both time out rather than hang.

## CI

`ci.yml` job `protocol-integration` runs `accordkit_protocol_test.dart` as a **blocking** PR and release gate against an immutable `ghcr.io` digest. `integration` (full suite), `ui-e2e`, and `multi-instance` are advisory (`continue-on-error`) and fail if 0 tests ran.

Updating the fixture: review the candidate image, replace the digest in both `ci.yml` and `support/accord_test_server.dart`, then run on a machine where the fixture picks Docker (no explicit or sibling binary). Never use a mutable tag.

```bash
ACCORD_SERVER_IMAGE=ghcr.io/daccordproject/accordserver@sha256:<digest> \
  flutter test integration/accordkit_protocol_test.dart
```

Real-SFU voice: see `multi_instance/README.md`.
