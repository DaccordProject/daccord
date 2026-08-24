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

    test('caps a too-long server heartbeat interval', () async {
      // A 45s interval is longer than a typical ~30s middlebox idle timeout,
      // which culls the idle socket (close 1006) before the first beat fires.
      // The effective interval must be capped so a beat lands inside that window.
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 45000},
      }));
      await pump();

      expect(socket.heartbeatIntervalMs, AccordConfig.heartbeatIntervalMax);
      await socket.dispose();
    });

    test('raises a zero server heartbeat interval to the safe minimum',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 0},
      }));
      await pump();

      expect(socket.heartbeatIntervalMs, AccordConfig.heartbeatIntervalMin);
      await socket.dispose();
    });

    test('raises a negative server heartbeat interval to the safe minimum',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': -1000},
      }));
      await pump();

      expect(socket.heartbeatIntervalMs, AccordConfig.heartbeatIntervalMin);
      await socket.dispose();
    });

    test('keeps a server heartbeat interval already under the cap', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 10000},
      }));
      await pump();

      expect(socket.heartbeatIntervalMs, 10000);
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

    test('call.ring emits a typed AccordCallSignal', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      final rings = <AccordCallSignal>[];
      socket.onCallRing.listen(rings.add);

      socket.connectToGateway('ws://x');
      await pump();

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'call.ring',
        'data': {
          'channel_id': '5',
          'caller_id': '9',
          'participants': ['9', '2'],
          'metadata': {'video': true},
        },
      }));
      await pump();

      expect(rings.single.type, 'ring');
      expect(rings.single.channelId, '5');
      expect(rings.single.callerId, '9');
      expect(rings.single.participants, ['9', '2']);
      expect(rings.single.metadata, {'video': true});
      await socket.dispose();
    });

    test('call.decline / cancel / end emit typed signals', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      final events = <AccordCallSignal>[];
      socket.onCallDecline.listen(events.add);
      socket.onCallCancel.listen(events.add);
      socket.onCallEnd.listen(events.add);

      socket.connectToGateway('ws://x');
      await pump();

      for (final type in ['call.decline', 'call.cancel', 'call.end']) {
        factory.last.receive(jsonEncode({
          'op': GatewayOpcodes.event,
          'type': type,
          'data': {'channel_id': '5', 'user_id': '2'},
        }));
      }
      await pump();

      expect(events.map((e) => e.type), ['decline', 'cancel', 'end']);
      expect(events.every((e) => e.channelId == '5' && e.userId == '2'), isTrue);
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

      // DM/group DM calls have no parent space. The server resolves the scope
      // from the channel, so a null space_id is the payload for a DM call —
      // not a reason to withhold the update.
      socket.updateVoiceState(null, '5', selfMute: true, selfDeaf: true);
      expect(lastSent(conn)['op'], GatewayOpcodes.voiceStateUpdate);
      expect(lastSent(conn)['data']['space_id'], isNull);
      expect(lastSent(conn)['data']['channel_id'], '5');
      expect(lastSent(conn)['data']['self_mute'], true);
      expect(lastSent(conn)['data']['self_deaf'], true);

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

      // Establish a session. `resumable` is what licenses the RESUME below —
      // without it the socket re-identifies instead (#208).
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'S1', 'resumable': true},
      }));
      await pump();
      expect(socket.resumeSupported, isTrue);

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

    test('re-identifies against a server that never advertised resume',
        () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();

      // A plain READY — no `resumable`, no `capabilities`. accordserver's
      // pre-identify loop ignores op 3 entirely, so a speculative RESUME would
      // idle until its 30-second identify timeout with us broadcast offline
      // the whole time (#208).
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'S1'},
      }));
      await pump();
      expect(socket.resumeSupported, isFalse);

      factory.last.simulateClose(1006);
      await pump();

      // The stale session is dropped up front rather than gambled on, so the
      // reconnect opens as a plain connect (never `resuming`).
      expect(socket.sessionId, '');
      expect(socket.state, isNot(GatewayState.resuming));

      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 60000},
      }));
      await pump();

      expect(lastSent(factory.last)['op'], GatewayOpcodes.identify);
      await socket.dispose();
    });

    test('a HELLO capability list also enables resuming', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      socket.connectToGateway('ws://x');
      await pump();
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {
          'heartbeat_interval': 60000,
          'capabilities': ['resume'],
        },
      }));
      await pump();
      expect(socket.resumeSupported, isTrue);
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.event,
        'type': 'ready',
        'data': {'session_id': 'S1'},
      }));
      await pump();

      factory.last.simulateClose(1006);
      await pump();
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 60000},
      }));
      await pump();

      expect(lastSent(factory.last)['op'], GatewayOpcodes.resume);
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

  group('backoff', () {
    /// Drives [rounds] connect → READY → die cycles, holding each session up
    /// for [sessionLifetime] on the injected clock, and returns the delay the
    /// socket waited before each reconnect.
    Future<List<int>> flap({
      required int rounds,
      required Duration sessionLifetime,
    }) async {
      final delays = <Duration>[];
      var clock = DateTime.utc(2024);
      final factory = FakeConnectionFactory();
      final socket = GatewaySocket(
        connectionFactory: factory.call,
        sleep: (d) async {
          delays.add(d);
        },
        random: () => 0.0,
        now: () => clock,
        token: 'tok',
        tokenType: 'Bot',
      );
      socket.setup(AccordConfig(), 'tok', intentList: ['messages']);
      socket.connectToGateway('ws://x');
      await pump();

      for (var i = 0; i < rounds; i++) {
        factory.last.receive(jsonEncode({
          'op': GatewayOpcodes.event,
          'type': 'ready',
          'data': {'session_id': 'S$i'},
        }));
        await pump();
        clock = clock.add(sessionLifetime);
        factory.last.simulateClose(1006);
        await pump();
      }
      await socket.dispose();
      return [for (final d in delays) d.inMilliseconds];
    }

    test('escalates when the session keeps dying before it is stable',
        () async {
      // The #208 cadence: READY, alive for five seconds, dead. The budget used
      // to be reset on READY, so this looped at 1–2s forever — one visible
      // offline/online flip per cycle for everyone watching the roster.
      expect(
        await flap(rounds: 4, sessionLifetime: const Duration(seconds: 5)),
        [1000, 2000, 4000, 8000],
      );
    });

    test('a session that stays up past the threshold earns the budget back',
        () async {
      expect(
        await flap(rounds: 3, sessionLifetime: const Duration(seconds: 45)),
        [1000, 1000, 1000],
      );
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

    test('is a no-op when the handshake is still in progress', () async {
      final factory = FakeConnectionFactory();
      final socket = makeSocket(factory);
      // Start connecting but don't pump — the socket is in the 'connecting'
      // state (ready future hasn't resolved yet).
      socket.connectToGateway('ws://x');

      socket.ensureConnected();
      await pump();

      // Still only the one connection; no probe heartbeat was sent.
      expect(factory.connections, hasLength(1));
      expect(socket.state, GatewayState.connected);
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
        'data': {'session_id': 'S1', 'resumable': true},
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

    test('heartbeat timer does not race with probe during ack window', () async {
      // Verify that the probe stops the heartbeat timer before sending its OOB
      // heartbeat, so a timer tick mid-probe can't close a live connection that
      // hasn't had time to ACK yet.
      final factory = FakeConnectionFactory();
      Completer<void>? sleepGate;
      final socket = GatewaySocket(
        connectionFactory: factory.call,
        sleep: (_) {
          sleepGate = Completer<void>();
          return sleepGate!.future;
        },
        random: () => 0.0,
        token: 'tok',
        tokenType: 'Bot',
        probeTimeout: const Duration(seconds: 5),
      );
      socket.setup(AccordConfig(), 'tok', tknType: 'Bot');
      socket.connectToGateway('ws://x');
      await pump();

      // Receive HELLO so the heartbeat timer starts.
      factory.last.receive(jsonEncode({
        'op': GatewayOpcodes.hello,
        'data': {'heartbeat_interval': 30000},
      }));
      await pump();

      // Start a probe — it should stop the heartbeat timer immediately.
      socket.ensureConnected();
      await pump();

      // Simulate an ACK arriving before the probe timeout.
      factory.last.receive(jsonEncode({'op': GatewayOpcodes.heartbeatAck}));
      await pump();

      // Complete the probe sleep.
      sleepGate!.complete();
      await pump();

      // Connection still intact; no second connection was opened.
      expect(factory.connections, hasLength(1));
      expect(socket.state, GatewayState.connected);
      await socket.dispose();
    });
  });
}
