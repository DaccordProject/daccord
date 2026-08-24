import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/services/deep_link_navigation.dart';
import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:bonfire/features/spaces/views/accord_home.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccordConnection connection({
  required String host,
  required ConnectionStatus status,
  List<AccordSpace> spaces = const [],
  String userId = 'user',
}) => AccordConnection(
  session: AccordSession(
    server: AccordServer.fromBaseUrl('https://$host'),
    token: 'token',
    userId: userId,
    username: userId,
  ),
  status: status,
  spaces: spaces,
  spacesReady: status == ConnectionStatus.ready,
);

void main() {
  test(
    'pending controller retains a cold-start destination until consumed',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const destination = PendingDeepLinkDestination(spaceId: 'space-1');

      container.read(pendingDeepLinkProvider.notifier).hold(destination);
      expect(container.read(pendingDeepLinkProvider), same(destination));

      container.read(pendingDeepLinkProvider.notifier).clear();
      expect(container.read(pendingDeepLinkProvider), isNull);
    },
  );

  test(
    'navigate waits for the owning READY connection, then qualifies route',
    () {
      const pending = PendingDeepLinkDestination(
        spaceId: 'space-2',
        channelId: 'channel-2',
        messageId: 'message-2',
      );
      final targetSpace = AccordSpace(id: 'space-2', name: 'Target');
      final starting = ConnectionsState(
        connections: [
          connection(
            host: 'one.example',
            status: ConnectionStatus.ready,
            spaces: [AccordSpace(id: 'space-1')],
          ),
          connection(
            host: 'two.example',
            status: ConnectionStatus.connecting,
            spaces: [targetSpace],
            userId: 'two',
          ),
        ],
      );
      expect(
        resolveDeepLinkDestination(pending, starting),
        isA<DeepLinkWaiting>(),
      );

      final ready = ConnectionsState(
        connections: [
          starting.connections.first,
          connection(
            host: 'two.example',
            status: ConnectionStatus.ready,
            spaces: [targetSpace],
            userId: 'two',
          ),
        ],
      );
      final resolution = resolveDeepLinkDestination(pending, ready);
      expect(resolution, isA<DeepLinkResolved>());
      final resolved = (resolution as DeepLinkResolved).destination;
      expect(resolved.serverKey, 'two@https://two.example');
      expect(resolved.route.queryParameters, {
        'space': 'space-2',
        'channel': 'channel-2',
        'message': 'message-2',
      });
    },
  );

  test(
    'connect link resolves server, slug, and decoded channel end to end',
    () {
      final parsed = ServerUri.parseDeepLink(
        'daccord://connect/chat.example/team-news?channel=release%20notes',
      )!;
      final pending = PendingDeepLinkDestination.fromParsed(parsed)!;
      final state = ConnectionsState(
        connections: [
          connection(
            host: 'chat.example',
            status: ConnectionStatus.ready,
            spaces: [
              AccordSpace(id: 'space-9', name: 'Team News', slug: 'team-news'),
            ],
          ),
        ],
      );

      final resolution = resolveDeepLinkDestination(pending, state);
      expect(resolution, isA<DeepLinkResolved>());
      final resolved = (resolution as DeepLinkResolved).destination;
      expect(resolved.route.queryParameters['space'], 'space-9');
      expect(resolved.route.queryParameters['channelName'], 'release notes');
      expect(
        resolveDeepLinkChannel([
          AccordChannel(id: 'channel-9', name: 'release notes'),
          AccordChannel(id: 'channel-8', name: 'general'),
        ], channelName: resolved.channelName)?.id,
        'channel-9',
      );
    },
  );

  test('a disk space snapshot is not a ready destination cache', () {
    final cached = connection(
      host: 'chat.example',
      status: ConnectionStatus.ready,
      spaces: [AccordSpace(id: 'space-1')],
    ).copyWith(spacesReady: false);

    expect(
      resolveDeepLinkDestination(
        const PendingDeepLinkDestination(spaceId: 'space-1'),
        ConnectionsState(connections: [cached]),
      ),
      isA<DeepLinkWaiting>(),
    );
  });

  test(
    'connect destination never resolves against a different active server',
    () {
      final state = ConnectionsState(
        connections: [
          connection(
            host: 'other.example',
            status: ConnectionStatus.ready,
            spaces: [AccordSpace(id: 'space-1', slug: 'team-news')],
          ),
        ],
        activeKey: 'user@https://other.example',
      );
      const pending = PendingDeepLinkDestination(
        serverBaseUrl: 'https://chat.example',
        spaceName: 'team-news',
      );

      expect(
        resolveDeepLinkDestination(pending, state),
        isA<DeepLinkWaiting>(),
      );
    },
  );

  test('duplicate channel names fail closed', () {
    expect(
      resolveDeepLinkChannel([
        AccordChannel(id: 'one', name: 'general'),
        AccordChannel(id: 'two', name: 'general'),
      ], channelName: 'general'),
      isNull,
    );
  });
}
