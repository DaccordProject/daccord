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

// Covers the two ways the "Settings does nothing" bug got in:
//
// * #179 — the logged-in redirect guarded on `state.matchedLocation`, which a
//   parent-route redirect sees pinned to its own matched segment (`/`) rather
//   than the full incoming location, so every signed-in sub-route was bounced
//   home. Only `state.uri.path` reflects where the user actually navigated.
// * The nesting that made that possible: `/spaces`, `/settings`, `/admin`, and
//   `/switcher` used to be children of `/`, which both subjected them to the
//   sign-in route's redirect and left the sign-in screen sitting in the
//   navigator stack underneath the whole app.
//
// Mirrors the app's real route shape (see lib/router/controller.dart) with
// placeholder screens instead of the real ones, so it doesn't drag in their
// provider dependencies.

GoRouter _buildTestRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/',
              redirect: redirectLoggedInToHome,
              builder: (context, state) => const Text('login'),
            ),
            GoRoute(
              path: '/login',
              redirect: redirectLoggedInToHome,
              builder: (context, state) => const Text('login'),
            ),
            GoRoute(
              path: '/register',
              redirect: redirectLoggedInToHome,
              builder: (context, state) => const Text('register'),
            ),
            GoRoute(
              path: '/switcher',
              builder: (context, state) => const Text('switcher'),
            ),
            GoRoute(
              path: '/spaces',
              builder: (context, state) => const Text('spaces'),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const Text('settings'),
            ),
            GoRoute(
              path: '/admin',
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

  group('signed-in destinations', () {
    testWidgets('home does not stack on the sign-in screen', (tester) async {
      final router = await _pumpAt(tester, '/spaces', auth: _loggedIn());

      expect(find.text('spaces'), findsOneWidget);
      // The sign-in screen used to sit underneath as `/spaces`' parent route,
      // which is what let a system back swipe pop the user down to it (#125).
      expect(find.text('login'), findsNothing);
      expect(router.canPop(), isFalse);
    });

    // The rail's gear button is the only `push` in the app: this is the exact
    // sequence the bug report describes ("clicking settings does nothing other
    // than seemingly refresh the app").
    testWidgets('pushing /settings from home opens it and pops back', (
      tester,
    ) async {
      final router = await _pumpAt(tester, '/spaces', auth: _loggedIn());

      router.push('/settings');
      await tester.pumpAndSettle();

      expect(find.text('settings'), findsOneWidget);
      expect(find.text('login'), findsNothing);
      expect(router.canPop(), isTrue);

      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('spaces'), findsOneWidget);
      expect(find.text('settings'), findsNothing);
    });

    for (final path in ['/switcher', '/admin']) {
      testWidgets('pushing $path from home pops back to it', (tester) async {
        final router = await _pumpAt(tester, '/spaces', auth: _loggedIn());

        router.push(path);
        await tester.pumpAndSettle();

        expect(find.text(path.substring(1)), findsOneWidget);

        router.pop();
        await tester.pumpAndSettle();

        expect(find.text('spaces'), findsOneWidget);
      });
    }
  });
}
