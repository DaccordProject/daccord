import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/accord_channels.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _SwitchingAuth extends AccordAuth {
  _SwitchingAuth(this.initial);

  final AccordAuthState initial;

  @override
  AccordAuthState build() => initial;

  // ignore: use_setters_to_change_properties
  void publish(AccordAuthState next) => state = next;
}

void main() {
  ProviderContainer container() {
    final result = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      ],
    );
    addTearDown(result.dispose);
    return result;
  }

  AccordMessage message(String content) => AccordMessage(
    id: 'same-message',
    channelId: 'same-channel',
    content: content,
  );

  test('identical remote IDs address distinct server provider instances', () {
    final c = container();

    c
        .read(
          accordChannelsControllerProvider('server-a', 'same-space').notifier,
        )
        .setChannels([
          AccordChannel(id: 'same-channel', name: 'from A', type: 'text'),
        ]);
    c
        .read(
          accordChannelsControllerProvider('server-b', 'same-space').notifier,
        )
        .setChannels([
          AccordChannel(id: 'same-channel', name: 'from B', type: 'text'),
        ]);

    c
        .read(
          accordMessagesControllerProvider('server-a', 'same-channel').notifier,
        )
        .addMessage(message('from A'));
    c
        .read(
          accordMessagesControllerProvider('server-b', 'same-channel').notifier,
        )
        .addMessage(message('from B'));

    expect(
      c
          .read(accordChannelsControllerProvider('server-a', 'same-space'))!
          .single
          .name,
      'from A',
    );
    expect(
      c
          .read(accordMessagesControllerProvider('server-a', 'same-channel'))!
          .single
          .content,
      'from A',
    );
    expect(
      c
          .read(accordMessagesControllerProvider('server-b', 'same-channel'))!
          .single
          .content,
      'from B',
    );
    expect(
      activeMessageChannels,
      containsAll(<ServerChannelKey>[
        (serverKey: 'server-a', channelId: 'same-channel'),
        (serverKey: 'server-b', channelId: 'same-channel'),
      ]),
    );
  });

  test('thread, forum, member and voice caches do not alias', () {
    final c = container();
    final fromA = message('from A');
    final fromB = message('from B');

    c
        .read(
          threadRepliesControllerProvider(
            'server-a',
            'same-channel',
            'same-root',
          ).notifier,
        )
        .addReply(fromA);
    c
        .read(
          threadRepliesControllerProvider(
            'server-b',
            'same-channel',
            'same-root',
          ).notifier,
        )
        .addReply(fromB);
    c
        .read(forumPostsControllerProvider('server-a', 'same-channel').notifier)
        .addPost(fromA);
    c
        .read(forumPostsControllerProvider('server-b', 'same-channel').notifier)
        .addPost(fromB);

    final memberA = AccordMember.fromJson({
      'space_id': 'same-space',
      'user_id': 'same-user',
      'nickname': 'from A',
    });
    final memberB = AccordMember.fromJson({
      'space_id': 'same-space',
      'user_id': 'same-user',
      'nickname': 'from B',
    });
    c
        .read(
          accordMembersControllerProvider('server-a', 'same-space').notifier,
        )
        .upsertMember(memberA);
    c
        .read(
          accordMembersControllerProvider('server-b', 'same-space').notifier,
        )
        .upsertMember(memberB);

    c
        .read(voiceStatesControllerProvider('server-a').notifier)
        .upsert(
          AccordVoiceState(userId: 'same-user', channelId: 'same-channel'),
        );

    expect(
      c
          .read(
            threadRepliesControllerProvider(
              'server-a',
              'same-channel',
              'same-root',
            ),
          )!
          .single
          .content,
      'from A',
    );
    expect(
      c
          .read(forumPostsControllerProvider('server-b', 'same-channel'))!
          .single
          .content,
      'from B',
    );
    expect(
      c
          .read(accordMembersControllerProvider('server-a', 'same-space'))!
          .values
          .single
          .nickname,
      'from A',
    );
    expect(c.read(voiceStatesControllerProvider('server-b')), isEmpty);
  });

  test(
    'a channel response completing after a server switch is discarded',
    () async {
      final releaseA = Completer<void>();
      final startedA = Completer<void>();
      final serverA = AccordServer.fromBaseUrl('https://a.example.test');
      final serverB = AccordServer.fromBaseUrl('https://b.example.test');
      final clientA = AccordClient(
        token: 'a',
        baseUrl: serverA.baseUrl,
        gatewayUrl: serverA.gatewayUrl,
        cdnUrl: serverA.cdnUrl,
        httpClient: MockClient((_) async {
          if (!startedA.isCompleted) startedA.complete();
          await releaseA.future;
          return http.Response(
            jsonEncode([
              {'id': 'same-channel', 'name': 'late A', 'type': 'text'},
            ]),
            200,
          );
        }),
      );
      final clientB = AccordClient(
        token: 'b',
        baseUrl: serverB.baseUrl,
        gatewayUrl: serverB.gatewayUrl,
        cdnUrl: serverB.cdnUrl,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode([
              {'id': 'same-channel', 'name': 'from B', 'type': 'text'},
            ]),
            200,
          ),
        ),
      );
      final sessionA = AccordSession(
        server: serverA,
        token: 'a',
        userId: 'user',
        username: 'A',
      );
      final sessionB = AccordSession(
        server: serverB,
        token: 'b',
        userId: 'user',
        username: 'B',
      );
      final authA = AccordAuthLoggedIn(client: clientA, session: sessionA);
      final c = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(() => _SwitchingAuth(authA)),
        ],
      );
      addTearDown(c.dispose);
      addTearDown(clientA.dispose);
      addTearDown(clientB.dispose);

      c.read(accordChannelsControllerProvider(sessionA.key, 'same-space'));
      await startedA.future;
      (c.read(accordAuthProvider.notifier) as _SwitchingAuth).publish(
        AccordAuthLoggedIn(client: clientB, session: sessionB),
      );
      c.read(accordChannelsControllerProvider(sessionB.key, 'same-space'));
      releaseA.complete();

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        c.read(accordChannelsControllerProvider(sessionA.key, 'same-space')),
        isNull,
      );
      expect(
        c
            .read(accordChannelsControllerProvider(sessionB.key, 'same-space'))!
            .single
            .name,
        'from B',
      );
    },
  );
}
