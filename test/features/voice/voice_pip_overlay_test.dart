import 'package:accordkit/accordkit.dart'
    show AccordChannel, AccordUser, AccordVoiceState;
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/channels/controllers/dm_channels.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/views/voice_pip_overlay.dart';
import 'package:bonfire/features/voice/views/voice_view.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVoiceController extends VoiceController {
  _StubVoiceController(this._initial);

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

class _FakeVoiceStates extends VoiceStatesController {
  @override
  Map<String, Map<String, AccordVoiceState>> build() => const {};
}

class _FakeDmChannels extends DmChannelsController {
  _FakeDmChannels(this._seed);
  final List<AccordChannel>? _seed;

  @override
  List<AccordChannel>? build() => _seed;
}

final _dm = AccordChannel(
  id: 'dm1',
  type: 'dm',
  recipients: [AccordUser(id: 'u2', username: 'alice', displayName: 'Alice')],
);

/// The PiP's "reopen" affordance, and the only widget unique to it.
final _pip = find.byIcon(Icons.open_in_full);

Widget _host({
  required _StubVoiceController voice,
  String? shownChannelId,
  bool hasVideo = true,
  List<AccordChannel>? dms,
  void Function(String channelId, String spaceId)? onOpen,
}) {
  return ProviderScope(
    overrides: [
      accordAuthProvider.overrideWithValue(const AccordAuthLoggedOut()),
      voiceControllerProvider.overrideWith(() => voice),
      voiceStatesControllerProvider.overrideWith(_FakeVoiceStates.new),
      dmChannelsControllerProvider.overrideWith(() => _FakeDmChannels(dms)),
    ],
    child: MaterialApp(
      theme: buildAppTheme(AppThemePreset.dark),
      home: Scaffold(
        body: Stack(
          children: [
            const SizedBox.expand(child: Text('channel')),
            VoicePipOverlay(
              shownChannelId: shownChannelId,
              onOpen: onOpen ?? (_, _) {},
              // A real LiveKit VideoTrack can't be built off-device; this
              // stands in for the track preview.
              previewBuilder: () =>
                  hasVideo ? const ColoredBox(color: Colors.blue) : null,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('a DM call with video gets a PiP', (tester) async {
    // DM calls used to be excluded outright (#136).
    final voice = _StubVoiceController(const VoiceConnection(channelId: 'dm1'));
    await tester.pumpWidget(
      _host(voice: voice, shownChannelId: 'other', dms: [_dm]),
    );
    await tester.pump();

    expect(_pip, findsOneWidget);
  });

  testWidgets('tapping a DM call PiP reopens the full-screen call view', (
    tester,
  ) async {
    final voice = _StubVoiceController(const VoiceConnection(channelId: 'dm1'));
    await tester.pumpWidget(
      _host(
        voice: voice,
        shownChannelId: 'other',
        dms: [_dm],
        // The space channel opener can't resolve a DM channel, so it must not
        // be the route back into the call.
        onOpen: (_, _) => fail('a DM call must not route through _openChannel'),
      ),
    );
    await tester.pump();

    await tester.tap(_pip);
    // Not pumpAndSettle: the pushed call view holds a progress indicator that
    // never settles. Two pumps finish the route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final view = tester.widget<VoiceChannelView>(find.byType(VoiceChannelView));
    expect(view.channelId, 'dm1');
    expect(view.spaceId, isNull);
    // Titled from the DM's recipients, since a 1:1 DM has no channel name.
    expect(view.channelName, 'Alice');
    expect(view.fullScreen, isTrue);
  });

  testWidgets('a group DM PiP reopens under the group name', (tester) async {
    final voice = _StubVoiceController(const VoiceConnection(channelId: 'g1'));
    await tester.pumpWidget(
      _host(
        voice: voice,
        shownChannelId: 'other',
        dms: [AccordChannel(id: 'g1', type: 'group_dm', name: 'Book club')],
      ),
    );
    await tester.pump();

    await tester.tap(_pip);
    // Not pumpAndSettle: the pushed call view holds a progress indicator that
    // never settles. Two pumps finish the route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final view = tester.widget<VoiceChannelView>(find.byType(VoiceChannelView));
    expect(view.channelName, 'Book club');
  });

  testWidgets('an audio-only DM call shows no PiP', (tester) async {
    // Consistent with space voice: nothing to preview, nothing to float.
    final voice = _StubVoiceController(const VoiceConnection(channelId: 'dm1'));
    await tester.pumpWidget(
      _host(
        voice: voice,
        shownChannelId: 'other',
        hasVideo: false,
        dms: [_dm],
      ),
    );
    await tester.pump();

    expect(_pip, findsNothing);
  });

  testWidgets('no PiP while the call itself is on screen', (tester) async {
    final voice = _StubVoiceController(const VoiceConnection(channelId: 'dm1'));
    await tester.pumpWidget(
      _host(voice: voice, shownChannelId: 'dm1', dms: [_dm]),
    );
    await tester.pump();

    expect(_pip, findsNothing);
  });

  testWidgets('a space voice channel still reopens through the host', (
    tester,
  ) async {
    final voice = _StubVoiceController(
      const VoiceConnection(channelId: 'c1', spaceId: 's1'),
    );
    final opened = <(String, String)>[];
    await tester.pumpWidget(
      _host(
        voice: voice,
        shownChannelId: 'c2',
        onOpen: (channelId, spaceId) => opened.add((channelId, spaceId)),
      ),
    );
    await tester.pump();

    await tester.tap(_pip);
    // Not pumpAndSettle: the pushed call view holds a progress indicator that
    // never settles. Two pumps finish the route transition.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(opened, [('c1', 's1')]);
    expect(find.byType(VoiceChannelView), findsNothing);
  });
}
