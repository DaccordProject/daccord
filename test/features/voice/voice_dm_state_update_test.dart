import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [GatewayConnection] that records every frame the socket sends, so a test
/// can assert on the outbound wire payload without real networking.
class _FakeGatewayConnection implements GatewayConnection {
  final _messages = StreamController<String>();
  final List<String> sent = [];

  @override
  Future<void> get ready => Future.value();

  @override
  Stream<String> get messages => _messages.stream;

  @override
  void sendText(String text) => sent.add(text);

  @override
  Future<void> close([int? code, String? reason]) async {
    if (!_messages.isClosed) await _messages.close();
  }

  @override
  int? closeCode;

  @override
  String? closeReason;
}

/// Hands out a single [_FakeGatewayConnection] regardless of the requested URL.
class _FakeConnectionFactory {
  final connection = _FakeGatewayConnection();
  GatewayConnection call(String url) => connection;
}

/// Routes [VoiceController._client] to a client wired to a fake gateway
/// connection instead of a real login.
class _FakeAccordAuth extends AccordAuth {
  _FakeAccordAuth.single(AccordClient client)
    : _clients = {'server-key': client};

  _FakeAccordAuth.clients(this._clients);

  final Map<String, AccordClient> _clients;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  AccordClient? clientForKey(String key) => _clients[key];
}

/// A [VoiceController] that starts out connected to a DM call (no space) on
/// the fake connection's key, without ever touching LiveKit.
class _DmConnectedVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection(
    channelId: 'dm-channel',
    spaceId: null,
    serverKey: 'server-key',
  );
}

/// A [VoiceController] connected to a space (non-DM) voice channel, for
/// contrast against the DM case.
class _SpaceConnectedVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection(
    channelId: 'space-channel',
    spaceId: 'space-1',
    serverKey: 'server-key',
  );
}

/// Models the user browsing a different server while the DM call remains
/// pinned to `server-key`.
class _OtherActiveConnections extends ConnectionsController {
  @override
  ConnectionsState build() => const ConnectionsState(activeKey: 'other-server');
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

Map<String, dynamic> _lastSent(_FakeGatewayConnection c) =>
    jsonDecode(c.sent.last) as Map<String, dynamic>;

void main() {
  // setMute()/setDeafen() touch the global `soundManager` singleton, which
  // constructs an AudioPlayer that needs ServicesBinding.instance.
  TestWidgetsFlutterBinding.ensureInitialized();

  // ...and that AudioPlayer talks to audioplayers' platform channels, which
  // have no implementation under `flutter test`. The resulting
  // MissingPluginException surfaces asynchronously — often after the test
  // body has finished, failing the run with "failed after it had already
  // completed" — so answer the channels with a no-op instead.
  const audioChannels = [
    MethodChannel('xyz.luan/audioplayers.global'),
    MethodChannel('xyz.luan/audioplayers'),
  ];

  setUp(() {
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);
    }
  });

  tearDown(() {
    for (final channel in audioChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  group('mid-call self-state broadcast (#135)', () {
    test('setMute broadcasts over a DM call, where spaceId is null', () async {
      final factory = _FakeConnectionFactory();
      final client = AccordClient(
        baseUrl: 'https://test.example',
        gatewayUrl: 'wss://test.example/ws',
        connectionFactory: factory.call,
      );
      addTearDown(client.dispose);
      client.login();
      await pump();

      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(() => _FakeAccordAuth.single(client)),
          voiceControllerProvider.overrideWith(_DmConnectedVoiceController.new),
        ],
      );
      addTearDown(container.dispose);

      container.read(voiceControllerProvider.notifier).setMute(true);
      await pump();

      // The old guard bailed out here because `spaceId` was null — nothing
      // was ever sent and peers never saw the mute. It must now go out with
      // an explicit null `space_id`, not be withheld.
      final sent = _lastSent(factory.connection);
      expect(sent['op'], GatewayOpcodes.voiceStateUpdate);
      expect(sent['data']['space_id'], isNull);
      expect(sent['data']['channel_id'], 'dm-channel');
      expect(sent['data']['self_mute'], isTrue);
    });

    test(
      'setDeafen broadcasts DM state through the call-pinned client',
      () async {
        final callFactory = _FakeConnectionFactory();
        final otherFactory = _FakeConnectionFactory();
        final callClient = AccordClient(
          baseUrl: 'https://call.example',
          gatewayUrl: 'wss://call.example/ws',
          connectionFactory: callFactory.call,
        );
        final otherClient = AccordClient(
          baseUrl: 'https://other.example',
          gatewayUrl: 'wss://other.example/ws',
          connectionFactory: otherFactory.call,
        );
        addTearDown(callClient.dispose);
        addTearDown(otherClient.dispose);
        callClient.login();
        otherClient.login();
        await pump();
        callFactory.connection.sent.clear();
        otherFactory.connection.sent.clear();

        final container = ProviderContainer(
          overrides: [
            accordAuthProvider.overrideWith(
              () => _FakeAccordAuth.clients({
                'server-key': callClient,
                'other-server': otherClient,
              }),
            ),
            connectionsControllerProvider.overrideWith(
              _OtherActiveConnections.new,
            ),
            voiceControllerProvider.overrideWith(
              _DmConnectedVoiceController.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        final voice = container.read(voiceControllerProvider.notifier);
        voice.setMute(true);
        await pump();
        callFactory.connection.sent.clear();
        voice.setDeafen(true);
        await pump();

        final sent = _lastSent(callFactory.connection);
        expect(sent['op'], GatewayOpcodes.voiceStateUpdate);
        expect(sent['data']['space_id'], isNull);
        expect(sent['data']['channel_id'], 'dm-channel');
        expect(sent['data']['self_mute'], isTrue);
        expect(sent['data']['self_deaf'], isTrue);
        // Switching the app's visible server must not leak call state onto a
        // different authenticated session.
        expect(otherFactory.connection.sent, isEmpty);
      },
    );

    test(
      'setMute still carries the space id for a space voice channel',
      () async {
        final factory = _FakeConnectionFactory();
        final client = AccordClient(
          baseUrl: 'https://test.example',
          gatewayUrl: 'wss://test.example/ws',
          connectionFactory: factory.call,
        );
        addTearDown(client.dispose);
        client.login();
        await pump();

        final container = ProviderContainer(
          overrides: [
            accordAuthProvider.overrideWith(
              () => _FakeAccordAuth.single(client),
            ),
            voiceControllerProvider.overrideWith(
              _SpaceConnectedVoiceController.new,
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(voiceControllerProvider.notifier).setMute(true);
        await pump();

        final sent = _lastSent(factory.connection);
        expect(sent['data']['space_id'], 'space-1');
        expect(sent['data']['channel_id'], 'space-channel');
      },
    );
  });
}
