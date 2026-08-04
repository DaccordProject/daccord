import 'package:accordkit/accordkit.dart' show AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/voice/controllers/call.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/incoming_call_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [CallController] holding a fixed ring, recording the decline instead of
/// hitting the network.
class _FakeCallController extends CallController {
  _FakeCallController(this._initial);

  final CallState _initial;
  int declines = 0;

  @override
  CallState build() => _initial;

  @override
  Future<void> declineIncoming() async {
    declines++;
    state = state.copyWith(clearIncoming: true);
  }
}

/// A [VoiceController] that never touches LiveKit.
class _StubVoiceController extends VoiceController {
  _StubVoiceController(this._initial);

  final VoiceConnection _initial;

  @override
  VoiceConnection build() => _initial;

  @override
  Future<void> join(String channelId, String? spaceId) async {}

  @override
  Future<void> leave() async {}
}

class _FakeVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build() => const {};
}

const _incoming = IncomingCall(
  channelId: 'dm-incoming',
  callerId: 'u2',
  serverKey: 'u1@s',
  participants: ['u1', 'u2'],
);

Widget _app({
  required _FakeCallController call,
  required Widget home,
  VoiceConnection voice = const VoiceConnection(),
}) {
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      callControllerProvider.overrideWith(() => call),
      voiceControllerProvider.overrideWith(() => _StubVoiceController(voice)),
      voiceStatesControllerProvider.overrideWith(_FakeVoiceStates.new),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      // Mirrors main.dart: the ring banner is hosted above every route.
      builder: (context, child) => withIncomingCallOverlay(child),
      home: home,
    ),
  );
}

/// The banner's own decline button. Scoped to the overlay because the
/// full-screen call view's control bar carries the same icon.
final _decline = find.descendant(
  of: find.byType(IncomingCallOverlay),
  matching: find.byIcon(Icons.call_end),
);

void main() {
  testWidgets('the ring banner is reachable over a dialog route', (
    tester,
  ) async {
    final call = _FakeCallController(const CallState(incoming: _incoming));
    await tester.pumpWidget(
      _app(
        call: call,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('Direct messages')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // A dialog route (with its full-screen modal barrier) is now on top — the
    // exact thing that used to swallow the banner (#139).
    expect(find.text('Direct messages'), findsOneWidget);
    expect(find.byType(ModalBarrier), findsWidgets);

    // The banner renders *and* takes the tap rather than the barrier.
    expect(_decline, findsOneWidget);
    expect(_decline.hitTestable(), findsOneWidget);
    await tester.tap(_decline);
    await tester.pump();

    expect(call.declines, 1);
    // Declining dismissed the banner, not the dialog underneath it.
    expect(find.text('Direct messages'), findsOneWidget);
  });

  testWidgets('the ring banner is reachable over the full-screen call route', (
    tester,
  ) async {
    final call = _FakeCallController(const CallState(incoming: _incoming));
    await tester.pumpWidget(
      _app(
        call: call,
        voice: const VoiceConnection(channelId: 'dm-active'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showFullScreenVoice(
                  context,
                  channelId: 'dm-active',
                  spaceId: null,
                  channelName: 'Bob',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('open'));
    // Not pumpAndSettle: the pushed call view holds a progress indicator that
    // never settles. Two pumps finish the route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // Already in a call: the classic call-waiting case.
    expect(find.byType(VoiceChannelView), findsOneWidget);

    expect(_decline, findsOneWidget);
    expect(_decline.hitTestable(), findsOneWidget);
    await tester.tap(_decline);
    await tester.pump();

    expect(call.declines, 1);
    // The in-progress call is untouched by declining the second one.
    expect(find.byType(VoiceChannelView), findsOneWidget);
  });

  testWidgets('nothing is rendered when no call is incoming', (tester) async {
    final call = _FakeCallController(const CallState());
    await tester.pumpWidget(
      _app(call: call, home: const Scaffold(body: Text('home'))),
    );
    await tester.pump();

    expect(_decline, findsNothing);
    expect(find.text('home'), findsOneWidget);
  });
}
