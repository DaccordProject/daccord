import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/spaces/controllers/spaces.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/views/voice_bar.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake [VoiceController] that returns a fixed [VoiceConnection], so widgets
/// can be driven through representative voice states without a native session.
class _FakeVoiceController extends VoiceController {
  _FakeVoiceController(this._state);
  final VoiceConnection _state;
  @override
  VoiceConnection build() => _state;
}

/// A fake [SpacesController] that exposes a fixed space list.
class _FakeSpacesController extends SpacesController {
  _FakeSpacesController(this._spaces);
  final List<AccordSpace> _spaces;
  @override
  List<AccordSpace> build() => _spaces;
}

/// Builds a space whose `@everyone` role (position 0) carries [permissions], so
/// every member's effective permissions include them — enough to drive the
/// soundboard gate without wiring up auth/members.
AccordSpace _spaceWithEveryonePerms(List<String> permissions) => AccordSpace(
  id: 's1',
  name: 'Space',
  roles: [AccordRole(id: 'everyone', position: 0, permissions: permissions)],
);

Widget _host(VoiceConnection state, {List<AccordSpace>? spaces}) => ProviderScope(
  overrides: [
    voiceControllerProvider.overrideWith(() => _FakeVoiceController(state)),
    if (spaces != null)
      spacesControllerProvider.overrideWith(
        () => _FakeSpacesController(spaces),
      ),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const Scaffold(body: VoiceBar()),
  ),
);

void main() {
  testWidgets('voice bar renders nothing while disconnected', (tester) async {
    await tester.pumpWidget(_host(const VoiceConnection()));
    await tester.pump();

    expect(find.byType(VoiceBar), findsOneWidget);
    // Disconnected → collapses to a zero-size box, no controls shown.
    expect(find.byType(IconButton), findsNothing);
    final size = tester.getSize(find.byType(VoiceBar));
    expect(size.height, 0);
  });

  testWidgets('shows soundboard button when use_soundboard is granted', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        // selfMute hides the mic meter, which reads an (unopened) Hive box.
        const VoiceConnection(channelId: 'c1', spaceId: 's1', selfMute: true),
        spaces: [
          _spaceWithEveryonePerms([AccordPermission.useSoundboard]),
        ],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.byTooltip('Soundboard'), findsOneWidget);
  });

  testWidgets('hides soundboard button without use_soundboard', (tester) async {
    await tester.pumpWidget(
      _host(
        const VoiceConnection(channelId: 'c1', spaceId: 's1', selfMute: true),
        spaces: [_spaceWithEveryonePerms([])],
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.graphic_eq), findsNothing);
  });

  testWidgets('hides soundboard button in a DM voice call (null spaceId)',
      (tester) async {
    // DM/group-DM calls have no parent space, so the soundboard must never appear
    // regardless of any permission state.
    await tester.pumpWidget(
      _host(const VoiceConnection(channelId: 'c1', selfMute: true)),
    );
    await tester.pump();

    expect(find.byIcon(Icons.graphic_eq), findsNothing);
  });
}
