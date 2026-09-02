import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Accept / decline / remove / block on the Friends tab used to fail in
/// complete silence: the row simply stayed as it was. The `_error` banner the
/// tab already rendered was never assigned to (#306). These pin it down.

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

class _FakeDmChannels extends DmChannelsController {
  @override
  List<AccordChannel>? build(String serverKey) => const [];
}

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// Serves one incoming friend request and answers every mutation with
/// [mutationStatus] / [mutationMessage].
ProviderContainer _container({
  required int mutationStatus,
  String? mutationMessage,
}) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((request) async {
      if (request.method == 'GET') {
        return _json({
          'data': [
            {
              'id': 'r1',
              'type': 3, // pending incoming
              'user': {'id': 'u2', 'username': 'bob'},
            },
          ],
        });
      }
      return _json({
        if (mutationMessage != null) 'message': mutationMessage,
      }, mutationStatus);
    }),
  );
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: 'u1',
            username: 'me',
          ),
        ),
      ),
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      dmChannelsControllerProvider('').overrideWith(_FakeDmChannels.new),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return container;
}

/// Opens the DM dialog and switches to the Friends tab.
Future<void> _openFriends(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAccordDirectMessages(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Friends'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a rejected accept reports the server\'s reason', (tester) async {
    final container = _container(
      mutationStatus: 403,
      mutationMessage: 'That user is not accepting friend requests',
    );
    await _openFriends(tester, container);
    expect(find.text('bob'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    expect(
      find.text('That user is not accepting friend requests'),
      findsOneWidget,
    );
  });

  testWidgets('a rejected decline falls back to our own wording', (
    tester,
  ) async {
    // A failure the server gave no words for.
    final container = _container(mutationStatus: 500, mutationMessage: '');
    await _openFriends(tester, container);

    await tester.tap(find.byTooltip('Decline'));
    await tester.pumpAndSettle();

    expect(find.text('Could not remove that relationship.'), findsOneWidget);
  });

  testWidgets('a successful action leaves no error behind', (tester) async {
    final container = _container(mutationStatus: 200);
    await _openFriends(tester, container);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not'), findsNothing);
  });
}
