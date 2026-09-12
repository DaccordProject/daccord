import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/messaging/views/message_pane/message_pane.dart';
import 'package:bonfire/features/profiles/controllers/profiles_controller.dart';
import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/user/views/accord_direct_messages.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/incoming_call_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/shared/components/app_shell.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The caller's side of a DM call (#324).
///
/// Placing a call used to leave the caller on a white screen. `main.dart`
/// booted a bare bootstrap `MaterialApp(home: ProfileGate(...))` *around* the
/// themed router app, so the DM conversation's `rootNavigator: true` lookup
/// climbed past the router into that outer navigator and `showFullScreenVoice`
/// pushed the call view there — where `BonfireThemeExtension.of` finds no
/// extension and throws (a blank error widget in release). These tests drive
/// the real conversation header through the real [CallController] inside the
/// production app shell ([buildAppShell]), logged in against a [MockClient].

const _selfId = 'u1';
final _server = AccordServer.fromBaseUrl('https://accord.example.test');
final _session = AccordSession(
  server: _server,
  token: 'test-token',
  userId: _selfId,
  username: 'self',
);
final _serverKey = _session.key;
final _dm = AccordChannel(
  id: 'dm1',
  type: 'dm',
  recipients: [AccordUser(id: 'u2', username: 'alice', displayName: 'Alice')],
);

class _FakeAuth extends AccordAuth {
  _FakeAuth(this._client);

  final AccordClient _client;

  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: _client, session: _session);

  @override
  AccordClient? clientForKey(String key) => key == _serverKey ? _client : null;
}

class _ActiveConnections extends ConnectionsController {
  @override
  ConnectionsState build() => ConnectionsState(activeKey: _serverKey);
}

/// A [VoiceController] that never touches LiveKit: joining pins the connection
/// exactly as the real one does, or fails with [failJoinWith] the way a
/// rejected `POST /channels/{id}/voice/join` does.
class _StubVoice extends VoiceController {
  _StubVoice({
    this.initial = const VoiceConnection(),
    this.failJoinWith,
    String? joinServerKey,
  }) : joinServerKey = joinServerKey ?? _serverKey;

  final VoiceConnection initial;
  final String? failJoinWith;

  /// The connection the join pins to. Defaults to the harness's own server;
  /// set to something [_FakeAuth] doesn't recognise to simulate the
  /// connection disappearing between the join resolving and the ring going
  /// out (`_clientFor` then finds no client for it).
  final String joinServerKey;
  int leaves = 0;

  @override
  VoiceConnection build() => initial;

  @override
  Future<void> join(String channelId, String? spaceId) async {
    final error = failJoinWith;
    if (error != null) {
      state = state.copyWith(error: error);
      return;
    }
    state = state.copyWith(
      channelId: channelId,
      spaceId: spaceId,
      serverKey: joinServerKey,
      clearError: true,
    );
  }

  @override
  Future<void> leave() async {
    leaves++;
    state = const VoiceConnection();
  }

  @override
  Future<void> toggleVideo() async {}
}

/// Both participants already in the DM call, so the connected body renders
/// tiles rather than "Connecting…".
class _SeededVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) => {
    'dm1': {
      'u1': AccordVoiceState(userId: 'u1', channelId: 'dm1'),
      'u2': AccordVoiceState(userId: 'u2', channelId: 'dm1'),
    },
  };
}

class _FakeDmChannels extends DmChannelsController {
  @override
  List<AccordChannel>? build(String serverKey) => [_dm];
}

/// The chat panel is the real [MessagePane], whose rows read local preferences
/// from a Hive box only `setupHive()` opens; in-memory defaults keep the tests
/// off disk.
class _FakeSettings extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

/// The production shell hosts the device-profile gate; keep it off Hive too.
class _NoProfiles extends ProfilesController {
  @override
  List<DeviceProfile> build() => const [];

  @override
  DeviceProfile? get active => null;
}

class _SilentRingtone implements CallRingtone {
  @override
  void start({bool outgoing = false}) {}

  @override
  void stop() {}
}

