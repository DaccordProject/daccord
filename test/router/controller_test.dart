import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/router/controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

// Regression test for #179: a redirect attached to a parent route (here `/`)
// sees `state.matchedLocation` pinned to that route's own segment for every
// sub-route match, not the full incoming location — only `state.uri.path`
// reflects where the user actually navigated. Reproduces the app's real route
// nesting (see lib/router/controller.dart) with placeholder screens instead of
// the real ones, so it doesn't drag in their provider dependencies.

GoRouter _buildTestRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          redirect: redirectLoggedInToHome,
          builder: (context, state) => const Text('login'),
          routes: [
            GoRoute(
              path: 'login',
              builder: (context, state) => const Text('login'),
            ),
            GoRoute(
              path: 'switcher',
              builder: (context, state) => const Text('switcher'),
            ),
            GoRoute(
              path: 'register',
              builder: (context, state) => const Text('register'),
            ),
            GoRoute(
              path: 'spaces',
              builder: (context, state) => const Text('spaces'),
            ),
            GoRoute(
              path: 'settings',
              builder: (context, state) => const Text('settings'),
            ),
            GoRoute(
              path: 'admin',
              builder: (context, state) => const Text('admin'),
            ),
          ],
        ),
      ],
    );

AccordAuthState _loggedIn() {
  final server = AccordServer.fromBaseUrl('https://example.test');
  final session = AccordSession(
    server: server,
    token: 't',
    userId: 'u1',
    username: 'tester',
  );
  return AccordAuthLoggedIn(client: AccordClient(), session: session);
}

Future<GoRouter> _pumpAt(
  WidgetTester tester,
  String location, {
  required AccordAuthState auth,
}) async {
  final router = _buildTestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [accordAuthProvider.overrideWithValue(auth)],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  router.go(location);
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('redirectLoggedInToHome', () {
    for (final path in ['/settings', '/admin', '/switcher']) {
      testWidgets('does not bounce $path home while logged in', (tester) async {
        await _pumpAt(tester, path, auth: _loggedIn());

        expect(find.text(path.substring(1)), findsOneWidget);
        expect(find.text('spaces'), findsNothing);
      });
    }

    for (final path in ['/', '/login', '/register']) {
      testWidgets('redirects $path to /spaces while logged in', (tester) async {
        await _pumpAt(tester, path, auth: _loggedIn());

        expect(find.text('spaces'), findsOneWidget);
      });
    }

    testWidgets('does not redirect / while logged out', (tester) async {
      await _pumpAt(tester, '/', auth: const AccordAuthLoggedOut());

      expect(find.text('login'), findsOneWidget);
      expect(find.text('spaces'), findsNothing);
    });
  });
}
