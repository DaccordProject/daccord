import 'dart:io';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/settings/views/accord_settings_screen.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// `AccordSettings.backgroundConnection` drives the Android foreground service
/// that keeps the gateway alive while the app is backgrounded, but it had a
/// reader and no setter, so nothing in the UI could ever turn it on (#306).
/// These cover the setter's persistence, the settings entry, and the platform
/// gate the entry shares with `BackgroundConnectionController`.

const _switch = Key('background-connection-switch');

/// Keeps the screen off Hive — a Hive write inside a `testWidgets` fake-async
/// zone never settles, so persistence is covered by the plain test below.
class _MemorySettingsController extends SettingsController {
  final List<bool> backgroundWrites = [];

  @override
  AccordSettings build() => const AccordSettings();

  @override
  void setBackgroundConnection(bool enabled) {
    backgroundWrites.add(enabled);
    state = state.copyWith(backgroundConnection: enabled);
  }
}

/// A viewport tall enough to lay the whole (lazy) settings list out at once, so
/// a `findsNothing` means absent rather than merely unbuilt.
Future<_MemorySettingsController> _pumpTall(WidgetTester tester) async {
  final settings = _MemorySettingsController();
  tester.view.physicalSize = const Size(600, 8000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [settingsControllerProvider.overrideWith(() => settings)],
      child: MaterialApp(
        theme: buildAppTheme(AppThemePreset.dark),
        home: const AccordSettingsScreen(),
      ),
    ),
  );
  await tester.pump();
  return settings;
}

void main() {
  tearDown(() => debugBackgroundConnectionAvailable = null);

  group('the setter that was missing', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('accord-bgconn-test');
      Hive.init(tempDir.path);
      await Hive.openBox('accord-settings');
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk('accord-settings');
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('setBackgroundConnection persists through the settings box', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(settingsControllerProvider).backgroundConnection,
        isFalse,
      );
      container
          .read(settingsControllerProvider.notifier)
          .setBackgroundConnection(true);

      expect(
        container.read(settingsControllerProvider).backgroundConnection,
        isTrue,
      );
      // Read it back the way a restart would, not just the in-memory state.
      expect(
        Hive.box('accord-settings').get('settings'),
        containsPair('backgroundConnection', true),
      );
    });
  });

  testWidgets('the toggle is offered where the service exists, and writes', (
    tester,
  ) async {
    debugBackgroundConnectionAvailable = true;
    final settings = await _pumpTall(tester);

    expect(find.byKey(_switch), findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byKey(_switch)).value, isFalse);

    await tester.tap(find.byKey(_switch));
    await tester.pump();

    expect(settings.backgroundWrites, [true]);
    expect(tester.widget<SwitchListTile>(find.byKey(_switch)).value, isTrue);
  });

  testWidgets('the toggle is hidden where the service cannot run', (
    tester,
  ) async {
    // Non-Android, or a store build whose manifest omits the service.
    debugBackgroundConnectionAvailable = false;
    await _pumpTall(tester);

    expect(find.byKey(_switch), findsNothing);
    // The rest of the Notifications section is unaffected.
    expect(find.text('Enable notifications'), findsOneWidget);
  });
}
