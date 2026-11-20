import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Ordinary accounts could only create spaces from the instance-admin panel,
/// although the server lets any signed-in user create and own one. The
/// add-server dialog's Create tab is the everyday entry point.

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// The dialog reads the auth notifier, so a value override is not enough.
class _SignedIn extends AccordAuth {
  _SignedIn(this._state);

  final AccordAuthState _state;

  @override
  AccordAuthState build() => _state;
}

final _server = AccordServer.fromBaseUrl('https://accord.example.test');

AccordSession _session({bool isGuest = false}) => AccordSession(
  server: _server,
  token: 'test-token',
  userId: 'u1',
  username: 'me',
  isGuest: isGuest,
);

void main() {
  late List<http.Request> requests;

  ({ProviderContainer container, GoRouter router}) setUpApp({
    bool isGuest = false,
    int status = 200,
  }) {
    requests = [];
    final client = AccordClient(
      token: 'test-token',
      baseUrl: _server.baseUrl,
      gatewayUrl: _server.gatewayUrl,
      cdnUrl: _server.cdnUrl,
      httpClient: MockClient((request) async {
        requests.add(request);
        if (status != 200) {
          return _json({
            'error': {'code': 'forbidden', 'message': 'Not allowed here'},
          }, status);
        }
        return _json({
          'data': {
            'id': 's1',
            'name': 'Our place',
            'owner_id': 'u1',
            'roles': <Object>[],
          },
        });
      }),
    );
    final session = _session(isGuest: isGuest);
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(
          () => _SignedIn(AccordAuthLoggedIn(client: client, session: session)),
        ),
      ],
    );
    container.read(connectionsControllerProvider.notifier)
      ..register(session)
      ..setActive(session.key);
    container.read(spacesControllerProvider.notifier).setSpaces(const []);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => showAddServerDialog(context, createSpace: true),
              child: const Text('open'),
            ),
          ),
        ),
        GoRoute(
          path: '/spaces',
          builder: (_, state) =>
              Text('space page ${state.uri.queryParameters['space']}'),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.dispose);
    addTearDown(router.dispose);
    return (container: container, router: router);
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    ProviderContainer container,
    GoRouter router,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildAppTheme(AppThemePreset.dark),
          routerConfig: router,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('creates an owned space, shows it and opens it', (tester) async {
    final (:container, :router) = setUpApp();
    await pumpDialog(tester, container, router);

    expect(find.text('Create your own space'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Space name'),
      '  Our place  ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final create = requests.single;
    expect(create.method, 'POST');
    expect(create.url.path, endsWith('/spaces'));
    expect(jsonDecode(create.body), {'name': 'Our place'});
    expect(
      container.read(spacesControllerProvider)?.map((s) => s.id),
      contains('s1'),
    );
    expect(
      container
          .read(connectionsControllerProvider.notifier)
          .spacesFor(_session().key)
          .map((s) => s.id),
      contains('s1'),
    );
    expect(find.text('space page s1'), findsOneWidget);
  });

  testWidgets('a blank name is rejected before any request', (tester) async {
    final (:container, :router) = setUpApp();
    await pumpDialog(tester, container, router);

    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(requests, isEmpty);
    expect(find.text('Enter a space name'), findsOneWidget);
  });

  testWidgets('server refusals stay in the dialog', (tester) async {
    final (:container, :router) = setUpApp(status: 403);
    await pumpDialog(tester, container, router);

    await tester.enterText(
      find.widgetWithText(TextField, 'Space name'),
      'Our place',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('Not allowed here'), findsOneWidget);
    expect(find.text('Create your own space'), findsOneWidget);
  });

  testWidgets('guests cannot create spaces', (tester) async {
    final (:container, :router) = setUpApp(isGuest: true);
    await pumpDialog(tester, container, router);

    expect(find.textContaining('Guests can’t create spaces'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create'),
    );
    expect(button.onPressed, isNull);
  });
}
