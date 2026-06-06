import 'package:bonfire/features/authentication/views/switcher.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:bonfire/features/authentication/views/accord_login.dart';
import 'package:bonfire/features/admin/views/accord_admin_panel.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';

/// The root navigator, so deep-link handling (in `main.dart`) can show the
/// Add-a-Server dialog and route over whatever screen is current.
final rootNavigatorKey = GlobalKey<NavigatorState>();

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
            builder: (context, state) => const AccordLoginScreen(),
            routes: [
              GoRoute(
                path: 'login',
                builder: (context, state) => const AccordLoginScreen(),
              ),
              GoRoute(
                path: 'switcher',
                builder: (context, state) => const AccountSwitcherScreen(),
              ),
              GoRoute(
                path: 'register',
                builder: (context, state) => const AccordLoginScreen(),
              ),
              GoRoute(
                path: 'spaces',
                builder: (context, state) => const AccordHomeScreen(),
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
