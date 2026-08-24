import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _spaceId = 'space1';
const _serverKey = 'u-self@https://accord.example.test';

/// A member payload with the user embedded, so `_resolveUsers` has nothing
/// left to backfill and the test doesn't need to also mock `/users/*`.
String _membersJson(List<String> userIds) => jsonEncode([
  for (final id in userIds)
    {
      'user_id': id,
      'user': {'id': id, 'username': id},
    },
]);

/// Builds a logged-in [ProviderContainer] whose [AccordClient] is backed by
/// [responder] instead of real HTTP, so `AccordMembersController._load`'s
/// retry/timeout/failure-flag behaviour can be driven deterministically.
ProviderContainer makeContainer(
  Future<http.Response> Function(http.Request request) responder,
) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient(responder),
  );
  final session = AccordSession(
    server: server,
    token: 'test-token',
    userId: 'u-self',
    username: 'self',
  );
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: session),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    accordMembersControllerProvider(_serverKey, _spaceId),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container;
}

Map<String, AccordMember>? _state(ProviderContainer c) =>
    c.read(accordMembersControllerProvider(_serverKey, _spaceId));

bool _failed(ProviderContainer c) =>
    c.read(membersLoadFailedProvider(_serverKey, _spaceId));

/// Polls [condition] until it's true, so tests don't hard-code the retry
/// loop's real (1s, 2s) backoff durations. Fails the test if [timeout] elapses
/// first.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('AccordMembersController._load', () {
    test('a genuinely empty roster is not treated as a failure', () async {
      final container = makeContainer(
        (_) async => http.Response(_membersJson(const []), 200),
      );

      await _waitUntil(() => _state(container) != null);

      expect(_state(container), isEmpty);
      expect(_failed(container), isFalse);
    });

    test(
      'retries a failing attempt and succeeds once the server recovers',
      () async {
        var attempts = 0;
        final container = makeContainer((_) async {
          attempts++;
          if (attempts == 1) return http.Response('', 500);
          return http.Response(_membersJson(const ['u1']), 200);
        });

        // First attempt fails immediately; the retry backs off ~1s before the
        // second attempt, which succeeds.
        await _waitUntil(() => _state(container) != null);

        expect(attempts, 2);
        expect(_state(container)?.keys, contains('u1'));
        expect(_failed(container), isFalse);
      },
    );

    test('sets the failed flag once every retry is exhausted', () async {
      var attempts = 0;
      final container = makeContainer((_) async {
        attempts++;
        return http.Response('', 500);
      });

      // 3 attempts, backing off 1s then 2s between them (~3s total).
      await _waitUntil(() => _failed(container));

      expect(attempts, 3);
      expect(_state(container), isNull);
    });

    test(
      'a fresh invalidate-triggered load clears the failed flag on success',
      () async {
        var attempts = 0;
        final container = makeContainer((_) async {
          attempts++;
          // Fail every attempt of the first load (3 tries), then succeed.
          if (attempts <= 3) return http.Response('', 500);
          return http.Response(_membersJson(const ['u1']), 200);
        });

        await _waitUntil(() => _failed(container));

        // Mirrors the roster's Retry button: clear the flag, then reload.
        container
            .read(membersLoadFailedProvider(_serverKey, _spaceId).notifier)
            .set(false);
        container.invalidate(
          accordMembersControllerProvider(_serverKey, _spaceId),
        );
        await _waitUntil(() => _state(container) != null);

        expect(_state(container)?.keys, contains('u1'));
        expect(_failed(container), isFalse);
      },
    );
  });
}
