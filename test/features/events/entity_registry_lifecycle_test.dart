import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/member/controllers/accord_members.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/messaging/controllers/forum_posts.dart';
import 'package:bonfire/features/messaging/controllers/thread_replies.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'closed entities leave reconnect registries and are not reloaded',
    () async {
      var requests = 0;
      final server = AccordServer.fromBaseUrl('https://accord.example.test');
      final client = AccordClient(
        token: 'token',
        baseUrl: server.baseUrl,
        gatewayUrl: server.gatewayUrl,
        cdnUrl: server.cdnUrl,
        httpClient: MockClient((_) async {
          requests++;
          return http.Response(jsonEncode(<Object>[]), 200);
        }),
      );
      final session = AccordSession(
        server: server,
        token: 'token',
        userId: 'self',
        username: 'Self',
      );
      final serverKey = session.key;
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWithValue(
            AccordAuthLoggedIn(client: client, session: session),
          ),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.dispose);

      final messages = container.listen(
        accordMessagesControllerProvider(serverKey, 'channel'),
        (_, _) {},
        fireImmediately: true,
      );
      final replies = container.listen(
        threadRepliesControllerProvider(serverKey, 'channel', 'root'),
        (_, _) {},
        fireImmediately: true,
      );
      final posts = container.listen(
        forumPostsControllerProvider(serverKey, 'forum'),
        (_, _) {},
        fireImmediately: true,
      );
      final members = container.listen(
        accordMembersControllerProvider(serverKey, 'space'),
        (_, _) {},
        fireImmediately: true,
      );

      expect(
        activeMessageChannels,
        contains((serverKey: serverKey, channelId: 'channel')),
      );
      expect(
        activeThreadReplies,
        contains((
          serverKey: serverKey,
          channelId: 'channel',
          rootId: 'root',
        )),
      );
      expect(
        activeForumChannels,
        contains((serverKey: serverKey, channelId: 'forum')),
      );
      expect(
        activeMemberSpaces,
        contains((serverKey: serverKey, spaceId: 'space')),
      );

      messages.close();
      replies.close();
      posts.close();
      members.close();
      await container.pump();

      expect(
        activeMessageChannels,
        isNot(contains((serverKey: serverKey, channelId: 'channel'))),
      );
      expect(
        activeThreadReplies,
        isNot(
          contains((
            serverKey: serverKey,
            channelId: 'channel',
            rootId: 'root',
          )),
        ),
      );
      expect(
        activeForumChannels,
        isNot(contains((serverKey: serverKey, channelId: 'forum'))),
      );
      expect(
        activeMemberSpaces,
        isNot(contains((serverKey: serverKey, spaceId: 'space'))),
      );

      // This is the reconnect fanout's target selection. Once every view closes,
      // none of these loops may recreate a controller or issue another request.
      final requestsBeforeReconnect = requests;
      for (final key in [...activeMessageChannels]) {
        await container
            .read(
              accordMessagesControllerProvider(
                key.serverKey,
                key.channelId,
              ).notifier,
            )
            .reload(client);
      }
      for (final key in [...activeThreadReplies]) {
        await container
            .read(
              threadRepliesControllerProvider(
                key.serverKey,
                key.channelId,
                key.rootId,
              ).notifier,
            )
            .reload(client);
      }
      for (final key in [...activeForumChannels]) {
        await container
            .read(
              forumPostsControllerProvider(
                key.serverKey,
                key.channelId,
              ).notifier,
            )
            .reload(client);
      }
      expect(requests, requestsBeforeReconnect);
    },
  );
}
