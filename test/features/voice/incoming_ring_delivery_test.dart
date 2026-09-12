import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/profiles/controllers/profiles_controller.dart';
import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/incoming_call_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/router/controller.dart' show rootNavigatorKey;
import 'package:bonfire/shared/components/app_shell.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:bonfire/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The callee's side of a DM call (#324): a `call.ring` frame shaped exactly
/// like accordserver's (`routes/voice.rs` `ring_call`, broadcast under the
/// `voice_states` intent) travels through the real [AccordClient] gateway, the
/// app's event handler and [CallController] to the banner hosted by the
/// production app shell — and accepting it opens the themed call view.

const _selfId = 'u1';
const _callerId = 'u2';
final _server = AccordServer.fromBaseUrl('https://accord.example.test');
final _session = AccordSession(
  server: _server,
  token: 'test-token',
  userId: _selfId,
  username: 'self',
);
final _serverKey = _session.key;
final _refProvider = Provider<Ref>((ref) => ref);

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

class _FakeAuth extends AccordAuth {
  _FakeAuth(this._client);

  final AccordClient _client;

  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: _client, session: _session);

  @override
  AccordClient? clientForKey(String key) => key == _serverKey ? _client : null;
}

class _Connections extends ConnectionsController {
  _Connections(this.activeKey);

  final String activeKey;

  @override
  ConnectionsState build() => ConnectionsState(activeKey: activeKey);
}

class _StubVoice extends VoiceController {
  _StubVoice([this.initial = const VoiceConnection()]);

  final VoiceConnection initial;

  @override
  VoiceConnection build() => initial;

  @override
  Future<void> join(String channelId, String? spaceId) async {
    state = state.copyWith(
      channelId: channelId,
      spaceId: spaceId,
      serverKey: _serverKey,
    );
  }

  @override
  Future<void> leave() async => state = const VoiceConnection();
}

class _NoVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build(String serverKey) =>
      const {};
}

class _FakeSettings extends SettingsController {
  @override
  AccordSettings build() =>
      const AccordSettings(notificationsEnabled: false, soundsEnabled: false);
}

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

/// The frame accordserver broadcasts to every DM participant (caller included)
/// when someone rings: `{op: 0, type: "call.ring", data: {...}}`, with a null
/// `metadata` when the caller sent no body.
Map<String, dynamic> _ringFrame({
  String channelId = 'dm1',
  String callerId = _callerId,
  Object? metadata = const {'video': false},
}) => {
  'op': GatewayOpcodes.event,
  'type': 'call.ring',
  'data': {
    'channel_id': channelId,
    'caller_id': callerId,
    'participants': [_selfId, callerId],
    'metadata': metadata,
  },
};

class _Harness {
  _Harness({
    String? activeKey,
    bool isActive = true,
    VoiceConnection voice = const VoiceConnection(),
  }) {
    client = AccordClient(
      token: 'test-token',
      tokenType: 'Bearer',
      baseUrl: _server.baseUrl,
      gatewayUrl: _server.gatewayUrl,
      cdnUrl: _server.cdnUrl,
      connectionFactory: (_) => connection,
      httpClient: MockClient((request) async {
        const json = {'content-type': 'application/json'};
        if (request.url.path.endsWith('/users/$_callerId')) {
          return http.Response(
            jsonEncode({
              'id': _callerId,
              'username': 'alice',
              'display_name': 'Alice',
            }),
            200,
            headers: json,
          );
        }
        final body = request.method == 'GET' ? '[]' : '{}';
        return http.Response(body, 200, headers: json);
      }),
    );
    container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(() => _FakeAuth(client)),
        connectionsControllerProvider.overrideWith(
          () => _Connections(activeKey ?? _serverKey),
        ),
        settingsControllerProvider.overrideWith(_FakeSettings.new),
        profilesControllerProvider.overrideWith(_NoProfiles.new),
        voiceControllerProvider.overrideWith(() => _StubVoice(voice)),
        voiceStatesControllerProvider(
          _serverKey,
        ).overrideWith(_NoVoiceStates.new),
        callRingtoneProvider.overrideWithValue(_SilentRingtone()),
      ],
    );
    // Wired exactly as AccordAuth wires each connection.
    dispose = handleAccordEvents(
      container.read(_refProvider),
      client,
      serverKey: _serverKey,
      currentUserId: _selfId,
      selfDomain: _server.homeDomain,
      isActive: () => isActive,
    );
  }

  final connection = _FakeGatewayConnection();
  late final AccordClient client;
  late final ProviderContainer container;
  late final VoidCallback dispose;

  CallState get callState => container.read(callControllerProvider);

  Future<void> login() async {
    client.login();
    await Future<void>.delayed(Duration.zero);
  }

  void tearDown() {
    dispose();
    container.dispose();
    client.dispose();
  }

  /// The app as `main.dart` composes it, keyed with the router's root
  /// navigator so the banner's accept can open the call view.
  Widget app(Widget home) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      navigatorKey: rootNavigatorKey,
      theme: buildAppTheme(AppThemePreset.dark),
      builder: (context, child) =>
          buildAppShell(context, child, uiScale: 1, reducedMotion: false),
      home: home,
    ),
  );
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

