import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _channelId = 'ch1';
const _serverKey = 'u-self@https://accord.example.test';

String _messagesJson(List<String> ids) => jsonEncode([
  for (final id in ids) {'id': id, 'channel_id': _channelId, 'content': id},
]);

/// A logged-in [ProviderContainer] whose [AccordClient] is backed by
/// [responder] instead of real HTTP, so the history load and the optimistic
/// mutations can be driven deterministically.
ProviderContainer makeContainer(
  Future<http.Response> Function(http.Request request) responder, {
  bool watchController = true,
}) {
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
  if (watchController) {
    final subscription = container.listen(
      accordMessagesControllerProvider(_serverKey, _channelId),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
  }
  return container;
}

AccordClient _client(ProviderContainer c) =>
    (c.read(accordAuthProvider) as AccordAuthLoggedIn).client;

AccordMessagesController _notifier(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider(_serverKey, _channelId).notifier);

List<AccordMessage>? _state(ProviderContainer c) =>
    c.read(accordMessagesControllerProvider(_serverKey, _channelId));

bool _failed(ProviderContainer c) =>
    c.read(messagesLoadFailedProvider(_serverKey, _channelId));

/// Polls [condition] until true so tests don't hard-code request latencies.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Condition not met in $timeout');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('AccordMessagesController._load failure flag', () {
    test('a failed history fetch is distinguishable from still loading', () async {
      final container = makeContainer(
        (_) async => http.Response('', 500),
      );

      // Both start out "null and not failed" — that is the loading state.
      expect(_state(container), isNull);
      await _waitUntil(() => _failed(container));

      // Still null, but now flagged: the pane renders an error, not a spinner.
      expect(_state(container), isNull);
    });

    test('a genuinely empty channel is not treated as a failure', () async {
      final container = makeContainer(
        (_) async => http.Response(_messagesJson(const []), 200),
      );

      await _waitUntil(() => _state(container) != null);

      expect(_state(container), isEmpty);
      expect(_failed(container), isFalse);
    });

    test('a successful reload clears a previously-set failure', () async {
      var failing = true;
      final container = makeContainer(
        (_) async => failing
            ? http.Response('', 503)
            : http.Response(_messagesJson(const ['m1']), 200),
      );
      await _waitUntil(() => _failed(container));

      failing = false;
      await _notifier(container).reload(_client(container));

      expect(_failed(container), isFalse);
      expect(_state(container)?.single.id, 'm1');
    });
  });

  group('optimistic actions report why they rolled back', () {
    test('pin returns the server error and reverts the flag', () async {
      final container = makeContainer((request) async {
        if (request.method == 'GET') {
          return http.Response(_messagesJson(const ['m1']), 200);
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'FORBIDDEN', 'message': 'Missing permissions'},
          }),
          403,
        );
      });
      await _waitUntil(() => _state(container) != null);

      final error = await _notifier(container).pin(_client(container), 'm1');

      expect(error, 'Missing permissions');
      expect(_state(container)!.single.pinned, isFalse);
    });

    test('unpin falls back to a plain message and restores the flag', () async {
      final container = makeContainer((request) async {
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode([
              {
                'id': 'm1',
                'channel_id': _channelId,
                'content': 'hi',
                'pinned': true,
              },
            ]),
            200,
          );
        }
        // A server that reports no explanation at all still has to produce
        // something the UI can show.
        return http.Response(
          jsonEncode({
            'error': {'code': 'SERVER_ERROR', 'message': ''},
          }),
          500,
        );
      });
      await _waitUntil(() => _state(container) != null);
      expect(_state(container)!.single.pinned, isTrue);

      final error = await _notifier(container).unpin(_client(container), 'm1');

      expect(error, 'Failed to unpin message.');
      expect(_state(container)!.single.pinned, isTrue);
    });

    test('a successful pin reports no error', () async {
      final container = makeContainer((request) async {
        if (request.method == 'GET') {
          return http.Response(_messagesJson(const ['m1']), 200);
        }
        return http.Response('', 204);
      });
      await _waitUntil(() => _state(container) != null);

      expect(await _notifier(container).pin(_client(container), 'm1'), isNull);
      expect(_state(container)!.single.pinned, isTrue);
    });

    test('toggleReaction returns the server error and removes the pill', () async {
      final container = makeContainer((request) async {
        if (request.method == 'GET') {
          return http.Response(_messagesJson(const ['m1']), 200);
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'FORBIDDEN', 'message': 'Reactions are disabled'},
          }),
          403,
        );
      });
      await _waitUntil(() => _state(container) != null);

      final error = await _notifier(
        container,
      ).toggleReaction(_client(container), 'm1', '🍔');

      expect(error, 'Reactions are disabled');
      expect(_state(container)!.single.reactions ?? const [], isEmpty);
    });

    test('a successful reaction toggle reports no error', () async {
      final container = makeContainer((request) async {
        if (request.method == 'GET') {
          return http.Response(_messagesJson(const ['m1']), 200);
        }
        return http.Response('', 204);
      });
      await _waitUntil(() => _state(container) != null);

      final error = await _notifier(
        container,
      ).toggleReaction(_client(container), 'm1', '🍔');

      expect(error, isNull);
      expect(_state(container)!.single.reactions!.single.includesMe, isTrue);
    });
  });
}
