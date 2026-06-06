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

Widget _host(VoiceConnection state) => ProviderScope(
  overrides: [
    voiceControllerProvider.overrideWith(() => _FakeVoiceController(state)),
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
}
