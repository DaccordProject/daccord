import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  _Auth(this.auth);
  final AccordAuthLoggedIn auth;
  @override
  AccordAuthState build() => auth;
  @override
  AccordClient? clientForKey(String key) =>
      key == auth.session.key ? auth.client : null;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

void main() {
  testWidgets(
    'history load and app resume advance the visible channel read position',
    (tester) async {
      final acks = <String>[];
      final history = Completer<http.Response>();
      final server = AccordServer.fromBaseUrl('https://example.test');
      final client = AccordClient(
        baseUrl: server.baseUrl,
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/messages')) return history.future;
          if (request.url.path.endsWith('/ack')) {
            acks.add(jsonDecode(request.body)['message_id'] as String);
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
      final session = AccordSession(
        server: server,
        token: 'test',
        userId: 'self',
        username: 'Self',
      );
      final key = session.key;
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(
            () => _Auth(AccordAuthLoggedIn(client: client, session: session)),
          ),
          settingsControllerProvider.overrideWith(_Settings.new),
        ],
      );
      addTearDown(() {
        accordVisibleChannel = null;
        container.dispose();
        client.dispose();
      });
      container.read(connectionsControllerProvider.notifier).register(session);
      container.read(connectionsControllerProvider.notifier).setActive(key);
      accordVisibleChannel = (serverKey: key, channelId: 'channel');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final reads = container.read(readStateControllerProvider(key).notifier);
      reads.hydrate(const [
        ReadEntry(channelId: 'channel', lastMessageId: '10'),
      ]);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(AppThemePreset.dark),
            home: const Scaffold(
              body: MessagePane(
                channel: null,
                channelId: 'channel',
                spaceId: null,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(acks, ['10']);
      history.complete(
        http.Response(
          jsonEncode({
            'data': [
              {
                'id': '20',
                'channel_id': 'channel',
                'author_id': 'self',
                'content': 'Newest message',
                'timestamp': '2026-09-07T12:00:00Z',
              },
            ],
          }),
          200,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(acks, ['10', '20']);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      reads.receiveMessage('channel', '21');
      reads.markUnread('channel', messageId: '21', isMention: true);
      container
          .read(accordMessagesControllerProvider(key, 'channel').notifier)
          .addMessage(
            AccordMessage(
              id: '21',
              channelId: 'channel',
              authorId: 'self',
              content: 'While away',
            ),
          );
      await tester.pump();
      expect(acks, ['10', '20']);
      expect(
        container.read(readStateControllerProvider(key)).isUnread('channel'),
        isTrue,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(acks, ['10', '20', '21']);
      expect(
        container.read(readStateControllerProvider(key)).isUnread('channel'),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
