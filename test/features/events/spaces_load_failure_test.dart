import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _serverKey = 'u-self@https://accord.example.test';

AccordSession _session(AccordServer server) => AccordSession(
  server: server,
  token: 'test-token',
  userId: 'u-self',
  username: 'self',
);

/// A logged-in container plus its client, with the connection registered and
/// active so the space load writes to the shared rail cache.
(ProviderContainer, AccordClient) makeContainer(
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
        AccordAuthLoggedIn(client: client, session: _session(server)),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  container
      .read(connectionsControllerProvider.notifier)
      .register(_session(server));
  container.read(connectionsControllerProvider.notifier).setActive(_serverKey);
  return (container, client);
}

bool _failed(ProviderContainer c) =>
    c.read(spacesLoadFailedProvider(_serverKey));

void main() {
  // `_loadSpaces` also writes SpaceCache, whose Hive box isn't open here; that
  // write logs and moves on, so it doesn't affect what's asserted below.
  group('space list load failure', () {
    test('a failed fetch is flagged so panes can offer a retry', () async {
      final (container, client) = makeContainer(
        (_) async => http.Response('', 500),
      );

      expect(_failed(container), isFalse);
      await container.read(retryLoadSpacesProvider)(client, _serverKey);

      expect(_failed(container), isTrue);
      expect(container.read(spacesControllerProvider), isNull);
    });

    test('a successful retry clears the flag and seeds the rail', () async {
      var failing = true;
      final (container, client) = makeContainer(
        (request) async => failing
            ? http.Response('', 500)
            : http.Response(
                jsonEncode(
                  request.url.path.endsWith('/spaces')
                      ? [
                          {'id': 's1', 'name': 'Space One'},
                        ]
                      : const [],
                ),
                200,
              ),
      );
      await container.read(retryLoadSpacesProvider)(client, _serverKey);
      expect(_failed(container), isTrue);

      failing = false;
      await container.read(retryLoadSpacesProvider)(client, _serverKey);

      expect(_failed(container), isFalse);
      expect(container.read(spacesControllerProvider)?.single.id, 's1');
    });
  });
}
