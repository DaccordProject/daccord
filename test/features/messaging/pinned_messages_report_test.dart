import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/messaging/controllers/hidden_messages.dart';
import 'package:bonfire/features/messaging/views/pinned_messages.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The pinned list is a message surface too (#290).
///
/// It shows other people's content, so it carries the same Report action as the
/// pane and drops what the user has already reported — otherwise a message
/// hidden from the pane came back the moment it was pinned.

const _channelId = 'c1';
const _selfId = 'u1';
const _themId = 'u2';

class _FakeHiddenMessages extends HiddenMessagesController {
  _FakeHiddenMessages(this.initial);

  final Set<String> initial;

  @override
  Set<String> build() => initial;
}

Map<String, String> _pin(String id, String content, String authorId) => {
  'id': id,
  'channel_id': _channelId,
  'author_id': authorId,
  'content': content,
  'timestamp': '2026-01-01T10:00:00Z',
};

class _Harness {
  _Harness({Set<String> hidden = const {}}) {
    final responder = MockClient((request) async {
      if (request.url.path.endsWith('/channels/$_channelId/pins')) {
        return http.Response(
          jsonEncode([
            _pin('m2', 'from them', _themId),
            _pin('m1', 'from me', _selfId),
          ]),
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
        hiddenMessagesControllerProvider.overrideWith(
          () => _FakeHiddenMessages(hidden),
        ),
      ],
    );
  }

  late final AccordClient client;
  late final ProviderContainer container;

  /// A DM channel's pins: no space, so nothing here can fall back to space
  /// moderation.
  Widget get app => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPinnedMessages(
              context,
              channelId: _channelId,
              canManage: false,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  void dispose() => client.dispose();
}

void main() {
  testWidgets('a pinned message from someone else can be reported', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('from them'), findsOneWidget);
    // One Report button: the user's own pinned message doesn't offer it.
    expect(find.byTooltip('Report'), findsOneWidget);

    await tester.tap(find.byTooltip('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Report message'), findsOneWidget);
  });

  testWidgets('a message already reported stays hidden when pinned', (
    tester,
  ) async {
    final harness = _Harness(hidden: {'m2'});
    addTearDown(harness.dispose);
    await tester.pumpWidget(harness.app);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('from me'), findsOneWidget);
    expect(find.text('from them'), findsNothing);
    expect(find.byTooltip('Report'), findsNothing);
  });
}
