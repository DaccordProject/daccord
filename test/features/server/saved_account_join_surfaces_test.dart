import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/authentication/utils/terms_acceptance.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/server/views/add_server_dialog.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Store extends AccordSessionStore {
  _Store(this.accounts);
  final List<AccordSession> accounts;

  @override
  Future<List<AccordSession>> listAccounts() async => accounts;

  @override
  Future<AccordSession?> readRestorableActive() async => null;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// Keep socket creation outside widget tests; account lookup and REST joins
/// still exercise the production repository, including raw SDK responses.
class _Auth extends AccordAuth {
  _Auth(this.session, this.target, {bool saved = true})
    : super(sessionStore: _Store(saved ? [session] : []));

  final AccordSession session;
  final AccordClient target;
  Completer<void>? lookupGate;
  bool connected = false;
  int lookups = 0;
  String? activated;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  Future<AccordAuthState> restoreSession() async => state;

  @override
  String? keyForBaseUrl(String baseUrl) =>
      connected && AccordServer.sameEndpoint(baseUrl, session.server.baseUrl)
      ? session.key
      : null;

  @override
  AccordClient? clientForKey(String key) =>
      connected && key == session.key ? target : null;

  @override
  Future<String?> ensureConnectionForBaseUrl(String baseUrl) async {
    lookups++;
    await lookupGate?.future;
    if (connected) return keyForBaseUrl(baseUrl);
    final account = await accountForBaseUrl(baseUrl);
    if (account == null) return null;
    _connect();
    return account.key;
  }

  void _connect() {
    connected = true;
    ref
        .read(connectionsControllerProvider.notifier)
        .register(session, status: ConnectionStatus.connecting);
  }

  @override
  void setActiveServer(String key) {
    activated = key;
    ref.read(connectionsControllerProvider.notifier).setActive(key);
    state = AccordAuthLoggedIn(client: target, session: session);
  }

  @override
  Future<AccordAuthState> loginWithCredentials({
    required AccordServer server,
    required String username,
    required String password,
  }) async {
    _connect();
    setActiveServer(session.key);
    return state;
  }
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  late AccordSession session;
  late AccordClient client;
  late List<http.Request> requests;
  var joinStatus = 200;

  setUp(() {
    session = AccordSession(
      server: AccordServer.fromBaseUrl('https://chat.example'),
      token: 'saved-account-token',
      userId: 'saved-user',
      username: 'Saved User',
    );
    requests = [];
    joinStatus = 200;
    client = AccordClient(
      baseUrl: session.server.baseUrl,
      token: session.token,
      httpClient: MockClient((request) async {
        requests.add(request);
        final status = request.method == 'GET' ? 200 : joinStatus;
        final body = request.method == 'GET'
            ? {'id': 'joined-space', 'name': 'Joined'}
            : {'space_id': 'joined-space', 'code': 'abc123'};
        return http.Response(
          jsonEncode(
            status == 200 ? {'data': body} : {'message': 'Join denied'},
          ),
          status,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  tearDown(() async => client.dispose());

  ProviderContainer containerFor(_Auth auth) {
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(() => auth),
        settingsControllerProvider.overrideWith(_Settings.new),
        accordDiscoveryBrowseProvider.overrideWithValue(
          ({
            required String masterUrl,
            required String query,
            required String tag,
          }) async => RestResult.success(200, [
            {
              'space_id': 'joined-space',
              'server_url': 'https://CHAT.example:443/',
              'name': 'Target',
            },
          ]),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget host(ProviderContainer container, Widget body) =>
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildAppTheme(AppThemePreset.dark),
          home: Scaffold(body: body),
        ),
      );

  for (final url in [
    'https://CHAT.example:443/?invite=abc123',
    'daccord://invite/abc123@chat.example',
    'daccord://connect/chat.example?invite=abc123',
  ]) {
    testWidgets('saved account accepts $url without credentials', (
      tester,
    ) async {
      final auth = _Auth(session, client)..lookupGate = Completer<void>();
      final container = containerFor(auth);
      await tester.pumpWidget(
        host(
          container,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddServerDialog(context, initialUrl: url),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
      await tester.pump();
      expect(auth.connected, isFalse);
      expect(_field('Username or email'), findsNothing);
      expect(requests, isEmpty);

      auth.lookupGate!.complete();
      await tester.pumpAndSettle();
      expect(_field('Username or email'), findsNothing);
      expect(find.text('Add a Server'), findsNothing);
      expect(auth.activated, session.key);
      expect(requests.map((request) => request.url.path), [
        '/api/v1/invites/abc123/accept',
        '/api/v1/spaces/joined-space',
      ]);
      expect(requests.first.headers['Authorization'], contains(session.token));
      final pending = container.read(pendingDeepLinkProvider)!;
      expect(pending.spaceId, 'joined-space');
      expect(
        resolveDeepLinkDestination(
          pending,
          container.read(connectionsControllerProvider),
        ),
        isA<DeepLinkResolved>(),
        reason: 'A REST join opens even while its gateway is still connecting',
      );
    });
  }

  testWidgets(
    'login discovery reuses a saved account before invoking auth callback',
    (tester) async {
      final auth = _Auth(session, client)..lookupGate = Completer<void>();
      final container = containerFor(auth);
      var requestedCredentials = false;
      await tester.pumpWidget(
        host(
          container,
          AccordDiscoveryBody(
            onJoinRequiresAuth: (_, _) => requestedCredentials = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(requestedCredentials, isFalse);
      expect(auth.connected, isFalse);
      auth.lookupGate!.complete();
      await tester.pumpAndSettle();
      expect(requestedCredentials, isFalse);
      expect(auth.activated, session.key);
      expect(requests.first.url.path, '/api/v1/spaces/joined-space/join');
      expect(container.read(pendingDeepLinkProvider)?.spaceId, 'joined-space');
    },
  );

  for (final url in [
    'daccord://connect/chat.example/public-room?channel=general',
    'https://CHAT.example:443/#public-room',
  ]) {
    testWidgets('saved account joins the public space from $url', (
      tester,
    ) async {
      final auth = _Auth(session, client);
      final container = containerFor(auth);
      await tester.pumpWidget(
        host(
          container,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddServerDialog(
                context,
                initialUrl: url,
                autoConnect: true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Add a Server'), findsNothing);
      expect(requests.first.url.path, '/api/v1/spaces/public-room/join');
      expect(container.read(pendingDeepLinkProvider)?.spaceId, 'joined-space');
      expect(auth.activated, session.key);
    });
  }

  testWidgets('existing membership conflict fetches and opens its space', (
    tester,
  ) async {
    joinStatus = 409;
    final auth = _Auth(session, client);
    final container = containerFor(auth);
    await tester.pumpWidget(host(container, const AccordDiscoveryBody()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(requests.map((request) => request.method), ['POST', 'GET']);
    expect(auth.activated, session.key);
    expect(container.read(pendingDeepLinkProvider)?.spaceId, 'joined-space');
  });

  testWidgets('discovery requests credentials only after no saved match', (
    tester,
  ) async {
    final auth = _Auth(session, client, saved: false);
    final container = containerFor(auth);
    String? requestedSpace;
    await tester.pumpWidget(
      host(
        container,
        AccordDiscoveryBody(
          onJoinRequiresAuth: (_, space) => requestedSpace = space,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(auth.lookups, 1);
    expect(requestedSpace, 'joined-space');
    expect(requests, isEmpty);
  });

  testWidgets(
    'failed saved-account join stays in discovery and does not switch',
    (tester) async {
      joinStatus = 403;
      final auth = _Auth(session, client);
      final container = containerFor(auth);
      await tester.pumpWidget(host(container, const AccordDiscoveryBody()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(find.text('Join denied'), findsOneWidget);
      expect(auth.activated, isNull);
      expect(container.read(pendingDeepLinkProvider), isNull);
      expect(find.text('Add a Server'), findsNothing);
    },
  );

  testWidgets(
    'signed-out invite survives login and is accepted on its account',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'pending-invite-login',
      );
      Hive.init(directory.path);
      await Hive.openBox('accord-session');
      await Hive.openBox('auth');
      await recordAppTermsAcceptance();
      addTearDown(() async {
        await Hive.close();
        directory.deleteSync(recursive: true);
      });
      final auth = _Auth(session, client, saved: false);
      final container = containerFor(auth);
      final pending = ServerUri.parseDeepLink(
        'daccord://invite/abc123@chat.example',
      )!;
      container.read(pendingServerJoinProvider.notifier).hold(pending);
      await tester.pumpWidget(
        host(container, const AccordLoginScreen(startOnCredentials: true)),
      );
      await tester.pumpAndSettle();
      expect(container.read(pendingServerJoinProvider)?.invite, 'abc123');
      await tester.enterText(_field('Username or email'), 'saved-user');
      await tester.enterText(_field('Password'), 'password');
      await tester.ensureVisible(find.text('Log In'));
      await tester.tap(find.text('Log In'));
      await tester.pump();
      await tester.pump();
      expect(requests.first.url.path, '/api/v1/invites/abc123/accept');
      expect(container.read(pendingServerJoinProvider), isNull);
      expect(container.read(pendingDeepLinkProvider)?.spaceId, 'joined-space');
    },
  );
}
