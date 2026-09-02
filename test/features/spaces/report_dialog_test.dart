import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/views/accord_reports.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The report dialog's two destinations (#290).
///
/// A report filed inside a space goes to that space's moderators. Everything
/// else — a direct message, a user reported from an account-level surface — has
/// no space to file against, so it goes to the account-level `/reports` route,
/// and on a server that doesn't serve one the dialog must still do what it
/// promises (block, hide) and must not claim a moderator will look at it.

const _selfId = 'u1';
const _themId = 'u2';

class _Harness {
  _Harness({this.directReportStatus = 200, this.failedBlocks = 0}) {
    final responder = MockClient((request) async {
      final path = request.url.path;
      requests.add('${request.method} $path');
      if (path.endsWith('/reports/categories')) {
        return _json({
          'data': [
            {'value': 'harassment', 'label': 'Harassment or bullying'},
            {'value': 'spam', 'label': 'Spam'},
          ],
        });
      }
      if (path.endsWith('/reports')) {
        final direct = !path.contains('/spaces/');
        if (direct && directReportStatus != 200) {
          return http.Response(
            jsonEncode({'message': 'not found'}),
            directReportStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        return _json({
          'data': {'id': 'r1', 'status': 'pending'},
        });
      }
      if (path.contains('/relationships/')) {
        blockAttempts++;
        if (blockAttempts <= failedBlocks) {
          return http.Response(
            jsonEncode({'message': 'relationship service unavailable'}),
            503,
            headers: {'content-type': 'application/json'},
          );
        }
        return _json({'data': {}});
      }
      return _json({'data': []});
    });
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: responder,
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: _selfId,
              username: 'self',
            ),
          ),
        ),
      ],
    );
  }

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  /// Status the account-level `POST /reports` answers with. 404 stands for a
  /// server that only implements space-scoped reports.
  final int directReportStatus;

  /// How many block attempts fail before one is allowed to succeed.
  final int failedBlocks;
  int blockAttempts = 0;
  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  Widget app({String? spaceId}) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showReportDialog(
              context,
              spaceId: spaceId,
              targetType: 'message',
              targetId: 'm1',
              channelId: 'c1',
              reportedUserId: _themId,
              reportedName: 'them',
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  void dispose() => container.dispose();
}

Future<void> _openAndSubmit(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Harassment or bullying').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Submit report'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a report inside a space goes to that space\'s moderators', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app(spaceId: 's1'));
    await _openAndSubmit(tester);

    expect(harness.requests, contains('POST /api/v1/spaces/s1/reports'));
    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.textContaining('Moderators will review it'), findsOneWidget);
    // Blocking is opt-in where moderators exist, so nothing was blocked.
    expect(
      harness.requests.any((r) => r.startsWith('PUT /api/v1/users')),
      isFalse,
    );
  });

  testWidgets('a report with no space is filed account-level', (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await _openAndSubmit(tester);

    expect(harness.requests, contains('POST /api/v1/reports'));
    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.textContaining('Moderators will review it'), findsOneWidget);
    // Outside a space the block is pre-checked, so it also ran.
    expect(
      harness.requests.any((r) => r.contains('/users/@me/relationships/u2')),
      isTrue,
    );
  });

  testWidgets('a server without account-level reports still blocks and hides', (
    tester,
  ) async {
    final harness = _Harness(directReportStatus: 404);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await _openAndSubmit(tester);

    expect(find.text('Report submitted'), findsNothing);
    expect(find.textContaining('Moderators will review it'), findsNothing);
    expect(find.textContaining('is now hidden for you'), findsOneWidget);
    expect(find.textContaining('account is blocked'), findsOneWidget);
    expect(
      harness.container.read(hiddenMessagesControllerProvider),
      contains('m1'),
    );
  });

  testWidgets('a failed block after a delivered report says only that', (
    tester,
  ) async {
    final harness = _Harness(failedBlocks: 99);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await _openAndSubmit(tester);

    expect(
      find.textContaining('Reported, but blocking the account failed'),
      findsOneWidget,
    );
    expect(find.text('Report submitted'), findsNothing);
  });

  testWidgets('a failed block with no report filed claims neither', (
    tester,
  ) async {
    // The account-level route is missing *and* the block failed: nothing
    // reached the server, and the copy must not pretend otherwise.
    final harness = _Harness(directReportStatus: 404, failedBlocks: 99);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await _openAndSubmit(tester);

    expect(find.textContaining('Nothing was sent'), findsOneWidget);
    expect(find.textContaining('Reported, but'), findsNothing);
    expect(find.textContaining('Moderators will review it'), findsNothing);
  });

  testWidgets('retrying after a failed block does not file a second report', (
    tester,
  ) async {
    final harness = _Harness(failedBlocks: 1);
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app());
    await _openAndSubmit(tester);

    expect(
      find.textContaining('Reported, but blocking the account failed'),
      findsOneWidget,
    );

    // The form is still live so the block can be retried — the report behind it
    // must not be sent again.
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    expect(harness.blockAttempts, 2);
    expect(
      harness.requests.where((r) => r == 'POST /api/v1/reports').length,
      1,
    );
    expect(find.text('Report submitted'), findsOneWidget);
    expect(find.textContaining('account is blocked'), findsOneWidget);
  });
}
