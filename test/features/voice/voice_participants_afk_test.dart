import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_participants.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for the AFK badge on a voice participant row (#112).
const _channelId = 'c1';
const _selfId = 'u-self';
const _otherId = 'u-other';

class _FakeVoiceController extends VoiceController {
  _FakeVoiceController(this._state);
  final VoiceConnection _state;
  @override
  VoiceConnection build() => _state;
}

class _FakeVoiceStates extends VoiceStatesController {
  _FakeVoiceStates(this._states);
  final Map<String, Map<String, AccordVoiceState>> _states;
  @override
  Map<String, Map<String, AccordVoiceState>> build() => _states;
}

AccordVoiceState _state(String userId) =>
    AccordVoiceState(userId: userId, channelId: _channelId);

final _finder = find.byKey(const Key('voice-participant-afk'));

/// A logged-in scope hosting just the participant list. The client is never
/// used by these widgets (no request is issued) — it only exists because
/// [AccordAuthLoggedIn] carries one, and it is what supplies `_selfId`.
Widget _host({
  required VoiceConnection voice,
  Map<String, AccordPresence> presences = const {},
  List<String> userIds = const [_selfId, _otherId],
}) {
  final server = AccordServer.fromBaseUrl('https://accord.example.test');
  final client = AccordClient(
    token: 'test-token',
    tokenType: 'Bearer',
    baseUrl: server.baseUrl,
    gatewayUrl: server.gatewayUrl,
    cdnUrl: server.cdnUrl,
  );
  addTearDown(client.dispose);
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(
        AccordAuthLoggedIn(
          client: client,
          session: AccordSession(
            server: server,
            token: 'test-token',
            userId: _selfId,
            username: 'self',
          ),
        ),
      ),
      voiceControllerProvider.overrideWith(() => _FakeVoiceController(voice)),
      voiceStatesControllerProvider.overrideWith(
        () => _FakeVoiceStates({
          _channelId: {for (final id in userIds) id: _state(id)},
        }),
      ),
      activePresencesProvider.overrideWithValue(PresenceMap(byUser: presences)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: const Scaffold(
        body: VoiceParticipantList(channelId: _channelId, spaceId: null),
      ),
    ),
  );
}

void main() {
  testWidgets('no AFK badge while everyone is active', (tester) async {
    await tester.pumpWidget(
      _host(
        voice: const VoiceConnection(channelId: _channelId),
        presences: {
          _selfId: AccordPresence(userId: _selfId, status: 'online'),
          _otherId: AccordPresence(userId: _otherId, status: 'online'),
        },
      ),
    );
    await tester.pump();

    expect(find.text(_selfId), findsOneWidget);
    expect(_finder, findsNothing);
  });

  testWidgets('our own row badges as soon as the voice controller says AFK', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        // No presence entry yet — the local flag must not wait on the
        // presence round-trip.
        voice: const VoiceConnection(channelId: _channelId, isAfk: true),
        userIds: const [_selfId],
      ),
    );
    await tester.pump();

    expect(_finder, findsOneWidget);
  });

  testWidgets('a remote member badges from their idle presence', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        voice: const VoiceConnection(channelId: _channelId),
        presences: {
          _selfId: AccordPresence(userId: _selfId, status: 'online'),
          _otherId: AccordPresence(userId: _otherId, status: 'idle'),
        },
      ),
    );
    await tester.pump();

    // Exactly one of the two rows is badged, and it's the idle one.
    expect(_finder, findsOneWidget);
    final row = find.ancestor(of: _finder, matching: find.byType(Row)).first;
    expect(
      find.descendant(of: row, matching: find.text(_otherId)),
      findsOneWidget,
    );
  });

  testWidgets('the badged row is dimmed', (tester) async {
    await tester.pumpWidget(
      _host(
        voice: const VoiceConnection(channelId: _channelId, isAfk: true),
        userIds: const [_selfId],
      ),
    );
    await tester.pump();

    final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacity.opacity, lessThan(1.0));
  });

  testWidgets('our AFK flag is ignored for a channel we are not in', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        voice: const VoiceConnection(channelId: 'some-other-channel', isAfk: true),
        userIds: const [_selfId],
      ),
    );
    await tester.pump();

    expect(_finder, findsNothing);
  });
}
