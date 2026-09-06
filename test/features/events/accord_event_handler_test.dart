import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/messaging/controllers/accord_messages.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
