import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A [VoiceSession] stand-in that never touches LiveKit: `connect` just
/// records the call and reports whatever mic outcome the test configured, and
/// `setMicEnabled` answers an unmute with [unmuteError].
class _FakeSession extends VoiceSession {
  String? micErrorOnConnect;
  String? unmuteError;
  int connects = 0;
  bool? connectedMuted;
  final micToggles = <bool>[];

  @override
  String? get micError => micErrorOnConnect;

  @override
  Future<void> connect(
    String url,
    String token, {
    bool selfMute = false,
    bool selfDeaf = false,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    int outputVolume = 100,
    int inputVolume = 100,
  }) async {
    connects++;
    connectedMuted = selfMute;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<String?> setMicEnabled(bool enabled) async {
    micToggles.add(enabled);
    return enabled ? unmuteError : null;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeAccordAuth extends AccordAuth {
  _FakeAccordAuth(this._client);
  final AccordClient _client;

  @override
  AccordAuthState build() => const AccordAuthLoggedOut();

  @override
  AccordClient? clientForKey(String key) =>
      key == 'server-key' ? _client : null;
}

class _ActiveConnections extends ConnectionsController {
  @override
  ConnectionsState build() => const ConnectionsState(activeKey: 'server-key');
}

class _FixedSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// A [VoiceController] already sitting muted in a channel, for the unmute
/// cases.
class _MutedInCallVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection(
    channelId: 'c1',
    spaceId: 's1',
    serverKey: 'server-key',
    selfMute: true,
  );
}

/// Serves the REST voice join with LiveKit credentials and an empty list for
/// everything else (voice status, leave).
AccordClient _client() {
  final responder = MockClient((request) async {
    final isJoin =
        request.method == 'POST' &&
        request.url.path.endsWith('/channels/c1/voice/join');
    final body = isJoin
        ? jsonEncode({
            'space_id': 's1',
            'channel_id': 'c1',
            'backend': 'livekit',
            'livekit_url': 'wss://livekit.example',
            'token': 'lk-token',
          })
        : '[]';
    return http.Response(
      body,
      200,
      headers: {'content-type': 'application/json'},
    );
  });
  return AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: 'https://accord.example',
    gatewayUrl: 'wss://accord.example/ws',
    httpClient: responder,
  );
}

({ProviderContainer container, _FakeSession session}) _harness({
  VoiceController Function()? voice,
}) {
  final client = _client();
  addTearDown(client.dispose);
  final container = ProviderContainer(
    overrides: [
      accordAuthProvider.overrideWith(() => _FakeAccordAuth(client)),
      connectionsControllerProvider.overrideWith(_ActiveConnections.new),
      settingsControllerProvider.overrideWith(_FixedSettingsController.new),
      if (voice != null) voiceControllerProvider.overrideWith(voice),
    ],
  );
  addTearDown(container.dispose);
  final session = _FakeSession();
  container.read(voiceControllerProvider.notifier).debugSession = session;
  return (container: container, session: session);
}

Future<void> pump() => Future<void>.delayed(Duration.zero);

void main() {
  // join() arms the AFK monitor, which installs input hooks on the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => soundManager.setVoiceSessionActive(false));

  group('initial mic publish (#325)', () {
    test('a denied microphone joins muted with the reason surfaced', () async {
      final h = _harness();
      h.session.micErrorOnConnect = micPermissionDeniedMessage;

      await h.container.read(voiceControllerProvider.notifier).join('c1', 's1');

      final state = h.container.read(voiceControllerProvider);
      expect(h.session.connects, 1);
      expect(
        h.session.connectedMuted,
        isFalse,
        reason: 'the mic was asked for',
      );
      expect(state.isConnected, isTrue, reason: 'still in the channel');
      expect(state.selfMute, isTrue, reason: 'no live mic, so shown muted');
      expect(state.error, micPermissionDeniedMessage);
    });

    test('a published microphone joins live with no error', () async {
      final h = _harness();

      await h.container.read(voiceControllerProvider.notifier).join('c1', 's1');

      final state = h.container.read(voiceControllerProvider);
      expect(state.isConnected, isTrue);
      expect(state.selfMute, isFalse);
      expect(state.error, isNull);
    });
  });

  group('unmute', () {
    test(
      'an unmute the platform refuses reverts to muted and says why',
      () async {
        final h = _harness(voice: _MutedInCallVoiceController.new);
        h.session.unmuteError = 'Microphone unavailable: NotFoundError';

        h.container.read(voiceControllerProvider.notifier).setMute(false);
        await pump();

        final state = h.container.read(voiceControllerProvider);
        expect(h.session.micToggles, [true]);
        expect(state.selfMute, isTrue);
        expect(state.error, 'Microphone unavailable: NotFoundError');
      },
    );

    test('a successful unmute goes live', () async {
      final h = _harness(voice: _MutedInCallVoiceController.new);

      h.container.read(voiceControllerProvider.notifier).setMute(false);
      await pump();

      final state = h.container.read(voiceControllerProvider);
      expect(h.session.micToggles, [true]);
      expect(state.selfMute, isFalse);
      expect(state.error, isNull);
    });
  });

  group('sound manager call tracking (#323)', () {
    test('the live-session flag wraps join and leave', () async {
      final h = _harness();
      final voice = h.container.read(voiceControllerProvider.notifier);
      expect(soundManager.voiceSessionActive, isFalse);

      await voice.join('c1', 's1');
      expect(soundManager.voiceSessionActive, isTrue);

      await voice.leave();
      expect(soundManager.voiceSessionActive, isFalse);
      expect(h.container.read(voiceControllerProvider).isConnected, isFalse);
    });
  });
}
