import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/voice/controllers/voice.dart';
import 'package:bonfire/features/voice/utils/audio_output_support.dart';
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

/// Lays the whole (lazy) list out at once so a `findsNothing` means the control
/// is absent rather than merely unbuilt.
Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(600, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(const AccordSettings()));
  await tester.pump();
}

void main() {
  group('output device picker (#306)', () {
    tearDown(() => debugCanPickAudioOutputDevice = null);

    testWidgets('is offered where the platform can honour the choice', (
      tester,
    ) async {
      debugCanPickAudioOutputDevice = true;
      await _pumpTall(tester);

      expect(find.text('OUTPUT DEVICE'), findsOneWidget);
      expect(find.byKey(const Key('audio-output-dropdown')), findsOneWidget);
    });

    testWidgets('is not offered where the write would be swallowed (iOS)', (
      tester,
    ) async {
      debugCanPickAudioOutputDevice = false;
      await _pumpTall(tester);

      expect(find.text('OUTPUT DEVICE'), findsNothing);
      expect(find.byKey(const Key('audio-output-dropdown')), findsNothing);
      // The rest of the voice stack is untouched — only the one dead control
      // goes, never the feature.
      expect(find.text('INPUT DEVICE'), findsOneWidget);
      expect(find.text('Output volume'), findsOneWidget);
      expect(find.text('CAMERA'), findsOneWidget);
    });
  });

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
