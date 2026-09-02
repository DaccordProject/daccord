import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/views/connections_settings_page.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Hosts [ConnectionsScreen] against a client whose
/// `GET /users/@me/connections` answers [status] with [body].
Widget _host({
  required int status,
  String body = '{}',
  bool embedded = false,
}) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((request) async {
      expect(request.url.path, endsWith('/users/@me/connections'));
      return http.Response(
        body,
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  addTearDown(client.dispose);
  final session = AccordSession(
    server: server,
    token: 'test-token',
    userId: 'u-self',
    username: 'self',
  );
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(client: client, session: session),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: ConnectionsScreen(embedded: embedded)),
    ),
  );
}

const _errorText = 'Failed to load connections.';

void main() {
  group('ConnectionsScreen — server without a connections endpoint', () {
    // The live server 404s this route, which used to paint a permanent red
    // "Failed to load connections." across the first settings screen a user
    // (or an app reviewer) opens (#292).
    for (final status in const [404, 405, 501]) {
      testWidgets('$status renders no error in the embedded Account card', (
        tester,
      ) async {
        await tester.pumpWidget(_host(status: status, embedded: true));
        await tester.pumpAndSettle();

        expect(find.text(_errorText), findsNothing);
      });

      testWidgets('$status collapses the embedded card entirely', (
        tester,
      ) async {
        await tester.pumpWidget(_host(status: status, embedded: true));
        await tester.pumpAndSettle();

        // Not even the section heading survives: a card that can never hold
        // anything is itself a half-built feature.
        expect(find.text('CONNECTIONS'), findsNothing);
        expect(tester.getSize(find.byType(ConnectionsScreen)).height, 0);
      });

      testWidgets('$status states the capability on the standalone page', (
        tester,
      ) async {
        await tester.pumpWidget(_host(status: status));
        await tester.pumpAndSettle();

        expect(find.text(_errorText), findsNothing);
        expect(
          find.textContaining("doesn't support linked third-party accounts"),
          findsOneWidget,
        );
      });
    }
  });

  group('ConnectionsScreen — genuine failures still surface', () {
    for (final status in const [500, 502]) {
      testWidgets('$status still shows the error (embedded)', (tester) async {
        await tester.pumpWidget(_host(status: status, embedded: true));
        await tester.pumpAndSettle();

        expect(find.text(_errorText), findsOneWidget);
      });

      testWidgets('$status still shows the error (standalone)', (tester) async {
        await tester.pumpWidget(_host(status: status));
        await tester.pumpAndSettle();

        expect(find.text(_errorText), findsOneWidget);
      });
    }
  });

  group('ConnectionsScreen — supported server', () {
    testWidgets('lists the linked accounts it is given', (tester) async {
      await tester.pumpWidget(
        _host(
          status: 200,
          body: '{"data":[{"id":"1","type":"github","name":"octocat"}]}',
          embedded: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_errorText), findsNothing);
      expect(find.text('github'), findsOneWidget);
      expect(find.text('octocat'), findsOneWidget);
    });

    testWidgets('an empty list keeps the neutral empty state', (tester) async {
      await tester.pumpWidget(_host(status: 200, body: '{"data":[]}'));
      await tester.pumpAndSettle();

      expect(find.text(_errorText), findsNothing);
      expect(find.textContaining('No connections linked.'), findsOneWidget);
    });
  });
}
