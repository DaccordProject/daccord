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

/// Sends the sign-in locations (`/`, `/login`, `/register`) straight home when
/// a live session already exists — e.g. deep-linking to `/login` while signed
/// in. Only a settled [AccordAuthLoggedIn] bounces: in-progress / MFA /
/// password-reset states still render the login screen's forms, and a login
/// that *completes* while the screen is showing navigates via the screen's own
/// `ref.listen` (a state change doesn't re-run router redirects).
///
/// Attached to each sign-in route individually rather than to a shared parent.
/// The location guard is belt-and-braces: should these routes ever gain
/// children again, a parent-route redirect sees `state.matchedLocation` pinned
/// to its own matched segment, so only `state.uri.path` reflects where the user
/// actually navigated (#179 — every signed-in sub-route got bounced home).
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

/// Every signed-in destination is a *sibling* of the sign-in routes, never a
/// child of them. Nesting them under `/` used to put the sign-in screen in the
/// navigator stack underneath the whole app, which is what made `/settings`,
/// `/admin`, and `/switcher` inherit `/`'s logged-in redirect (#179: Settings
/// twitched open then closed) and what made Android's back swipe on the home
/// screen pop down to sign-in (#125).
///
/// Screens opened *from* the home screen (Settings, Switch account, Server
/// administration) are reached with `push`, so `/spaces` stays beneath them and
/// their back affordance — system back, or the app bar's arrow via
/// `context.canPop()` — returns there. `go` is for replacing the stack
/// entirely: signing in, signing out, and returning home.
///
/// Keep `_buildTestRouter` in `test/router/controller_test.dart` mirroring this
/// shape; it exercises the redirect and the push/pop stack against placeholder
/// screens.
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
