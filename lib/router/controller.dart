import 'package:bonfire/features/admin/views/accord_admin_panel.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/authentication/views/switcher.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The root navigator, so deep-link handling (in `main.dart`) can show the
/// Add-a-Server dialog and route over whatever screen is current.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Sends the sign-in locations (`/`, `/login`, `/register`) home when a
/// settled [AccordAuthLoggedIn] session exists. In-progress / MFA /
/// password-reset states still render the forms, and a login that completes
/// on-screen navigates via the screen's own `ref.listen` (a state change
/// doesn't re-run router redirects).
///
/// Attached to each sign-in route rather than a shared parent. The location
/// guard matters if these routes ever gain children: a parent redirect sees
/// `state.matchedLocation` pinned to its own segment, so only `state.uri.path`
/// reflects the real destination.
@visibleForTesting
String? redirectLoggedInToHome(BuildContext context, GoRouterState state) {
  final location = state.uri.path;
  if (location != '/' && location != '/login' && location != '/register') {
    return null;
  }
  final auth = ProviderScope.containerOf(context).read(accordAuthProvider);
  return auth is AccordAuthLoggedIn ? '/spaces' : null;
}

/// Every signed-in destination is a *sibling* of the sign-in routes, never a
/// child: nesting under `/` puts the sign-in screen beneath the whole app, so
/// children inherit its logged-in redirect and Android back pops to sign-in.
///
/// Screens opened from home (Settings, Switch account, Server administration)
/// use `push`, so `/spaces` stays beneath them and back returns there. `go`
/// replaces the stack: signing in, signing out, and returning home.
///
/// Keep `_buildTestRouter` in `test/router/controller_test.dart` mirroring this
/// shape.
final routerController = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
      builder: (context, state, child) => Scaffold(
        body: child,
        backgroundColor: BonfireThemeExtension.of(context).background,
      ),
      routes: [
        GoRoute(
          path: '/',
          redirect: redirectLoggedInToHome,
          builder: (context, state) => const AccordLoginScreen(),
        ),
        GoRoute(
          path: '/login',
          redirect: redirectLoggedInToHome,
          builder: (context, state) =>
              const AccordLoginScreen(startOnCredentials: true),
        ),
        GoRoute(
          path: '/register',
          redirect: redirectLoggedInToHome,
          builder: (context, state) => const AccordLoginScreen(
            initialMode: AuthMode.register,
            startOnCredentials: true,
          ),
        ),
        GoRoute(
          path: '/switcher',
          builder: (context, state) => const AccountSwitcherScreen(),
        ),
        GoRoute(
          path: '/spaces',
          builder: (context, state) => AccordHomeScreen(
            initialSpaceId: state.uri.queryParameters['space'],
            initialChannelId: state.uri.queryParameters['channel'],
            initialChannelName: state.uri.queryParameters['channelName'],
            initialMessageId: state.uri.queryParameters['message'],
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const AccordSettingsScreen(),
        ),
        GoRoute(
          path: '/admin',
          builder: (context, state) => const AccordAdminPanel(),
        ),
      ],
    ),
  ],
);
