import 'dart:io';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('accord-settings-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  SettingsController controllerOf(ProviderContainer c) =>
      c.read(settingsControllerProvider.notifier);

  AccordSettings stateOf(ProviderContainer c) =>
      c.read(settingsControllerProvider);

  group('addRecentEmoji', () {
    test('adds a new token to the front', () {
      final c = makeContainer();
      controllerOf(c).addRecentEmoji('😀');
      controllerOf(c).addRecentEmoji('🎉');
      expect(stateOf(c).recentEmoji, ['🎉', '😀']);
    });

    test('re-adding an existing token moves it to the front without duplicating',
        () {
      final c = makeContainer();
      controllerOf(c)
        ..addRecentEmoji('a')
        ..addRecentEmoji('b')
        ..addRecentEmoji('c')
        ..addRecentEmoji('a');
      expect(stateOf(c).recentEmoji, ['a', 'c', 'b']);
    });

    test('caps the list at 24 — the 25th add drops the oldest', () {
      final c = makeContainer();
      final ctrl = controllerOf(c);
      for (var i = 0; i < 25; i++) {
        ctrl.addRecentEmoji('e$i');
      }
      final recent = stateOf(c).recentEmoji;
      expect(recent.length, 24);
      expect(recent.first, 'e24'); // most-recent at the front
      expect(recent.last, 'e1'); // 'e0' (oldest) dropped
      expect(recent.contains('e0'), isFalse);
    });

    test('an empty token is a no-op and does not persist', () {
      final c = makeContainer();
      controllerOf(c).addRecentEmoji('');
      expect(stateOf(c).recentEmoji, isEmpty);
      // Nothing written to the box.
      expect(Hive.box('accord-settings').get('settings'), isNull);
    });
  });

  group('setSfxVolume', () {
    test('clamps a value above 1.0 down to 1.0', () {
      final c = makeContainer();
      controllerOf(c).setSfxVolume(2.5);
      expect(stateOf(c).sfxVolume, 1.0);
    });

    test('clamps a value below 0.0 up to 0.0', () {
      final c = makeContainer();
      controllerOf(c).setSfxVolume(-3.0);
      expect(stateOf(c).sfxVolume, 0.0);
    });

    test('leaves an in-range value untouched', () {
      final c = makeContainer();
      controllerOf(c).setSfxVolume(0.6);
      expect(stateOf(c).sfxVolume, 0.6);
    });
  });

  group('persistence', () {
    test('a setter survives a controller rebuild (re-reading the box)', () {
      final c1 = makeContainer();
      controllerOf(c1)
        ..addRecentEmoji('💾')
        ..setSfxVolume(0.3)
        ..setSuppressEveryone(true);

      // A fresh container rebuilds the controller from the Hive box.
      final c2 = makeContainer();
      final restored = stateOf(c2);
      expect(restored.recentEmoji, ['💾']);
      expect(restored.sfxVolume, 0.3);
      expect(restored.suppressEveryone, isTrue);
    });

    test('clamped volume is what gets persisted', () {
      final c1 = makeContainer();
      controllerOf(c1).setSfxVolume(9.0);

      final c2 = makeContainer();
      expect(stateOf(c2).sfxVolume, 1.0);
    });
  });
}
