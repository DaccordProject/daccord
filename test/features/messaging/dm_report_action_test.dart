import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Reporting outside a space (#290).
///
/// A direct-message pane has no space, and the Report action used to be gated
/// on one — so the reviewer looking for a way to flag content in a DM found
/// none. These tests hold the action in place there, and hold the flip side:
/// once reported, the message is gone from the reporter's own view.

const _channelId = 'c1';
const _selfId = 'u1';
const _themId = 'u2';

class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

class _FakeHiddenMessages extends HiddenMessagesController {
  _FakeHiddenMessages(this.initial);

  final Set<String> initial;

  @override
  Set<String> build() => initial;
}

class _FakeBlockedUsers extends BlockedUsersController {
  _FakeBlockedUsers(this.initial);

  final Set<String> initial;

  @override
  Set<String> build(String serverKey) => initial;
}

Map<String, String> _msgJson(String id, String content, String authorId) => {
  'id': id,
  'channel_id': _channelId,
  'author_id': authorId,
  'content': content,
  'timestamp': '2026-01-01T10:00:00Z',
};

class _Harness {
  _Harness({Set<String> hidden = const {}, Set<String> blocked = const {}}) {
    final responder = MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.method == 'GET' &&
          request.url.path.endsWith('/channels/$_channelId/messages')) {
        return http.Response(
          jsonEncode([
            _msgJson('m2', 'from them', _themId),
            _msgJson('m1', 'from me', _selfId),
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/reports/categories')) {
        return http.Response(
          jsonEncode({
            'data': [
              {'value': 'harassment', 'label': 'Harassment or bullying'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '[]',
        200,
        headers: {'content-type': 'application/json'},
      );
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
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        // Hive isn't open in a widget test; seed the set directly.
        hiddenMessagesControllerProvider.overrideWith(
          () => _FakeHiddenMessages(hidden),
        ),
        blockedUsersControllerProvider(
          '',
        ).overrideWith(() => _FakeBlockedUsers(blocked)),
      ],
    );
  }

  final List<String> requests = [];
  late final AccordClient client;
  late final ProviderContainer container;

  /// A DM pane: no space, so nothing here can fall back to space moderation.
  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: const Scaffold(
        body: MessagePane(channel: null, channelId: _channelId, spaceId: null),
      ),
    ),
  );

  void dispose() => client.dispose();
}

Finder _body(String text) => find.text(text, findRichText: true);

Future<void> _tick(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('a direct message from someone else can be reported', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    expect(_body('from them'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('m2')),
        matching: find.byTooltip('Message actions'),
      ),
    );
    await _tick(tester);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Report'), findsOneWidget);

    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Report'));
    await _tick(tester);

    expect(find.text('Report message'), findsOneWidget);
    // No space means no moderators to promise, and blocking is pre-selected.
    expect(find.textContaining('go to the server operator'), findsOneWidget);
    final block = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(block.value, isTrue);
  });

  testWidgets('the user\'s own message offers no report action', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('m1')),
        matching: find.byTooltip('Message actions'),
      ),
    );
    await _tick(tester);
    expect(find.widgetWithText(PopupMenuItem<String>, 'Report'), findsNothing);
  });

  testWidgets('a reported message is gone from the reporter\'s view', (
    tester,
  ) async {
    final harness = _Harness(hidden: {'m2'});
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    expect(_body('from me'), findsOneWidget);
    expect(_body('from them'), findsNothing);
  });

  testWidgets('a blocked account\'s messages are hidden, as the block claims', (
    tester,
  ) async {
    final harness = _Harness(blocked: {_themId});
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await _tick(tester);

    expect(_body('from me'), findsOneWidget);
    expect(_body('from them'), findsNothing);
  });
}