final _accept = find.descendant(
  of: find.byType(IncomingCallOverlay),
  matching: find.byTooltip('Accept'),
);
final _decline = find.descendant(
  of: find.byType(IncomingCallOverlay),
  matching: find.byTooltip('Decline'),
);

void main() {
  test('a server-shaped call.ring lands in the call state', () async {
    final h = _Harness();
    addTearDown(h.tearDown);
    await h.login();

    h.connection.receive(_ringFrame());
    await Future<void>.delayed(Duration.zero);

    final incoming = h.callState.incoming;
    expect(incoming, isNotNull);
    expect(incoming!.channelId, 'dm1');
    expect(incoming.callerId, _callerId);
    expect(incoming.participants, [_selfId, _callerId]);
    expect(incoming.video, isFalse);
    // Accept/decline must route back through the connection it rang on.
    expect(incoming.serverKey, _serverKey);
  });

  test('a ring without metadata (no request body) still rings', () async {
    final h = _Harness();
    addTearDown(h.tearDown);
    await h.login();

    h.connection.receive(_ringFrame(metadata: null));
    await Future<void>.delayed(Duration.zero);

    expect(h.callState.incoming?.channelId, 'dm1');
    expect(h.callState.incoming?.video, isFalse);
  });

  test('a ring on a background connection still rings', () async {
    // The user is browsing another server; the DM lives on this one. The
    // server targets DM participants directly, so the ring must not be
    // gated on which connection is active.
    final h = _Harness(
      activeKey: 'someone@https://other.example',
      isActive: false,
    );
    addTearDown(h.tearDown);
    await h.login();

    h.connection.receive(_ringFrame());
    await Future<void>.delayed(Duration.zero);

    expect(h.callState.incoming?.channelId, 'dm1');
    expect(h.callState.incoming?.serverKey, _serverKey);
  });

  test('the caller\'s own echo of the ring is ignored', () async {
    // accordserver broadcasts call.ring to every participant, the caller too.
    final h = _Harness(
      voice: VoiceConnection(channelId: 'dm1', serverKey: _serverKey),
    );
    addTearDown(h.tearDown);
    await h.login();

    h.connection.receive(_ringFrame(callerId: _selfId));
    await Future<void>.delayed(Duration.zero);

    expect(h.callState.incoming, isNull);
  });

  test('a ring for the call we are already in is ignored', () async {
    final h = _Harness(
      voice: VoiceConnection(channelId: 'dm1', serverKey: _serverKey),
    );
    addTearDown(h.tearDown);
    await h.login();

    // Another participant of a group DM we already joined rings it again.
    h.connection.receive(_ringFrame(callerId: 'u3'));
    await Future<void>.delayed(Duration.zero);

    expect(h.callState.incoming, isNull);
  });

  testWidgets('the ring shows the banner in the app shell, over a dialog, and '
      'accepting opens the themed call view', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final h = _Harness();
    addTearDown(h.tearDown);
    // Inside testWidgets' fake-async zone the gateway handshake advances on
    // pumps, not on a real `Future.delayed`.
    h.client.login();
    await tester.pump();

    await tester.pumpWidget(
      h.app(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const AlertDialog(title: Text('Direct messages')),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    // The callee is sitting in a dialog (on mobile the DM conversation *is*
    // one) — the case the outer bootstrap navigator used to hide the banner in.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Direct messages'), findsOneWidget);

    h.connection.receive(_ringFrame());
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Alice'), findsOneWidget);
    expect(_decline.hitTestable(), findsOneWidget);
    expect(_accept.hitTestable(), findsOneWidget);

    await tester.tap(_accept);
    await _pump(tester);

    expect(tester.takeException(), isNull);
    expect(h.callState.incoming, isNull);
    expect(h.container.read(voiceControllerProvider).channelId, 'dm1');
    final view = find.byType(VoiceChannelView);
    expect(view, findsOneWidget);
    expect(
      Theme.of(tester.element(view)).extension<BonfireThemeExtension>(),
      isNotNull,
      reason: 'the call view must open inside the themed app',
    );
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });
}
