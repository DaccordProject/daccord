import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Client extends AccordClient {
  _Client(List<String> acks)
    : super(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/ack')) {
            acks.add(jsonDecode(request.body)['message_id'] as String);
          }
          return http.Response('{"data":[]}', 200);
        }),
      );
  final messageEvents = StreamController<AccordMessage>.broadcast();
  final reads = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<AccordMessage> get onMessageCreate => messageEvents.stream;
  @override
  Stream<Map<String, dynamic>> get onReadStateUpdate => reads.stream;
}

class _Settings extends SettingsController {
  @override
  AccordSettings build() =>
      const AccordSettings(notificationsEnabled: false, soundsEnabled: false);
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _Client client;
  late ProviderContainer container;
  late List<String> acks;
  var active = true;
  const key = 'self@https://example.test';
  const channel = 'channel';
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    active = true;
    acks = [];
    client = _Client(acks);
    container = ProviderContainer(
      overrides: [settingsControllerProvider.overrideWith(_Settings.new)],
    );
    final handler = Provider<void>((ref) {
      final dispose = handleAccordEvents(
        ref,
        client,
        serverKey: key,
        currentUserId: 'self',
        selfDomain: 'example.test',
        isActive: () => active,
      );
      ref.onDispose(dispose);
    });
    container.read(handler);
    accordVisibleChannel = (serverKey: key, channelId: channel);
  });
  tearDown(() async {
    accordVisibleChannel = null;
    container.dispose();
    await client.messageEvents.close();
    await client.reads.close();
    client.dispose();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  Future<void> settle() => Future<void>.delayed(Duration.zero);
  ReadStateSnapshot snapshot() =>
      container.read(readStateControllerProvider(key));
  void message(String id) => client.messageEvents.add(
    AccordMessage(
      id: id,
      channelId: channel,
      spaceId: 'space',
      authorId: 'other',
      mentions: ['self'],
    ),
  );

  test(
    'live messages in the viewed channel ack the actual message ID',
    () async {
      message('10');
      await settle();
      expect(acks, ['10']);
      expect(snapshot().isUnread(channel), isFalse);
      accordVisibleChannel = null;
      message('10');
      await settle();
      expect(snapshot().isUnread(channel), isFalse);
      message('11');
      await settle();
      expect(snapshot().mentionCount(channel), 1);
    },
  );

  test('an inactive device leaves its selected channel unread', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    message('10');
    await settle();
    expect(acks, isEmpty);
    expect(snapshot().mentionCount(channel), 1);
  });

  test('background-server remote reads retain newer unread messages', () async {
    active = false;
    message('10');
    message('11');
    await settle();
    client.reads.add({'channel_id': channel, 'last_read_message_id': '10'});
    await settle();
    expect(snapshot().mentionCount(channel), 1);
    client.reads.add({'channel_id': channel, 'last_read_message_id': '11'});
    await settle();
    expect(snapshot().isUnread(channel), isFalse);
    message('11');
    await settle();
    expect(snapshot().isUnread(channel), isFalse);
    expect(acks, isEmpty);
  });
}
