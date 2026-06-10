import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

import 'support/fake_gateway_connection.dart';
import 'support/test_helpers.dart';

Future<void> pump([int times = 2]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeConnectionFactory factory;
  late GatewaySocket gateway;

  Future<void> connectGateway() async {
    gateway = GatewaySocket(
      connectionFactory: factory.call,
      sleep: (_) async {},
      random: () => 0.0,
    );
    gateway.setup(AccordConfig(), 'tok');
    gateway.connectToGateway('ws://x');
    await pump();
  }

  setUp(() {
    factory = FakeConnectionFactory();
  });

  test('join success emits onVoiceConnected and tracks channel', () async {
    await connectGateway();
    final voiceApi = VoiceApi(mockRest(
      log: [],
      responder: (_) => jsonData({
        'space_id': '7',
        'channel_id': '5',
        'backend': 'livekit',
        'url': 'wss://lk',
        'token': 't',
        'voice_state': {'user_id': '9', 'channel_id': '5'},
      }),
    ));
    final manager = VoiceManager(voiceApi, gateway);
    final connected = <AccordVoiceServerUpdate>[];
    manager.onVoiceConnected.listen(connected.add);

    final result = await manager.join('5', selfMute: true);
    await pump();

    expect(result.ok, isTrue);
    expect(manager.isConnectedToVoice(), isTrue);
    expect(manager.getCurrentChannel(), '5');
    expect(connected.single.livekitUrl, 'wss://lk');
    await manager.dispose();
    await gateway.dispose();
  });

  test('join failure emits onVoiceError', () async {
    await connectGateway();
    final voiceApi = VoiceApi(mockRest(
      log: [],
      responder: (_) => jsonError('FORBIDDEN', 'no voice', status: 403),
    ));
    final manager = VoiceManager(voiceApi, gateway);
    final errors = <String>[];
    manager.onVoiceError.listen(errors.add);

    final result = await manager.join('5');
    await pump();

    expect(result.ok, isFalse);
    expect(errors.single, 'no voice');
    expect(manager.isConnectedToVoice(), isFalse);
    await manager.dispose();
    await gateway.dispose();
  });

  test('leave without a channel returns a failure', () async {
    await connectGateway();
    final voiceApi =
        VoiceApi(mockRest(log: [], responder: (_) => jsonData(null)));
    final manager = VoiceManager(voiceApi, gateway);
    final result = await manager.leave();
    expect(result.ok, isFalse);
    await manager.dispose();
    await gateway.dispose();
  });

  test('forced disconnect via voice.state_update with null channel', () async {
    await connectGateway();
    final voiceApi = VoiceApi(mockRest(
      log: [],
      responder: (_) => jsonData({
        'space_id': '7',
        'channel_id': '5',
        'backend': 'custom',
        'voice_state': {'user_id': '9', 'channel_id': '5'},
      }),
    ));
    final manager = VoiceManager(voiceApi, gateway);
    final disconnects = <String>[];
    manager.onVoiceDisconnected.listen(disconnects.add);

    await manager.join('5');
    await pump();

    // Gateway relays a state update removing us from the channel.
    factory.last.receive(jsonEncode({
      'op': GatewayOpcodes.event,
      'type': 'voice.state_update',
      'data': {'user_id': '9', 'channel_id': null},
    }));
    await pump();

    expect(disconnects, contains('5'));
    expect(manager.isConnectedToVoice(), isFalse);
    await manager.dispose();
    await gateway.dispose();
  });
}
