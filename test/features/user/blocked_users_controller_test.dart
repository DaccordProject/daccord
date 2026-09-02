import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

AccordClient _client(
  Future<http.Response> Function(http.Request request) responder,
) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  return AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient(responder),
  );
}

ProviderContainer _container(AccordClient client) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: 'self',
            username: 'self',
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

http.Response _relationships(String blockedId) => http.Response(
  jsonEncode([
    {
      'id': 'r-$blockedId',
      'type': accordBlockedRelationship,
      'user': {'id': blockedId, 'username': blockedId},
    },
  ]),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'an earlier-started refresh landing last does not clobber a later one',
    () async {
      // The gateway handler fires a refresh() on READY and again on every
      // relationship event, with nothing serializing them — so two requests
      // can be in flight together. Without a generation check, whichever
      // response arrives last wins even if it was sent first, reverting the
      // set a later, already-applied refresh had just written (#290 follow-up).
      final gates = <Completer<void>>[];
      var dispatched = 0;
      final client = _client((request) async {
        final gate = Completer<void>();
        gates.add(gate);
        final myCall = ++dispatched;
        await gate.future;
        return myCall == 1 ? _relationships('stale') : _relationships('fresh');
      });
      addTearDown(client.dispose);
      final container = _container(client);
      final blocked = container.read(
        blockedUsersControllerProvider('').notifier,
      );

      final first = blocked.refresh(client); // starts first, resolves last
      final second = blocked.refresh(client); // starts second, resolves first
      await _waitUntil(() => gates.length == 2);

      // Resolve the later-started request first.
      gates[1].complete();
      await second;
      expect(
        container.read(blockedUsersControllerProvider('')),
        unorderedEquals(<String>{'fresh'}),
      );

      gates[0].complete();
      await first;
      // The stale response from the call that started first must not
      // overwrite what the later call already applied.
      expect(
        container.read(blockedUsersControllerProvider('')),
        unorderedEquals(<String>{'fresh'}),
      );
    },
  );

  test('a single refresh still applies the server list normally', () async {
    final client = _client((request) async => _relationships('them'));
    addTearDown(client.dispose);
    final container = _container(client);
    final blocked = container.read(
      blockedUsersControllerProvider('').notifier,
    );

    await blocked.refresh(client);

    expect(
      container.read(blockedUsersControllerProvider('')),
      unorderedEquals(<String>{'them'}),
    );
  });

  test('sync is a no-op when the resulting set is unchanged', () {
    final client = _client(
      (request) async => http.Response('[]', 200),
    );
    addTearDown(client.dispose);
    final container = _container(client);
    final blocked = container.read(
      blockedUsersControllerProvider('').notifier,
    );
    blocked.block('u1');
    final before = container.read(blockedUsersControllerProvider(''));

    blocked.sync([
      AccordRelationship(
        id: 'r1',
        type: accordBlockedRelationship,
        user: AccordUser(id: 'u1', username: 'u1'),
      ),
    ]);

    // Same set contents, so the state object itself must not be replaced —
    // a watcher relying on identity to skip an unrelated rebuild would
    // otherwise rebuild for nothing every time the relationship list is
    // re-fetched.
    expect(
      identical(container.read(blockedUsersControllerProvider('')), before),
      isTrue,
    );
  });
}