class _Harness {
  _Harness({
    _StubVoice? voice,
    this.ringStatus = 200,
    this.ringBody = '{"data":{"ok":true}}',
  }) : voice = voice ?? _StubVoice() {
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: _server.baseUrl,
      gatewayUrl: _server.gatewayUrl,
      cdnUrl: _server.cdnUrl,
      httpClient: MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        const json = {'content-type': 'application/json'};
        if (request.url.path.endsWith('/call/ring')) {
          return http.Response(ringBody, ringStatus, headers: json);
        }
        final body = request.method == 'GET' ? '[]' : '{}';
        return http.Response(body, 200, headers: json);
      }),
    );
  }

  final _StubVoice voice;
  final int ringStatus;
  final String ringBody;
  final List<String> requests = [];
  late final AccordClient client;

  /// The app exactly as `main.dart` composes it: one themed [MaterialApp]
  /// whose builder is [buildAppShell], and nothing above it.
  Widget app(Widget home) => ProviderScope(
    overrides: [
      accordAuthProvider.overrideWith(() => _FakeAuth(client)),
      connectionsControllerProvider.overrideWith(_ActiveConnections.new),
      settingsControllerProvider.overrideWith(_FakeSettings.new),
      profilesControllerProvider.overrideWith(_NoProfiles.new),
      voiceControllerProvider.overrideWith(() => voice),
      voiceStatesControllerProvider(
        _serverKey,
      ).overrideWith(_SeededVoiceStates.new),
      dmChannelsControllerProvider(
        _serverKey,
      ).overrideWith(_FakeDmChannels.new),
      callRingtoneProvider.overrideWithValue(_SilentRingtone()),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      builder: (context, child) =>
          buildAppShell(context, child, uiScale: 1, reducedMotion: false),
      home: home,
    ),
  );

  /// A home screen with a button that opens the DM conversation the way the
  /// rail does — a dialog on the root navigator.
  Widget dmHome() => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showAccordDirectMessages(context, initialChannel: _dm),
        child: const Text('open dm'),
      ),
    ),
  );
}

/// The call view holds a progress indicator while ringing, so it never
/// settles; fixed pumps stand in for `pumpAndSettle`.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openConversation(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  addTearDown(h.client.dispose);
  await tester.pumpWidget(h.app(h.dmHome()));
  await tester.tap(find.text('open dm'));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Start voice call'), findsOneWidget);
}

/// The in-call control bar's hang-up button, scoped to the call view because
/// the incoming-call banner's decline button shares the icon.
final _hangUp = find.descendant(
  of: find.byType(VoiceChannelView),
  matching: find.byIcon(Icons.call_end),
);

final _decline = find.descendant(
  of: find.byType(IncomingCallOverlay),
  matching: find.byTooltip('Decline'),
);

