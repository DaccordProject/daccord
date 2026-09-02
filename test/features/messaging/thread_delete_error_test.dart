import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Deleting a forum post whose DELETE the server refuses used to do nothing at
/// all — the dialog stayed open, the post stayed put, and nothing said why
/// (#306).

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

final _root = AccordMessage(
  id: 'm1',
  channelId: 'c1',
  authorId: 'u1',
  content: 'the post body',
  title: 'A post',
);

/// Answers replies with an empty list and the post's DELETE with
/// [deleteStatus].
Widget _host({
  required int deleteStatus,
  required List<ThreadResult?> closes,
}) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
    httpClient: MockClient((request) async {
      if (request.method == 'DELETE') {
        return http.Response(
          jsonEncode({'message': 'post is locked'}),
          deleteStatus,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': <Object>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  addTearDown(client.dispose);

  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: 'u1',
            username: 'me',
          ),
        ),
      ),
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: AccordThreadPane(
          channelId: 'c1',
          spaceId: null,
          root: _root,
          canManageMessages: true,
          onClose: closes.add,
        ),
      ),
    ),
  );
}

/// Long-presses the root post, picks Delete, and confirms.
Future<void> _deleteRoot(WidgetTester tester) async {
  // The row is keyed by message id; its body is markdown, not a plain Text.
  await tester.longPress(find.byKey(const ValueKey('m1')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Delete'));
  await tester.pumpAndSettle();
  // The confirmation dialog's own Delete button.
  await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a refused post delete says why and keeps the thread open', (
    tester,
  ) async {
    final closes = <ThreadResult?>[];
    await tester.pumpWidget(_host(deleteStatus: 403, closes: closes));
    await tester.pumpAndSettle();

    await _deleteRoot(tester);

    expect(find.textContaining('Failed to delete post'), findsOneWidget);
    expect(closes, isEmpty);
  });

  testWidgets('an accepted delete closes the thread without complaint', (
    tester,
  ) async {
    final closes = <ThreadResult?>[];
    await tester.pumpWidget(_host(deleteStatus: 200, closes: closes));
    await tester.pumpAndSettle();

    await _deleteRoot(tester);

    expect(find.textContaining('Failed to delete post'), findsNothing);
    expect(closes.length, 1);
  });
}
