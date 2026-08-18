import 'package:accordkit/accordkit.dart' show AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records leaves so a test can tell "dropped out of the room" apart from
/// "cancelled the call".
class _RecordingVoiceController extends VoiceController {
  _RecordingVoiceController(this._initial);

  final VoiceConnection _initial;
  int leaves = 0;

  @override
  VoiceConnection build() => _initial;

  @override
  Future<void> join(String channelId, String? spaceId) async {}

  @override
  Future<void> leave() async {
    leaves++;
    state = const VoiceConnection();
  }
}

/// Stands in for the real controller, whose `cancelOutgoing` is what sends the
/// `call/cancel` REST (plus leaving voice and clearing the outgoing state).
class _RecordingCallController extends CallController {
  _RecordingCallController(this._initial);

  final CallState _initial;
  int cancels = 0;

  @override
  CallState build() => _initial;

  @override
  Future<void> cancelOutgoing() async {
    cancels++;
    state = state.copyWith(clearOutgoing: true);
  }
}

class _FakeVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build() => const {};
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
  required _RecordingCallController call,
  required String channelId,
  required String? spaceId,
}) {
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      settingsControllerProvider.overrideWith(_FakeSettingsController.new),
      voiceControllerProvider.overrideWith(() => voice),
      callControllerProvider.overrideWith(() => call),
      voiceStatesControllerProvider.overrideWith(_FakeVoiceStates.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: VoiceChannelView(
          channelId: channelId,
          spaceId: spaceId,
          channelName: 'Alice',
        ),
      ),
    ),
  );
}

final _disconnect = find.byTooltip('Disconnect');

void main() {
  testWidgets('hanging up a still-ringing DM call cancels it', (tester) async {
    // The callee hasn't answered yet, so dropping the room silently would leave
    // their device ringing until the server noticed (#140).
    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'dm1'),
    );
    final call = _RecordingCallController(
      const CallState(outgoingChannelId: 'dm1'),
    );
    await tester.pumpWidget(
      _host(voice: voice, call: call, channelId: 'dm1', spaceId: null),
    );
    await tester.pump();
    expect(find.textContaining('Calling'), findsOneWidget);

    await tester.tap(_disconnect);
    await tester.pump();

    expect(call.cancels, 1);
    // cancelOutgoing owns the leave; the button must not do it separately.
    expect(voice.leaves, 0);
  });

  testWidgets('hanging up an answered DM call just leaves', (tester) async {
    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'dm1'),
    );
    final call = _RecordingCallController(const CallState());
    await tester.pumpWidget(
      _host(voice: voice, call: call, channelId: 'dm1', spaceId: null),
    );
    await tester.pump();
    expect(find.textContaining('Calling'), findsNothing);

    await tester.tap(_disconnect);
    await tester.pump();

    expect(call.cancels, 0);
    expect(voice.leaves, 1);
  });

  testWidgets('hanging up a space voice channel just leaves', (tester) async {
    // Nothing rings in a space channel; the outgoing state can only be a
    // leftover from a DM call, so it must not steer this button.
    final voice = _RecordingVoiceController(
      const VoiceConnection(channelId: 'c1', spaceId: 's1'),
    );
    final call = _RecordingCallController(
      const CallState(outgoingChannelId: 'c1'),
    );
    await tester.pumpWidget(
      _host(voice: voice, call: call, channelId: 'c1', spaceId: 's1'),
    );
    await tester.pump();

    await tester.tap(_disconnect);
    await tester.pump();

    expect(call.cancels, 0);
    expect(voice.leaves, 1);
  });
}
