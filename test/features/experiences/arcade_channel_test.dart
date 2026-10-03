import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/views/arcade_activity_badge.dart';
import 'package:bonfire/features/experiences/views/experience_idle_countdown.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  final AccordClient fixtureClient;
  final AccordSession account;
  _Auth(this.fixtureClient, this.account);
  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: fixtureClient, session: account);
  @override
  AccordClient? clientForKey(String key) =>
      key == account.key ? fixtureClient : null;
}

class _Connections extends ConnectionsController {
  final AccordSession account;
  _Connections(this.account);
  @override
  ConnectionsState build() => ConnectionsState(
    activeKey: account.key,
    connections: [
      AccordConnection(session: account, status: ConnectionStatus.ready),
    ],
  );
}

void main() {
  final account = AccordSession(
    server: AccordServer.fromBaseUrl('https://arcade.test'),
    token: 'test-only',
    tokenType: 'Bearer',
    userId: 'owner',
    username: 'owner',
  );
  Widget scope(AccordClient client, Widget child) => ProviderScope(
    overrides: [
      accordAuthProvider.overrideWith(() => _Auth(client, account)),
      connectionsControllerProvider.overrideWith(() => _Connections(account)),
    ],
    child: MaterialApp(
      theme: ThemeData(
        extensions: const [
          BonfireThemeExtension(
            foreground: Color(0xff2f3136),
            background: Color(0xff36393f),
            dirtyWhite: Colors.white70,
            gray: Colors.grey,
            darkGray: Color(0xff202225),
            primary: Colors.blue,
            red: Colors.red,
            green: Colors.green,
            yellow: Colors.yellow,
          ),
        ],
      ),
      home: Scaffold(body: child),
    ),
  );

  testWidgets('badge counts active games and lobbies, then updates to zero', (
    tester,
  ) async {
    var count = 3;
    final client = AccordClient(
      baseUrl: account.server.baseUrl,
      httpClient: MockClient((request) async {
        expect(request.url.path, endsWith('/arcade'));
        return http.Response(
          jsonEncode({
            'data': {'active_sessions': count},
          }),
          200,
        );
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      scope(
        client,
        ArcadeActivityBadge(serverKey: account.key, spaceId: 'space'),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(Badge), matching: find.text('3')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('3 active games and lobbies'), findsOneWidget);
    count = 0;
    await tester.pump(const Duration(seconds: 15));
    await tester.pumpAndSettle();
    expect(find.byType(Badge), findsNothing);
    expect(find.text('0'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'older server fallback counts lobbies and running games, excludes ended games',
    (tester) async {
      final client = AccordClient(
        baseUrl: account.server.baseUrl,
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/sessions')
                  ? [
                      {'state': 'lobby'},
                      {'state': 'running'},
                      {'state': 'ended'},
                    ]
                  : {'visible': true},
            }),
            200,
          ),
        ),
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(
        scope(
          client,
          ArcadeActivityBadge(serverKey: account.key, spaceId: 'space'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a late count cannot leak into the next space', (tester) async {
    final delayed = Completer<http.Response>();
    final client = AccordClient(
      baseUrl: account.server.baseUrl,
      httpClient: MockClient((request) async {
        if (request.url.path.contains('/old/')) return delayed.future;
        return http.Response(
          jsonEncode({
            'data': {'active_sessions': 1},
          }),
          200,
        );
      }),
    );
    addTearDown(client.dispose);
    await tester.pumpWidget(
      scope(
        client,
        ArcadeActivityBadge(serverKey: account.key, spaceId: 'old'),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      scope(
        client,
        ArcadeActivityBadge(serverKey: account.key, spaceId: 'new'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    delayed.complete(
      http.Response(
        jsonEncode({
          'data': {'active_sessions': 99},
        }),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('99'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'idle countdown follows the server deadline and clears for ended games',
    (tester) async {
      AccordExperienceSession snapshot(
        Duration remaining, {
        String state = 'lobby',
      }) => AccordExperienceSession.fromJson({
        'state': state,
        'idle_expires_at':
            DateTime.now().add(remaining).millisecondsSinceEpoch ~/ 1000,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ExperienceIdleCountdown(
            session: snapshot(const Duration(hours: 2)),
          ),
        ),
      );
      expect(find.textContaining('Removed in 1h'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: ExperienceIdleCountdown(
            session: snapshot(const Duration(days: 7)),
          ),
        ),
      );
      expect(find.textContaining('Removed in 6d'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: ExperienceIdleCountdown(
            session: snapshot(const Duration(seconds: -1)),
          ),
        ),
      );
      expect(find.text('Removing inactive game…'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: ExperienceIdleCountdown(
            session: snapshot(const Duration(days: 7), state: 'ended'),
          ),
        ),
      );
      expect(find.byType(Text), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'Arcade channel opens inside the message pane without fetching chat history',
    (tester) async {
      final paths = <String>[];
      final client = AccordClient(
        baseUrl: account.server.baseUrl,
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'data': request.url.path.endsWith('/sessions')
                  ? []
                  : {'enabled': true, 'visible': false, 'experiences': []},
            }),
            200,
          );
        }),
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(
        scope(
          client,
          MessagePane(
            channel: AccordChannel(
              id: 'arcade-space',
              type: 'arcade',
              spaceId: 'space',
              name: 'game-room',
            ),
            channelId: 'arcade-space',
            spaceId: 'space',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SpaceArcade), findsOneWidget);
      expect(find.text('game-room'), findsOneWidget);
      expect(find.byType(BackButton), findsNothing);
      expect(paths.any((p) => p.contains('/messages')), isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
