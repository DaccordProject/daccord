import 'package:accordkit/accordkit.dart' show AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_text_panel.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [VoiceController] that records join/leave calls instead of talking to
/// LiveKit, so a test can prove that *opening* a voice channel connects nothing
/// (issue #202) and that the Join button is what actually connects.
class _RecordingVoiceController extends VoiceController {
  _RecordingVoiceController(this._initial);

  final VoiceConnection _initial;
  final List<(String, String?)> joins = [];
  int leaves = 0;

  @override
  VoiceConnection build() => _initial;

  @override
  Future<void> join(String channelId, String? spaceId) async {
    joins.add((channelId, spaceId));
    state = state.copyWith(channelId: channelId, spaceId: spaceId);
  }

  @override
  Future<void> leave() async {
    leaves++;
    state = const VoiceConnection();
  }
}

/// Seeds the who-is-in-which-channel cache without a gateway.
class _FakeVoiceStates extends VoiceStatesController {
  _FakeVoiceStates(this._seed);
  final Map<String, Map<String, AccordVoiceState>> _seed;
  @override
  Map<String, Map<String, AccordVoiceState>> build() => _seed;
}

/// The voice view's chat panel is the real [MessagePane], whose rows and
/// composer read local preferences — and the live [SettingsController] reads a
/// Hive box that only `setupHive()` opens. In-memory defaults keep these
/// widget tests off disk.
class _FakeSettingsController extends SettingsController {
  @override
  AccordSettings build() => const AccordSettings();
}

Widget _host({
  required _RecordingVoiceController voice,
  required String channelId,
  String? spaceId = 's1',
  Map<String, Map<String, AccordVoiceState>> voiceStates = const {},
}) {
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      voiceControllerProvider.overrideWith(() => voice),
      voiceStatesControllerProvider.overrideWith(
        () => _FakeVoiceStates(voiceStates),
      ),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: VoiceChannelView(
          channelId: channelId,
          spaceId: spaceId,
          channelName: 'general-voice',
        ),
      ),
    ),
  );
}

/// The in-call control bar's disconnect button — the marker for "we are
/// connected to the channel being viewed".
final _controlBar = find.byIcon(Icons.call_end);