void main() {
  testWidgets('placing a DM call opens the themed call view over the '
      'conversation, then returns to it on hang-up', (tester) async {
    final h = _Harness();
    await _openConversation(tester, h);

    await tester.tap(find.byTooltip('Start voice call'));
    await _settle(tester);

    // The white screen: the call view threw building on the bootstrap app's
    // extension-less theme.
    expect(tester.takeException(), isNull);
    final view = find.byType(VoiceChannelView);
    expect(view, findsOneWidget);
    expect(
      Theme.of(tester.element(view)).extension<BonfireThemeExtension>(),
      isNotNull,
      reason: 'the call view must be pushed inside the themed app',
    );

    // Joined, then rung — and the view reflects both.
    expect(h.requests, contains('POST /api/v1/channels/dm1/call/ring'));
    expect(find.text('Calling Alice…'), findsOneWidget);
    expect(_hangUp, findsOneWidget);
    // Full-screen opens with the chat panel, which is the real message pane.
    expect(find.byType(MessagePane), findsWidgets);

    // Hanging up while still ringing cancels the call, and ending the call
    // pops the view back to the conversation it was placed from.
    await tester.tap(_hangUp);
    // Once the call view has popped nothing is left animating, so the route's
    // exit transition can be waited out rather than pumped by hand.
    await tester.pumpAndSettle();
    expect(h.requests, contains('POST /api/v1/channels/dm1/call/cancel'));
    expect(h.voice.leaves, 1);
    expect(find.byType(VoiceChannelView), findsNothing);
    expect(find.byTooltip('Start voice call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a second call ringing in stays answerable above the call view '
      'and the conversation dialog', (tester) async {
    final h = _Harness();
    await _openConversation(tester, h);
    await tester.tap(find.byTooltip('Start voice call'));
    await _settle(tester);
    expect(find.byType(VoiceChannelView), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VoiceChannelView)),
    );
    container
        .read(callControllerProvider.notifier)
        .handleRing(
          const AccordCallSignal(
            type: 'ring',
            channelId: 'dm2',
            callerId: 'u3',
            participants: ['u1', 'u3'],
          ),
          _serverKey,
          _selfId,
        );
    await _settle(tester);

    // Both the dialog route and the call route are pages on the app's root
    // navigator; the banner host sits above that navigator, so it is on top.
    expect(_decline, findsOneWidget);
    expect(_decline.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the full-screen DM call view renders with its chat panel open', (
    tester,
  ) async {
    // The second shape of the report: the view itself, presented full-screen
    // for a DM (no space) — its chat panel builds a MessagePane with no
    // channel object and no space, which must not be a problem.
    final h = _Harness(
      voice: _StubVoice(
        initial: VoiceConnection(channelId: 'dm1', serverKey: _serverKey),
      ),
    );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(h.client.dispose);

    await tester.pumpWidget(
      h.app(
        const Scaffold(
          body: SafeArea(
            child: VoiceChannelView(
              channelId: 'dm1',
              spaceId: null,
              channelName: 'Alice',
              fullScreen: true,
            ),
          ),
        ),
      ),
    );
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(MessagePane), findsOneWidget);
    expect(find.byTooltip('Close chat'), findsOneWidget);
    expect(_hangUp, findsOneWidget);
    // Connected but not ringing: no "Calling…" banner.
    expect(find.textContaining('Calling'), findsNothing);
    // Both participants have a tile.
    expect(find.text('Alice'), findsWidgets);
  });

  testWidgets('a rejected voice join is reported on the conversation and '
      'never rings', (tester) async {
    final h = _Harness(
      voice: _StubVoice(failJoinWith: 'Voice backend unavailable'),
    );
    await _openConversation(tester, h);

    await tester.tap(find.byTooltip('Start voice call'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.byType(VoiceChannelView), findsNothing);
    // Join must succeed before the ring goes out.
    expect(h.requests, isNot(contains('POST /api/v1/channels/dm1/call/ring')));
    expect(find.text('Voice backend unavailable'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byTooltip('Start voice call')),
    );
    expect(container.read(callControllerProvider).hasOutgoing, isFalse);
  });

  testWidgets('a rejected ring hangs the call up and says why', (tester) async {
    final h = _Harness(
      ringStatus: 400,
      ringBody:
          '{"error":{"code":"channel_not_dm","message":"Not a DM channel"}}',
    );
    await _openConversation(tester, h);

    await tester.tap(find.byTooltip('Start voice call'));
    await _settle(tester);

    expect(tester.takeException(), isNull);
    // Nobody is being rung, so there is no call to show.
    expect(find.byType(VoiceChannelView), findsNothing);
    expect(h.voice.leaves, 1);
    expect(find.text('Not a DM channel'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byTooltip('Start voice call')),
    );
    expect(container.read(callControllerProvider).hasOutgoing, isFalse);
    expect(container.read(voiceControllerProvider).channelId, isNull);
  });

  testWidgets(
    'a connection that vanishes right after a successful join hangs the '
    'call up instead of ringing',
    (tester) async {
      // The join is pinned to a serverKey no client exists for by the time it
      // resolves — the connection was dropped mid-join. `_clientFor` then
      // returns null and `startCall` must not fall through to ringing on
      // whatever connection happens to be active now.
      final h = _Harness(voice: _StubVoice(joinServerKey: 'gone@nowhere'));
      await _openConversation(tester, h);

      await tester.tap(find.byTooltip('Start voice call'));
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(VoiceChannelView), findsNothing);
      expect(
        h.requests,
        isNot(contains('POST /api/v1/channels/dm1/call/ring')),
      );
      expect(h.voice.leaves, 1);
      expect(
        find.text('Could not start the call — no connection'),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byTooltip('Start voice call')),
      );
      expect(container.read(callControllerProvider).hasOutgoing, isFalse);
    },
  );
}
