import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

import 'support/fake_gateway_connection.dart';

/// Yields to the microtask/event queue so stream events and `.then` callbacks
/// run.
Future<void> pump([int times = 2]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

GatewaySocket makeSocket(FakeConnectionFactory factory) {
  final s = GatewaySocket(
    connectionFactory: factory.call,
    sleep: (_) async {},
    random: () => 0.0,
    token: 'tok',
    tokenType: 'Bot',
  );
  s.setup(AccordConfig(), 'tok', tknType: 'Bot', intentList: ['messages']);
  return s;
}

Map<String, dynamic> lastSent(FakeGatewayConnection c) =>
    jsonDecode(c.sent.last) as Map<String, dynamic>;

void main() {
  group('handshake', () {
    test('emits connected when the socket becomes ready', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      final connected = <void>[];
      socket.onConnected.listen(connected.add);

      socket.connectToGateway('ws://x');
      await pump();

      expect(socket.state, GatewayState.connected);
      expect(connected, hasLength(1));
      await socket.dispose();
    });

    test('HELLO triggers IDENTIFY with token and intents', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 60000},
      }));
      await pump();

      final sent = lastSent(factory.last);
      expect(sent['op'], GatewayOpcodes.identify);
      expect(sent['data']['token'], 'Bot tok');
      expect(sent['data']['intents'], ['messages']);
      await socket.dispose();
    });
  });

  group('heartbeat', () {
    test('server HEARTBEAT op prompts an immediate heartbeat with sequence',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      // Deliver an event carrying a sequence number.
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'typing.start',
        'seq': 7,
        'data': {'channel_id': '1'},
      }));
      // Server asks us to heartbeat.
      factory.last.receive(jsonEncode({'op': GatewayOpcodes.heartbeat}));
      await pump();

      final sent = lastSent(factory.last);
      expect(sent['op'], GatewayOpcodes.heartbeat);
      expect(sent['data'], 7);
      await socket.dispose();
    });
  });

  group('dispatch', () {
    test('message.create emits a typed AccordMessage and a raw event',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      final messages = <AccordMessage>[];
      final raw = <RawGatewayEvent>[];
      socket.onMessageCreate.listen(messages.add);
      socket.onRawEvent.listen(raw.add);

      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'message.create',
        'data': {'id': '1', 'channel_id': '5', 'content': 'hi'},
      }));
      await pump();

      expect(messages.single.content, 'hi');
      expect(raw.single.type, 'message.create');
      await socket.dispose();
    });

    test('ready event records the session id', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'SESSION'},
      }));
      await pump();

      expect(socket.sessionId, 'SESSION');
      await socket.dispose();
    });
  });

  group('outbound helpers', () {
    test('updatePresence / updateVoiceState / requestMembers / voiceSignal',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      final conn = factory.last;

      socket.updatePresence('online', activity: {'name': 'g'});
      expect(lastSent(conn)['op'], GatewayOpcodes.presenceUpdate);
      expect(lastSent(conn)['data']['activity'], {'name': 'g'});

      socket.updateVoiceState('7', '5', selfMute: true);
      expect(lastSent(conn)['op'], GatewayOpcodes.voiceStateUpdate);
      expect(lastSent(conn)['data']['channel_id'], '5');
      expect(lastSent(conn)['data']['self_mute'], true);

      socket.updateVoiceState('7', null);
      expect(lastSent(conn)['data']['channel_id'], isNull);

      socket.requestMembers('7', query: 'al', limit: 5);
      expect(lastSent(conn)['op'], GatewayOpcodes.requestMembers);
      expect(lastSent(conn)['data']['limit'], 5);

      socket.sendVoiceSignal('7', '5', 'offer', {'sdp': 'x'});
      expect(lastSent(conn)['op'], GatewayOpcodes.voiceSignal);
      expect(lastSent(conn)['data']['type'], 'offer');

      await socket.dispose();
    });
  });

  group('reconnect', () {
    test('resumes after an unexpected close once a session exists', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      // Establish a session.
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'S1'},
      }));
      await pump();

      // Unexpected drop.
      factory.last.simulateClose(1006);
      await pump();

      expect(factory.connections.length, 2,
          reason: 'a reconnect connection should be created');

      // New connection gets HELLO → should RESUME (not IDENTIFY).
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 60000},
      }));
      await pump();

      final sent = lastSent(factory.last);
      expect(sent['op'], GatewayOpcodes.resume);
      expect(sent['data']['session_id'], 'S1');
      await socket.dispose();
    });

    test('does not reconnect on a fatal close code', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.simulateClose(4004); // authentication failed
      await pump();

      expect(factory.connections.length, 1);
      expect(socket.state, GatewayState.disconnected);
      await socket.dispose();
    });

    test('disconnectFromGateway emits disconnected and suppresses reconnect',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      final disconnects = <DisconnectInfo>[];
      socket.onDisconnected.listen(disconnects.add);

      socket.connectToGateway('ws://x');
      await pump();
      await socket.disconnectFromGateway(1000, 'bye');
      await pump();

      expect(disconnects.single.reason, 'bye');
      expect(factory.connections.length, 1);
      expect(socket.state, GatewayState.disconnected);
      await socket.dispose();
    });

    test('non-resumable INVALID_SESSION clears session and reconnects',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'S1'},
      }));
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.invalidSession,
        'data': false,
      }));
      await pump();

      expect(socket.sessionId, '');
      expect(factory.connections.length, 2);
      await socket.dispose();
    });
  });

  group('ensureConnected', () {
    /// A socket whose automatic reconnects are exhausted immediately, so tests
    /// can observe ensureConnected reviving a connection the backoff gave up on.
    GatewaySocket makeExhaustedSocket(FakeConnectionFactory factory) {
      final s = GatewaySocket(
        connectionFactory: factory.call,
        sleep: (_) async {},
        random: () => 0.0,
        maxReconnectAttempts: 0,
        token: 'tok',
        tokenType: 'Bot',
      );
      s.setup(AccordConfig(), 'tok', tknType: 'Bot', intentList: ['messages']);
      return s;
    }

    test('is a no-op before the first connect', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);

      socket.ensureConnected();
      await pump();

      expect(factory.connections, isEmpty);
      await socket.dispose();
    });

    test('is a no-op after an explicit disconnect', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      await socket.disconnectFromGateway();

      socket.ensureConnected();
      await pump();

      expect(factory.connections, hasLength(1));
      expect(socket.state, GatewayState.disconnected);
      await socket.dispose();
    });

    test('revives a dead socket even after reconnects are exhausted',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeExhaustedSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.simulateClose(1006);
      await pump();
      expect(socket.state, GatewayState.disconnected);
      expect(factory.connections, hasLength(1));

      socket.ensureConnected();
      await pump();

      expect(factory.connections, hasLength(2));
      expect(socket.state, GatewayState.connected);
      await socket.dispose();
    });

    test('resumes the previous session when one is held', () async {
      final factory = FakeConnectionFactory();
      final socket = makeExhaustedSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'seq': 3,
        'data': {'session_id': 'S1'},
      }));
      await pump();

      factory.last.simulateClose(1006);
      await pump();
      socket.ensureConnected();
      await pump();
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 60000},
      }));
      await pump();

      final sent = lastSent(factory.last);
      expect(sent['op'], GatewayOpcodes.resume);
      expect(sent['data']['session_id'], 'S1');
      expect(sent['data']['seq'], 3);
      await socket.dispose();
    });

    test('force-closes a stale connection that misses the probe ack',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      expect(socket.state, GatewayState.connected);

      socket.ensureConnected();
      await pump(4);

      // The probe heartbeat went out, was never acked, and the dead socket was
      // closed and reopened through the normal reconnect path.
      final probe =
          jsonDecode(factory.connections.first.sent.last) as Map<String, dynamic>;
      expect(probe['op'], GatewayOpcodes.heartbeat);
      expect(factory.connections.first.closeCode, 4000);
      expect(factory.connections, hasLength(2));
      await socket.dispose();
    });

    test('leaves a live connection alone when the probe is acked', () async {
      final factory = FakeConnectionFactory();
      Completer<void>? gate;
      final socket = GatewaySocket(
        connectionFactory: factory.call,
        sleep: (_) {
          gate = Completer<void>();
          return gate!.future;
        },
        random: () => 0.0,
        token: 'tok',
        tokenType: 'Bot',
      );
      socket.setup(AccordConfig(), 'tok', tknType: 'Bot');
      socket.connectToGateway('ws://x');
      await pump();

      socket.ensureConnected();
      await pump();
      factory.last.receive(jsonEncode({'op': GatewayOpcodes.heartbeatAck}));
      await pump();
      gate!.complete();
      await pump();

      expect(factory.connections, hasLength(1));
      expect(socket.state, GatewayState.connected);
      await socket.dispose();
    });
  });
}
