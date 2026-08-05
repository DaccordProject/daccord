import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/views/voice_settings_screen.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings held in memory rather than Hive, so the page can be pumped without
/// opening a box.
class _MemorySettingsController extends SettingsController {
  _MemorySettingsController(this._initial);
  final AccordSettings _initial;

  @override
  AccordSettings build() => _initial;
}

/// Never joined, so the page renders its disconnected mic-test copy.
class _IdleVoiceController extends VoiceController {
  @override
  VoiceConnection build() => const VoiceConnection();
}

Widget _host(AccordSettings settings) => ProviderScope(
  overrides: [
    settingsControllerProvider.overrideWith(
      () => _MemorySettingsController(settings),
    ),
    voiceControllerProvider.overrideWith(_IdleVoiceController.new),
  ],
  child: MaterialApp(
    theme: buildAppTheme(AppThemePreset.dark),
    home: const VoiceSettingsScreen(),
  ),
);

void main() {
  testWidgets('screen-share quality is its own section, labelled apart from '
      'the camera', (tester) async {
    await tester.pumpWidget(
      _host(const AccordSettings(videoFps: 30, screenShareFps: 60)),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const Key('screen-share-motion-switch')),
      300,
    );

    // Both groups are on the page, and every control says which one it belongs
    // to — the old shared "Resolution"/"Frame rate" rows were ambiguous.
    expect(find.text('SCREEN SHARE'), findsOneWidget);
    expect(find.text('Camera resolution'), findsOneWidget);
    expect(find.text('Camera frame rate'), findsOneWidget);
    expect(find.text('Screen share resolution'), findsOneWidget);
    expect(find.text('Screen share frame rate'), findsOneWidget);
    expect(find.byKey(const Key('screen-share-motion-switch')), findsOneWidget);

    // The two frame-rate pickers show their own value, not a shared one.
    final dropdowns = tester
        .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
        .toList();
    expect(dropdowns.map((d) => d.value), containsAll(<int>[30, 60]));
  });
}
