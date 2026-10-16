import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/admin/views/admin_device_bans_tab.dart';
import 'package:bonfire/features/admin/views/admin_users_tab.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object? data, [int status = 200]) => http.Response(
  jsonEncode({'data': data}),
  status,
  headers: {'content-type': 'application/json'},
);

final _users = [
  {'id': 'u1', 'username': 'me', 'is_admin': true},
  {'id': 'u2', 'username': 'alice'},
  {'id': 'u3', 'username': 'carol', 'is_admin': true},
  {'id': 'u4', 'username': 'helper-bot', 'bot': true},
];

Map<String, dynamic> _ban(String id, {String? username, String? userId}) => {
  'id': id,
  'fingerprint': '0123456789abcdef' * 4,
  'user_id': userId,
  'username': username,
  'reason': 'spam waves',
  'banned_by': 'u1',
  'created_at': '2026-10-01T12:00:00Z',
};

/// An instance admin (`u1`) whose server answers the admin routes; every
/// request is recorded in [log] as `METHOD path body`.
ProviderContainer _container(List<String> log, {int banned = 2}) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1', '');
      log.add('${request.method} $path ${request.body}'.trim());
      return switch ((request.method, path)) {
        ('GET', '/admin/users') => _json(_users),
        ('POST', '/admin/users/u2/device-bans') => _json({
          'banned': banned,
          'bans': [
            for (var i = 0; i < banned; i++)
              _ban('b$i', username: 'alice', userId: 'u2'),
          ],
        }),
        ('PATCH', '/admin/users/u2') => _json({..._users[1], 'disabled': true}),
        ('GET', '/admin/device-bans') => _json([
          _ban('b2', username: 'spammer', userId: 'u9'),
          _ban('b1', userId: 'u8'),
          _ban('b0'),
        ]),
        ('DELETE', '/admin/device-bans/b2') => http.Response('', 204),
        _ => _json(null, 404),
      };
    }),
  );
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: 'u1',
            username: 'me',
            isAdmin: true,
          ),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(client.dispose);
  return container;
}

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  Widget tab,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(body: tab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the overflow menu on the row for [username].
Future<void> _openMenu(WidgetTester tester, String username) async {
  await tester.tap(
    find.descendant(
      of: find.widgetWithText(ListTile, username),
      matching: find.byIcon(Icons.more_vert),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ban devices is offered only for ordinary accounts', (
    tester,
  ) async {
    await _pump(tester, _container([]), const AdminUsersTab());

    for (final (username, offered) in [
      ('me', false),
      ('alice', true),
      ('carol', false),
      ('helper-bot', false),
    ]) {
      await _openMenu(tester, username);
      expect(
        find.text('Ban devices…'),
        offered ? findsOneWidget : findsNothing,
        reason: username,
      );
      await tester.tapAt(Offset.zero); // dismiss the menu
      await tester.pumpAndSettle();
    }
  });

  testWidgets('banning devices also disables the account by default', (
    tester,
  ) async {
    final log = <String>[];
    await _pump(tester, _container(log), const AdminUsersTab());

    await _openMenu(tester, 'alice');
    await tester.tap(find.text('Ban devices…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Bans every device this account has signed in'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, '  spam waves ');
    await tester.tap(find.widgetWithText(FilledButton, 'Ban devices'));
    await tester.pumpAndSettle();

    expect(log.skip(1), [
      'POST /admin/users/u2/device-bans {"reason":"spam waves"}',
      'PATCH /admin/users/u2 {"disabled":true}',
    ]);
    expect(find.text('Banned 2 devices'), findsOneWidget);
    expect(find.text('Disabled'), findsOneWidget);
  });

  testWidgets('without disabling, a ban with no recorded devices says why', (
    tester,
  ) async {
    final log = <String>[];
    await _pump(tester, _container(log, banned: 0), const AdminUsersTab());

    await _openMenu(tester, 'alice');
    await tester.tap(find.text('Ban devices…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Also disable this account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Ban devices'));
    await tester.pumpAndSettle();

    expect(log.skip(1), ['POST /admin/users/u2/device-bans {}']);
    expect(
      find.textContaining('No devices recorded for this account yet'),
      findsOneWidget,
    );
    expect(find.text('Disabled'), findsNothing);
  });

  testWidgets('cancelling the dialog sends nothing', (tester) async {
    final log = <String>[];
    await _pump(tester, _container(log), const AdminUsersTab());

    await _openMenu(tester, 'alice');
    await tester.tap(find.text('Ban devices…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(log, ['GET /admin/users']);
  });

  testWidgets('the Devices tab lists bans and unbans after confirming', (
    tester,
  ) async {
    final log = <String>[];
    await _pump(tester, _container(log), const AdminDeviceBansTab());

    expect(log, ['GET /admin/device-bans']);
    expect(find.text('spammer'), findsOneWidget);
    expect(find.text('u8'), findsOneWidget);
    expect(find.text('Unknown account'), findsOneWidget);
    expect(find.textContaining('Device 0123456789ab ·'), findsNWidgets(3));
    expect(find.textContaining('by u1'), findsNWidgets(3));
    expect(find.text('spam waves'), findsNWidgets(3));

    await tester.tap(find.text('Unban').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unban'));
    await tester.pumpAndSettle();

    expect(log.last, 'DELETE /admin/device-bans/b2');
    expect(find.text('spammer'), findsNothing);
    expect(find.text('u8'), findsOneWidget);
  });
}
