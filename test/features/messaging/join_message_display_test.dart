import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/views/box/accord_message_content.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/messaging/views/pinned_messages.dart';
import 'package:bonfire/features/messaging/views/thread_view.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/spaces/views/accord_search.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/controllers/accord_users.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _legacyText = 'old@example.com joined the server.';
const _channelId = 'channel';
const _authorId = 'author';

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

class _Harness {
  _Harness({bool missingUser = false, String content = _legacyText}) {
    join = AccordMessage(
      id: 'join',
      channelId: _channelId,
      authorId: _authorId,
      type: 'member_join',
      content: content,
      timestamp: '2026-10-01T10:00:00Z',
    );
    final server = AccordServer.fromBaseUrl('https://accord.example.test');
    client = AccordClient(
      token: 'test-token',
      baseUrl: server.baseUrl,
      gatewayUrl: server.gatewayUrl,
      cdnUrl: server.cdnUrl,
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/users/$_authorId')) {
          return http.Response(
            missingUser
                ? '{}'
                : jsonEncode({'id': _authorId, 'username': 'xvi'}),
            missingUser ? 404 : 200,
          );
        }
        if (request.url.path.endsWith('/channels/$_channelId/messages')) {
          return http.Response(
            jsonEncode([
              {
                'id': 'reply',
                'channel_id': _channelId,
                'author_id': _authorId,
                'content': 'A regular message with old@example.com',
                'reply_to': 'join',
                'timestamp': '2026-10-01T10:10:00Z',
              },
              join.toJson(),
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/channels/$_channelId/pins')) {
          return http.Response(jsonEncode([join.toJson()]), 200);
        }
        if (request.url.path.endsWith('/messages/search')) {
          return http.Response(jsonEncode([join.toJson()]), 200);
        }
        return http.Response('[]', 200);
      }),
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(
          AccordAuthLoggedIn(
            client: client,
            session: AccordSession(
              server: server,
              token: 'test-token',
              userId: 'self',
              username: 'self',
            ),
          ),
        ),
        settingsControllerProvider.overrideWith(_Settings.new),
      ],
    );
  }

  late final AccordMessage join;
  late final AccordClient client;
  late final ProviderContainer container;

  Widget app(Widget body) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(body: body),
    ),
  );

  Widget pane({String? spaceId}) =>
      app(MessagePane(channel: null, channelId: _channelId, spaceId: spaceId));

  void rename(String name) {
    container
        .read(accordUsersControllerProvider('').notifier)
        .upsert(AccordUser(id: _authorId, username: 'xvi', displayName: name));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    client.dispose();
  }
}

Future<void> _tick(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('old join text follows profile updates in chat and replies', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(harness.pane());
    await _tick(tester);

    expect(find.text('xvi joined the server.'), findsOneWidget);
    expect(find.text('xvi  xvi joined the server.'), findsOneWidget);
    expect(find.text(_legacyText, findRichText: true), findsNothing);
    expect(
      find.text('A regular message with old@example.com', findRichText: true),
      findsOneWidget,
    );

    harness.rename('**Alladinz** @everyone');
    await _tick(tester);
    expect(
      find.text('**Alladinz** @everyone joined the server.'),
      findsOneWidget,
    );
    // Profile names stay literal rather than being interpreted as Markdown.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('join')),
        matching: find.byType(AccordMessageContent),
      ),
      findsNothing,
    );
    expect(harness.join.content, _legacyText);
  });

  testWidgets('unresolved join authors never fall back to the saved email', (
    tester,
  ) async {
    final harness = _Harness(missingUser: true);
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(harness.pane());
    await _tick(tester);
    expect(find.text('Unknown joined the server.'), findsOneWidget);
    expect(find.text(_legacyText, findRichText: true), findsNothing);

    harness.rename('Alladinz');
    await _tick(tester);
    expect(find.text('Alladinz joined the server.'), findsOneWidget);
  });

  testWidgets('join text uses the space nickname even with an empty body', (
    tester,
  ) async {
    final harness = _Harness(content: '');
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(harness.pane(spaceId: 'space'));
    await _tick(tester);
    harness.container
        .read(accordMembersControllerProvider('', 'space').notifier)
        .upsertMember(
          AccordMember(
            userId: _authorId,
            spaceId: 'space',
            nickname: 'Space name',
            user: AccordUser(id: _authorId, username: 'xvi'),
          ),
        );
    await _tick(tester);
    expect(find.text('Space name joined the server.'), findsOneWidget);
  });

  testWidgets('copy text copies the displayed join name', (tester) async {
    final harness = _Harness();
    addTearDown(() => harness.dispose(tester));
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(harness.pane());
    await _tick(tester);
    await tester.longPress(find.text('xvi joined the server.'));
    await _tick(tester);
    await tester.tap(find.text('Copy text'));
    await _tick(tester);
    expect(copied, 'xvi joined the server.');
  });

  testWidgets('thread join text follows the current profile name', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(
      harness.app(
        AccordThreadPane(
          channelId: _channelId,
          spaceId: null,
          canManageMessages: false,
          root: harness.join,
          onClose: (_) {},
        ),
      ),
    );
    await _tick(tester);
    expect(find.text('xvi joined the server.'), findsOneWidget);
    harness.rename('Alladinz');
    await _tick(tester);
    expect(find.text('Alladinz joined the server.'), findsOneWidget);
    expect(find.text(_legacyText, findRichText: true), findsNothing);
  });

  testWidgets('search join text follows the current profile name', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(
      harness.app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showAccordSearch(context, spaceId: 'space'),
            child: const Text('Search'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Search'));
    await _tick(tester);
    await tester.enterText(find.byType(TextField), 'joined');
    await _tick(tester);
    expect(find.text('xvi joined the server.'), findsOneWidget);
    harness.rename('Alladinz');
    await _tick(tester);
    expect(find.text('Alladinz joined the server.'), findsOneWidget);
    expect(find.text(_legacyText), findsNothing);
  });

  testWidgets('pinned join text follows the current profile name', (
    tester,
  ) async {
    final harness = _Harness();
    addTearDown(() => harness.dispose(tester));
    await tester.pumpWidget(
      harness.app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showPinnedMessages(
              context,
              channelId: _channelId,
              canManage: false,
            ),
            child: const Text('Pins'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pins'));
    await _tick(tester);
    expect(find.text('xvi joined the server.'), findsOneWidget);
    harness.rename('Alladinz');
    await _tick(tester);
    expect(find.text('Alladinz joined the server.'), findsOneWidget);
    expect(find.text(_legacyText), findsNothing);
  });
}
