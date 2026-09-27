import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/spaces/views/accord_discovery.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/shared/components/async_state_views.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.initial);
  final AccordAuthLoggedIn initial;

  @override
  AccordAuthState build() => initial;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings(autoUpdateCheck: false);
}

class _Tabs extends OpenTabsController {
  @override
  OpenTabsState build() => const OpenTabsState();
}

class _Updates extends UpdateController {
  @override
  Future<void> maybeCheckOnStartup() async {}
}

void main() {
  late ProviderContainer container;
  late AccordClient client;
  late AccordSession session;
  late GoRouter router;

  Future<void> mount(
    WidgetTester tester, {
    bool isAdmin = false,
    bool spacesReady = true,
    ConnectionStatus status = ConnectionStatus.ready,
    bool failed = false,
  }) async {
    session = AccordSession(
      server: AccordServer.fromBaseUrl('https://accord.example.test'),
      token: 'test-token',
      userId: 'operator',
      username: 'operator',
      isAdmin: isAdmin,
    );
    client = AccordClient(
      baseUrl: session.server.baseUrl,
      httpClient: MockClient((_) async => http.Response('{"data":[]}', 200)),
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(
          () => _Auth(AccordAuthLoggedIn(client: client, session: session)),
        ),
        settingsControllerProvider.overrideWith(_Settings.new),
        openTabsControllerProvider.overrideWith(_Tabs.new),
        updateControllerProvider.overrideWith(_Updates.new),
        accordDiscoveryBrowseProvider.overrideWithValue(
          ({required masterUrl, required query, required tag}) async =>
              RestResult.success(200, []),
        ),
      ],
    );
    final connections = container.read(connectionsControllerProvider.notifier);
    connections.register(session, status: status);
    connections.setActive(session.key);
    connections.setSpaces(session.key, [], authoritative: spacesReady);
    container.read(spacesControllerProvider.notifier).setSpaces([]);
    container.read(spacesLoadFailedProvider(session.key).notifier).set(failed);
    router = GoRouter(
      initialLocation: '/spaces',
      routes: [
        GoRoute(
          path: '/spaces',
          builder: (_, _) => const Scaffold(body: AccordHomeScreen()),
        ),
        GoRoute(
          path: '/admin',
          builder: (_, _) => const Scaffold(body: Text('Admin destination')),
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      container.dispose();
      await client.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildAppTheme(AppThemePreset.dark),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('bootstrap admin can open administration with no memberships', (
    tester,
  ) async {
    await mount(tester, isAdmin: true);
    expect(find.text('No spaces yet'), findsOneWidget);
    expect(find.byType(LoadingView), findsNothing);
    await tester.tap(find.text('Server administration'));
    await tester.pumpAndSettle();
    expect(find.text('Admin destination'), findsOneWidget);
  });

  testWidgets(
    'ordinary account gets invite and discovery actions without administration',
    (tester) async {
      await mount(tester);
      expect(find.text('No spaces yet'), findsOneWidget);
      expect(find.text('Server administration'), findsNothing);
      await tester.tap(find.text('Join with invite'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(TextButton, 'Explore public spaces'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Discover Servers'), findsOneWidget);
    },
  );

  testWidgets(
    'empty cache keeps loading until READY and authoritative spaces',
    (tester) async {
      await mount(
        tester,
        spacesReady: false,
        status: ConnectionStatus.connecting,
      );
      expect(find.text('No spaces yet'), findsNothing);
      expect(find.byType(LoadingView), findsOneWidget);
      final connections = container.read(
        connectionsControllerProvider.notifier,
      );
      connections.setStatus(session.key, ConnectionStatus.ready);
      await tester.pump();
      expect(find.text('No spaces yet'), findsNothing);
      expect(find.byType(LoadingView), findsOneWidget);
      connections.setSpaces(session.key, [], authoritative: true);
      await tester.pump();
      expect(find.text('No spaces yet'), findsOneWidget);
      expect(find.byType(LoadingView), findsNothing);
    },
  );

  testWidgets('space fetch errors keep the actionable retry state', (
    tester,
  ) async {
    await mount(tester, failed: true);
    expect(find.text("Couldn't load your spaces"), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No spaces yet'), findsNothing);
  });

  testWidgets('an unreachable gateway is not mistaken for empty membership', (
    tester,
  ) async {
    await mount(tester, status: ConnectionStatus.reconnecting);
    expect(find.text('Server unreachable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('No spaces yet'), findsNothing);
  });

  testWidgets(
    'joining a space clears the empty state and leaving the last restores it',
    (tester) async {
      await mount(tester);
      final spaces = container.read(spacesControllerProvider.notifier);
      final connections = container.read(
        connectionsControllerProvider.notifier,
      );
      final space = AccordSpace(id: 'general', name: 'General');
      connections.upsertSpace(session.key, space);
      spaces.upsertSpace(space);
      await tester.pumpAndSettle();
      expect(find.text('No spaces yet'), findsNothing);
      expect(find.text('General'), findsWidgets);
      connections.removeSpace(session.key, space.id);
      spaces.removeSpace(space.id);
      await tester.pumpAndSettle();
      expect(find.text('No spaces yet'), findsOneWidget);
      expect(find.byType(LoadingView), findsNothing);
    },
  );
}