void main() {
  testWidgets('opening a voice channel shows the lobby without connecting', (
    tester,
  ) async {
    final voice = _RecordingVoiceController(const VoiceConnection());
    await tester.pumpWidget(_host(voice: voice, channelId: 'c1'));
    await tester.pump();

    // Nothing was joined just by rendering the channel.
    expect(voice.joins, isEmpty);
    expect(voice.leaves, 0);
    // The lobby (Join button) is shown, and no call controls.
    expect(find.text('Join Voice'), findsOneWidget);
    expect(_controlBar, findsNothing);
    // The channel's text chat is visible by default in the lobby — reading a
    // voice channel without joining is the point of the change.
    expect(find.byType(VoiceTextPanel), findsOneWidget);
  });

  testWidgets('the lobby lists who is already in the channel', (tester) async {
    final voice = _RecordingVoiceController(const VoiceConnection());
    await tester.pumpWidget(
      _host(
        voice: voice,
        channelId: 'c1',
        voiceStates: {
          'c1': {'u1': AccordVoiceState(userId: 'u1', channelId: 'c1')},
        },
      ),
    );
    await tester.pump();

    expect(find.text('No one is here yet'), findsNothing);
    expect(find.text('Join Voice'), findsOneWidget);
    expect(voice.joins, isEmpty);
  });

  testWidgets('the Join button connects and reveals the call controls', (
    tester,
  ) async {
    final voice = _RecordingVoiceController(const VoiceConnection());
    await tester.pumpWidget(_host(voice: voice, channelId: 'c1'));
    await tester.pump();

    await tester.tap(find.text('Join Voice'));
    await tester.pump();

    expect(voice.joins, [('c1', 's1')]);
    expect(find.text('Join Voice'), findsNothing);
    expect(_controlBar, findsOneWidget);
  });

  testWidgets('viewing another voice channel while connected neither '
      'disconnects nor switches', (tester) async {
    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'c1', spaceId: 's1'),
    );
    await tester.pumpWidget(_host(voice: voice, channelId: 'c2'));
    await tester.pump();

    // Still in c1; the c2 view is only a lobby.
    expect(voice.joins, isEmpty);
    expect(voice.leaves, 0);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(VoiceChannelView)),
    );
    expect(container.read(voiceControllerProvider).channelId, 'c1');
    expect(find.text('Join Voice'), findsOneWidget);
    expect(_controlBar, findsNothing);
    // ...and the lobby says so, rather than implying we moved.
    expect(
      find.textContaining("You're connected to"),
      findsOneWidget,
    );
  });

  testWidgets('switching the view from a connected channel to another opens '
      'that channel’s lobby with its chat', (tester) async {
    // The message pane reuses one VoiceChannelView across channel switches, so
    // the per-channel defaults have to be re-derived on the swap.
    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'c1', spaceId: 's1'),
    );
    Widget host(String channelId) => ProviderScope(
      overrides: [
        accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
        settingsControllerProvider.overrideWith(_FakeSettingsController.new),
        voiceControllerProvider.overrideWith(() => voice),
        voiceStatesControllerProvider.overrideWith(
          () => _FakeVoiceStates(const {}),
        ),
      ],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: Scaffold(
          body: VoiceChannelView(
            channelId: channelId,
            spaceId: 's1',
            channelName: channelId,
          ),
        ),
      ),
    );

    await tester.pumpWidget(host('c1'));
    await tester.pump();
    // Connected view in a pane: chat starts closed, controls shown.
    expect(_controlBar, findsOneWidget);
    expect(find.byType(VoiceTextPanel), findsNothing);

    await tester.pumpWidget(host('c2'));
    await tester.pump();

    expect(voice.leaves, 0);
    expect(voice.joins, isEmpty);
    expect(find.text('Join Voice'), findsOneWidget);
    expect(find.byType(VoiceTextPanel), findsOneWidget);
  });

  testWidgets('narrow layout keeps both the chat and the Join button reachable',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final voice = _RecordingVoiceController(const VoiceConnection());
    await tester.pumpWidget(
      _host(
        voice: voice,
        channelId: 'c1',
        voiceStates: {
          'c1': {'u1': AccordVoiceState(userId: 'u1', channelId: 'c1')},
        },
      ),
    );
    await tester.pump();

    // Below the side-panel breakpoint the chat used to replace the body
    // outright, which would have hidden the only way to join.
    expect(find.byType(VoiceTextPanel), findsOneWidget);
    expect(find.text('Join Voice'), findsOneWidget);

    await tester.tap(find.text('Join Voice'));
    await tester.pump();
    expect(voice.joins, [('c1', 's1')]);
  });

  testWidgets('narrow layout fits the lobby, its note and the chat together', (
    tester,
  ) async {
    // The compact strip stacks participants + Join + the "still connected
    // elsewhere" note above the chat; a layout overflow would fail this test.
    tester.view.physicalSize = const Size(400, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'c1', spaceId: 's1'),
    );
    await tester.pumpWidget(
      _host(
        voice: voice,
        channelId: 'c2',
        voiceStates: {
          'c2': {'u1': AccordVoiceState(userId: 'u1', channelId: 'c2')},
        },
      ),
    );
    await tester.pump();

    expect(find.byType(VoiceTextPanel), findsOneWidget);
    expect(find.text('Join Voice'), findsOneWidget);
    expect(find.textContaining("You're connected to"), findsOneWidget);
  });

  testWidgets('a DM call lobby offers no Join button action', (tester) async {
    // DM calls are joined through the ring/accept path, never the lobby button.
    final voice = _RecordingVoiceController(const VoiceConnection());
    await tester.pumpWidget(
      _host(voice: voice, channelId: 'dm1', spaceId: null),
    );
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Join Voice'),
    );
    expect(button.onPressed, isNull);
  });
}
