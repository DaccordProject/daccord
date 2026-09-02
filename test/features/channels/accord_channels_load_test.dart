import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _spaceId = 'space1';
const _serverKey = 'u-self@https://accord.example.test';

/// A logged-in [ProviderContainer] whose channel fetches hit [responder]
/// instead of the network.
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
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: 'u-self',
            username: 'self',
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  final subscription = container.listen(
    accordChannelsControllerProvider(_serverKey, _spaceId),
    (_, _) {},
    fireImmediately: true,
  );
  addTearDown(subscription.close);
  return container;
}

List<AccordChannel>? _state(ProviderContainer c) =>
    c.read(accordChannelsControllerProvider(_serverKey, _spaceId));

bool _failed(ProviderContainer c) =>
    c.read(channelsLoadFailedProvider(_serverKey, _spaceId));

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

void main() {
  group('AccordChannelsController._load', () {
    test('flags a failed fetch so the pane can stop spinning', () async {
      final container = makeContainer((_) async => http.Response('', 500));

      expect(_state(container), isNull);
      await _waitUntil(() => _failed(container));
      expect(_state(container), isNull);
    });

    test('a space with no channels is not treated as a failure', () async {
      final container = makeContainer(
        (_) async => http.Response(jsonEncode(const []), 200),
      );

      await _waitUntil(() => _state(container) != null);
      expect(_state(container), isEmpty);
      expect(_failed(container), isFalse);
    });

    test('a successful retry clears the flag', () async {
      var failing = true;
      final container = makeContainer(
        (_) async => failing
            ? http.Response('', 500)
            : http.Response(
                jsonEncode([
                  {'id': 'c1', 'space_id': _spaceId, 'name': 'general'},
                ]),
                200,
              ),
      );
      await _waitUntil(() => _failed(container));

      // What the pane's Retry button does: clear, then re-run the load.
      failing = false;
      container
          .read(channelsLoadFailedProvider(_serverKey, _spaceId).notifier)
          .set(false);
      container.invalidate(
        accordChannelsControllerProvider(_serverKey, _spaceId),
      );

      await _waitUntil(() => _state(container) != null);
      expect(_failed(container), isFalse);
      expect(_state(container)!.single.id, 'c1');
    });
  });
}
