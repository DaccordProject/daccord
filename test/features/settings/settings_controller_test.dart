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

  group('acceptRules', () {
    test('records acceptance and survives a controller rebuild', () {
      final c1 = makeContainer();
      controllerOf(c1).acceptRules('space-1');
      expect(stateOf(c1).isRulesAccepted('space-1'), isTrue);
      expect(stateOf(c1).isRulesAccepted('space-2'), isFalse);

      // The reported bug: the rules popup reappeared every join because
      // acceptance was in-memory. It must now survive a fresh controller.
      final c2 = makeContainer();
      expect(stateOf(c2).isRulesAccepted('space-1'), isTrue);
    });

    test('re-accepting the same space is a no-op (no duplicates)', () {
      final c = makeContainer();
      controllerOf(c)
        ..acceptRules('s')
        ..acceptRules('s');
      expect(stateOf(c).acceptedRuleSpaces, ['s']);
    });
  });

  group('acknowledgeNsfw', () {
    test('records and persists per-channel acknowledgement', () {
      final c1 = makeContainer();
      controllerOf(c1).acknowledgeNsfw('chan-1');
      final c2 = makeContainer();
      expect(stateOf(c2).isNsfwAcknowledged('chan-1'), isTrue);
      expect(stateOf(c2).isNsfwAcknowledged('chan-2'), isFalse);
    });
  });

  group('setCategoryCollapsed', () {
    test('toggles per-space and persists', () {
      final c1 = makeContainer();
      controllerOf(c1).setCategoryCollapsed('space', 'cat', true);
      expect(stateOf(c1).isCategoryCollapsed('space', 'cat'), isTrue);

      final c2 = makeContainer();
      expect(stateOf(c2).isCategoryCollapsed('space', 'cat'), isTrue);

      controllerOf(c2).setCategoryCollapsed('space', 'cat', false);
      expect(stateOf(c2).isCategoryCollapsed('space', 'cat'), isFalse);
      // Cleared spaces drop out of the map entirely.
      expect(stateOf(c2).collapsedCategories.containsKey('space'), isFalse);
    });

    test('collapse state is scoped to its space', () {
      final c = makeContainer();
      controllerOf(c).setCategoryCollapsed('space-a', 'cat', true);
      expect(stateOf(c).isCategoryCollapsed('space-b', 'cat'), isFalse);
    });
  });

  group('setDraft', () {
    test('saves, restores across rebuild, and clears on blank', () {
      final c1 = makeContainer();
      controllerOf(c1).setDraft('chan', 'half-typed message');
      expect(stateOf(c1).draftFor('chan'), 'half-typed message');

      final c2 = makeContainer();
      expect(stateOf(c2).draftFor('chan'), 'half-typed message');

      controllerOf(c2).setDraft('chan', '');
      expect(stateOf(c2).draftFor('chan'), '');
      expect(stateOf(c2).drafts.containsKey('chan'), isFalse);
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

  group('voice settings', () {
    test('input/output volume clamps to 0–200', () {
      final c = makeContainer();
      controllerOf(c)
        ..setInputVolume(500)
        ..setOutputVolume(-50);
      expect(stateOf(c).inputVolume, 200);
      expect(stateOf(c).outputVolume, 0);
    });

    test('input sensitivity clamps to 0–100', () {
      final c = makeContainer();
      controllerOf(c).setInputSensitivity(250);
      expect(stateOf(c).inputSensitivity, 100);
    });

    test('speakingThreshold maps sensitivity logarithmically', () {
      const s0 = AccordSettings(inputSensitivity: 0);
      const s50 = AccordSettings(inputSensitivity: 50);
      const s100 = AccordSettings(inputSensitivity: 100);
      expect(s0.speakingThreshold, closeTo(0.1, 1e-6));
      expect(s50.speakingThreshold, closeTo(0.00316, 1e-4));
      expect(s100.speakingThreshold, closeTo(0.0001, 1e-6));
      // Higher sensitivity → lower threshold.
      expect(s100.speakingThreshold, lessThan(s0.speakingThreshold));
    });

    test('device + volume selections survive a controller rebuild', () {
      final c1 = makeContainer();
      controllerOf(c1)
        ..setAudioInputDevice('mic-1')
        ..setAudioOutputDevice('spk-2')
        ..setVideoInputDevice('cam-3')
        ..setInputVolume(150)
        ..setOutputVolume(80)
        ..setInputSensitivity(70);

      final c2 = makeContainer();
      final s = stateOf(c2);
      expect(s.audioInputDeviceId, 'mic-1');
      expect(s.audioOutputDeviceId, 'spk-2');
      expect(s.videoInputDeviceId, 'cam-3');
      expect(s.inputVolume, 150);
      expect(s.outputVolume, 80);
      expect(s.inputSensitivity, 70);
    });
  });
}
