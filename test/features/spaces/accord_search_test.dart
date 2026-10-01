import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/views/accord_search.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.initial);
  final AccordAuthLoggedIn initial;

  @override
  AccordAuthState build() => initial;
}

void main() {
  testWidgets(
    'selecting a search hit preserves its exact message destination',
    (tester) async {
      final session = AccordSession(
        server: AccordServer.fromBaseUrl('https://accord.test'),
        token: 'test',
        userId: 'operator',
        username: 'operator',
      );
      final client = AccordClient(
        baseUrl: session.server.baseUrl,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': request.url.path.contains('/messages/search')
                  ? [
                      {
                        'id': 'older-message',
                        'channel_id': 'channel',
                        'author_id': 'author',
                        'content': 'Found message',
                      },
                    ]
                  : [],
            }),
            200,
          ),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(
            () => _Auth(AccordAuthLoggedIn(client: client, session: session)),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);
      final connections = container.read(
        connectionsControllerProvider.notifier,
      );
      connections.register(session);
      connections.setActive(session.key);
      AccordSearchSelection? selected;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(AppThemePreset.dark),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showAccordSearch(
                      context,
                      spaceId: 'space',
                    );
                  },
                  child: const Text('Search'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Found');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Found message'));
      await tester.pumpAndSettle();
      expect(selected?.channelId, 'channel');
      expect(selected?.messageId, 'older-message');
    },
  );
}
