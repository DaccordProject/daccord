import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/views/switcher.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/authentication/views/auth_form.dart';
import 'package:bonfire/features/admin/views/accord_admin_panel.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';

/// The root navigator, so deep-link handling (in `main.dart`) can show the
/// Add-a-Server dialog and route over whatever screen is current.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Sends the login-hosting locations straight home when a live session already
/// exists — e.g. tapping "back" out of `/admin` or `/settings` (whose router
/// parent is the login route) or deep-linking to `/login` while signed in.
/// Only a settled [AccordAuthLoggedIn] bounces: in-progress / MFA /
/// password-reset states still render the login screen's forms, and a login
/// that *completes* while the screen is showing navigates via the screen's own
/// `ref.listen` (a state change doesn't re-run router redirects).
///
/// Attached to the `/` route, so it also runs for every sub-route match; the
/// location guard keeps `/switcher`, `/spaces`, `/settings`, and `/admin`
/// reachable while logged in.
///
/// Guard on the full destination (`state.uri.path`), not `state.matchedLocation`:
/// this redirect lives on the `/` route, and for a parent-route redirect
/// go_router sets `matchedLocation` to that route's own matched segment (`/`),
/// not the full incoming location. Using `matchedLocation` here would treat
/// every sub-route (`/settings`, `/admin`, `/switcher`) as `/` and bounce it
/// home while logged in.
///
/// Public (not `_`-prefixed) and [visibleForTesting] so tests can exercise it
/// against a real [GoRouter] instance without depending on the app's actual
/// screen widgets.
@visibleForTesting
String? redirectLoggedInToHome(BuildContext context, GoRouterState state) {
  final location = state.uri.path;
  if (location != '/' && location != '/login' && location != '/register') {
    return null;
  }
  final auth = ProviderScope.containerOf(context).read(accordAuthProvider);
  return auth is AccordAuthLoggedIn ? '/spaces' : null;
}

final routerController = GoRouter(
  navigatorKey: rootNavigatorKey,
  routes: [
    ShellRoute(
        builder: (context, state, child) => Scaffold(
            body: child,
            backgroundColor: BonfireThemeExtension.of(context).background),
        routes: [
          GoRoute(
            path: '/',
            redirect: redirectLoggedInToHome,
            builder: (context, state) => const AccordLoginScreen(),
            routes: [
              GoRoute(
                path: 'login',
                builder: (context, state) =>
                    const AccordLoginScreen(startOnCredentials: true),
              ),
              GoRoute(
                path: 'switcher',
                builder: (context, state) => const AccountSwitcherScreen(),
              ),
              GoRoute(
                path: 'register',
                builder: (context, state) => const AccordLoginScreen(
                  initialMode: AuthMode.register,
                  startOnCredentials: true,
                ),
              ),
              GoRoute(
                path: 'spaces',
                builder: (context, state) => AccordHomeScreen(
                  initialSpaceId: state.uri.queryParameters['space'],
                ),
              ),
              GoRoute(
                path: 'settings',
                builder: (context, state) => const AccordSettingsScreen(),
              ),
              GoRoute(
                path: 'admin',
                builder: (context, state) => const AccordAdminPanel(),
              ),
            ],
          ),
        ]),
  ],
);
