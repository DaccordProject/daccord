import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/channels/controllers/open_tabs.dart';
import 'package:bonfire/features/channels/models/open_tab.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/user/controllers/blocked_users.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [GatewayConnection] a test can push inbound frames through.
class _FakeGatewayConnection implements GatewayConnection {
  final _messages = StreamController<String>();
  void receive(Map<String, dynamic> frame) => _messages.add(jsonEncode(frame));
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<String> get messages => _messages.stream;
  @override
  void sendText(String text) {}
  @override
  Future<void> close([int? code, String? reason]) => _messages.close();
  @override
  int? closeCode;
  @override
  String? closeReason;
}

/// Keeps message.create off Hive, the notification plugin and the audio
/// players — none of which exist under `flutter test`.
class _QuietSettings extends SettingsController {
  @override
  AccordSettings build() =>
      const AccordSettings(notificationsEnabled: false, soundsEnabled: false);
}

/// Seeds the blocked set without the relationship fetch.
class _FakeBlockedUsers extends BlockedUsersController {
  _FakeBlockedUsers(this.initial);

  final Set<String> initial;

  @override
  Set<String> build(String serverKey) => initial;
}

const _serverKey = 'u-self@https://accord.example.test';
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  test('a gateway message.create lands in the open channel cache', () async {
    final connection = _FakeGatewayConnection();
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      gatewayUrl: 'wss://accord.example.test/ws',
      connectionFactory: (_) => connection,
    );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [settingsControllerProvider.overrideWith(_QuietSettings.new)],
    );
    addTearDown(container.dispose);
    // Listening opens the channel, which is what lets the handler cache into it.
    final provider = accordMessagesControllerProvider(_serverKey, 'c1');
    container.listen(provider, (_, _) {});
    addTearDown(
      handleAccordEvents(
        container.read(_refProvider),
        client,
        serverKey: _serverKey,
        currentUserId: 'u-self',
        selfDomain: 'accord.example.test',
        isActive: () => true,
      ),
    );
    client.login();
    await Future<void>.delayed(Duration.zero);

    connection.receive({
      'op': GatewayOpcodes.event,
      'type': 'message.create',
      'data': {
        'id': 'm1',
        'channel_id': 'c1',
        'space_id': 's1',
        'author_id': 'u-other',
        'content': 'hello',
      },
    });
    await Future<void>.delayed(Duration.zero);

    expect(container.read(provider)?.single.id, 'm1');
  });

  test('our own message reads the channel instead of highlighting it', () async {
    final connection = _FakeGatewayConnection();
    final acked = <String>[];
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      gatewayUrl: 'wss://accord.example.test/ws',
      connectionFactory: (_) => connection,
      httpClient: MockClient((request) async {
        acked.add('${request.method} ${request.url.path} ${request.body}');
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [settingsControllerProvider.overrideWith(_QuietSettings.new)],
    );
    addTearDown(container.dispose);
    // Unread from somebody else, in a channel that is not on screen.
    container
        .read(readStateControllerProvider(_serverKey).notifier)
        .markUnread('c1', spaceId: 's1');
    addTearDown(
      handleAccordEvents(
        container.read(_refProvider),
        client,
        serverKey: _serverKey,
        currentUserId: 'u-self',
        selfDomain: 'accord.example.test',
        isActive: () => true,
      ),
    );
    client.login();
    await Future<void>.delayed(Duration.zero);

    // Federation echoes our own message back qualified to our home domain.
    connection.receive({
      'op': GatewayOpcodes.event,
      'type': 'message.create',
      'data': {
        'id': 'm7',
        'channel_id': 'c1',
        'space_id': 's1',
        'author_id': 'u-self@accord.example.test',
        'content': 'mine',
      },
    });
    await Future<void>.delayed(Duration.zero);

    final state = container.read(readStateControllerProvider(_serverKey));
    expect(state.isUnread('c1'), isFalse);
    // The ack is what stops READY's `unread` array from re-lighting the channel.
    expect(acked, contains('POST /api/v1/channels/c1/ack {"message_id":"m7"}'));
  });

  test('a blocked account never lights a DM or counts as a mention', () async {
    final connection = _FakeGatewayConnection();
    final client = AccordClient(
      baseUrl: 'https://accord.example.test',
      gatewayUrl: 'wss://accord.example.test/ws',
      connectionFactory: (_) => connection,
    );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(_QuietSettings.new),
        blockedUsersControllerProvider(
          _serverKey,
        ).overrideWith(() => _FakeBlockedUsers({'u-blocked'})),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(
      handleAccordEvents(
        container.read(_refProvider),
        client,
        serverKey: _serverKey,
        currentUserId: 'u-self',
        selfDomain: 'accord.example.test',
        isActive: () => true,
      ),
    );
    client.login();
    await Future<void>.delayed(Duration.zero);

    // A DM from the blocked account is dropped outright.
    connection.receive({
      'op': GatewayOpcodes.event,
      'type': 'message.create',
      'data': {
        'id': 'm1',
        'channel_id': 'dm1',
        'author_id': 'u-blocked',
        'content': 'let me in',
      },
    });
    // A space mention from them still lands, but as a plain unread.
    connection.receive({
      'op': GatewayOpcodes.event,
      'type': 'message.create',
      'data': {
        'id': 'm2',
        'channel_id': 'c1',
        'space_id': 's1',
        'author_id': 'u-blocked',
        'content': 'hey @self',
        'mentions': ['u-self'],
      },
    });
    await Future<void>.delayed(Duration.zero);

    final state = container.read(readStateControllerProvider(_serverKey));
    expect(state.isUnread('dm1'), isFalse);
    expect(state.isUnread('c1'), isTrue);
    expect(state.mentionCount('c1'), 0);
  });

  group('losing a space', () {
    late Directory tempDir;

    setUp(() async {
      // The open-tab strip persists to the settings box.
      tempDir = Directory.systemTemp.createTempSync('event-handler-test');
      Hive.init(tempDir.path);
      await Hive.openBox('accord-settings');
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk('accord-settings');
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('our own member.leave removes the space and its tabs', () async {
      final connection = _FakeGatewayConnection();
      final client = AccordClient(
        baseUrl: 'https://accord.example.test',
        gatewayUrl: 'wss://accord.example.test/ws',
        connectionFactory: (_) => connection,
      );
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [
          settingsControllerProvider.overrideWith(_QuietSettings.new),
        ],
      );
      addTearDown(container.dispose);

      final session = AccordSession(
        server: AccordServer.fromBaseUrl('https://accord.example.test'),
        token: 't',
        userId: 'u-self',
        username: 'self',
      );
      expect(session.key, _serverKey);
      final spaces = [
        AccordSpace(id: 's1', name: 'Banned from'),
        AccordSpace(id: 's2', name: 'Still in'),
      ];
      container.read(connectionsControllerProvider.notifier)
        ..register(session)
        ..setActive(_serverKey)
        ..setSpaces(_serverKey, spaces);
      final spacesCtl = container.read(spacesControllerProvider.notifier);
      for (final space in spaces) {
        spacesCtl.upsertSpace(space);
      }
      container.read(openTabsControllerProvider.notifier)
        ..open(
          const OpenTab(
            channelId: 'c2',
            spaceId: 's2',
            serverKey: _serverKey,
            name: 'general',
          ),
        )
        ..open(
          const OpenTab(
            channelId: 'c1',
            spaceId: 's1',
            serverKey: _serverKey,
            name: 'general',
          ),
        );

      addTearDown(
        handleAccordEvents(
          container.read(_refProvider),
          client,
          serverKey: _serverKey,
          currentUserId: 'u-self',
          selfDomain: 'accord.example.test',
          isActive: () => true,
        ),
      );
      client.login();
      await Future<void>.delayed(Duration.zero);

      List<String> railIds() => [
        for (final s
            in container.read(connectionsControllerProvider).active!.spaces)
          s.id,
      ];
      List<String> activeIds() => [
        for (final s in container.read(spacesControllerProvider)!) s.id,
      ];

      // Somebody else leaving changes nothing about our spaces.
      connection.receive({
        'op': GatewayOpcodes.event,
        'type': 'member.leave',
        'data': {'space_id': 's1', 'user_id': 'u-other'},
      });
      await Future<void>.delayed(Duration.zero);
      expect(railIds(), ['s1', 's2']);

      // Our own removal may echo back qualified to our home domain.
      connection.receive({
        'op': GatewayOpcodes.event,
        'type': 'member.leave',
        'data': {'space_id': 's1', 'user_id': 'u-self@accord.example.test'},
      });
      await Future<void>.delayed(Duration.zero);

      expect(railIds(), ['s2']);
      expect(activeIds(), ['s2']);
      final tabs = container.read(openTabsControllerProvider);
      expect(tabs.tabs.map((t) => t.spaceId), ['s2']);
      // The viewed tab was in the lost space, so the home screen falls back.
      expect(tabs.activeTab, isNull);
    });
  });
}
