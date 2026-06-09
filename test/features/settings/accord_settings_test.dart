import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccordSettings round-trip', () {
    test('toJson -> fromJson preserves every field', () {
      const settings = AccordSettings(
        themePreset: AppThemePreset.nord,
        accentColor: 0xFF00FF00,
        notificationsEnabled: false,
        suppressEveryone: true,
        soundsEnabled: false,
        sfxVolume: 0.42,
        recentEmoji: ['😀', 'party:123'],
        masterServerUrl: 'https://master.example.com',
        mutedSpaces: ['space-1', 'space-2'],
        hiddenSpaces: ['space-3'],
      );

      final restored = AccordSettings.fromJson(settings.toJson());

      expect(restored.themePreset, AppThemePreset.nord);
      expect(restored.accentColor, 0xFF00FF00);
      expect(restored.notificationsEnabled, isFalse);
      expect(restored.suppressEveryone, isTrue);
      expect(restored.soundsEnabled, isFalse);
      expect(restored.sfxVolume, 0.42);
      expect(restored.recentEmoji, ['😀', 'party:123']);
      expect(restored.masterServerUrl, 'https://master.example.com');
      expect(restored.mutedSpaces, ['space-1', 'space-2']);
      expect(restored.hiddenSpaces, ['space-3']);
      expect(restored.isSpaceMuted('space-1'), isTrue);
      expect(restored.isSpaceHidden('space-3'), isTrue);
    });

    test('a null accentColor round-trips as null', () {
      const settings = AccordSettings();
      expect(settings.toJson()['accentColor'], isNull);
      expect(AccordSettings.fromJson(settings.toJson()).accentColor, isNull);
    });
  });

  group('AccordSettings.fromJson defaults', () {
    test('an empty map applies all documented defaults', () {
      final settings = AccordSettings.fromJson(const {});
      expect(settings.themePreset, AppThemePreset.dark);
      expect(settings.accentColor, isNull);
      expect(settings.notificationsEnabled, isTrue);
      expect(settings.suppressEveryone, isFalse);
      expect(settings.soundsEnabled, isTrue);
      expect(settings.sfxVolume, 1.0);
      expect(settings.recentEmoji, isEmpty);
      expect(settings.masterServerUrl, AccordSettings.defaultMasterServerUrl);
    });

    test('a partial map keeps provided values and defaults the rest', () {
      final settings = AccordSettings.fromJson(const {
        'notificationsEnabled': false,
        'sfxVolume': 0.25,
      });
      expect(settings.notificationsEnabled, isFalse);
      expect(settings.sfxVolume, 0.25);
      // Untouched fields fall back to defaults.
      expect(settings.suppressEveryone, isFalse);
      expect(settings.soundsEnabled, isTrue);
      expect(settings.recentEmoji, isEmpty);
    });

    test('a blank/whitespace masterServerUrl falls back to the default', () {
      expect(
        AccordSettings.fromJson(const {'masterServerUrl': '   '}).masterServerUrl,
        AccordSettings.defaultMasterServerUrl,
      );
      expect(
        AccordSettings.fromJson(const {'masterServerUrl': ''}).masterServerUrl,
        AccordSettings.defaultMasterServerUrl,
      );
    });

    test('an integer sfxVolume is coerced to double', () {
      final settings = AccordSettings.fromJson(const {'sfxVolume': 1});
      expect(settings.sfxVolume, 1.0);
      expect(settings.sfxVolume, isA<double>());
    });
  });

  group('AccordSettings themePreset parsing', () {
    test('a null themePreset falls back to dark via AppThemePreset.fromName',
        () {
      expect(
        AccordSettings.fromJson(const {'themePreset': null}).themePreset,
        AppThemePreset.dark,
      );
    });

    test('an unknown themePreset name falls back to dark', () {
      expect(
        AccordSettings.fromJson(const {'themePreset': 'sunburst'}).themePreset,
        AppThemePreset.dark,
      );
    });

    test('a known themePreset name parses to its enum value', () {
      expect(
        AccordSettings.fromJson(const {'themePreset': 'midnight'}).themePreset,
        AppThemePreset.midnight,
      );
    });
  });

  group('AccordSettings.recentEmoji coercion', () {
    test('non-string entries are coerced to String', () {
      final settings = AccordSettings.fromJson(const {
        'recentEmoji': [1, true, '😀'],
      });
      expect(settings.recentEmoji, ['1', 'true', '😀']);
    });

    test('a missing recentEmoji yields an empty list', () {
      expect(AccordSettings.fromJson(const {}).recentEmoji, isEmpty);
    });
  });

  group('AccordSettings.copyWith', () {
    const base = AccordSettings(accentColor: 0xFF112233);

    test('clearAccentColor: true nulls the accent', () {
      expect(base.copyWith(clearAccentColor: true).accentColor, isNull);
    });

    test('accentColor: x sets a new accent', () {
      expect(base.copyWith(accentColor: 0xFFAABBCC).accentColor, 0xFFAABBCC);
    });

    test('clearAccentColor takes precedence over accentColor when both given',
        () {
      final result =
          base.copyWith(accentColor: 0xFFAABBCC, clearAccentColor: true);
      expect(result.accentColor, isNull);
    });

    test('omitting accent fields preserves the existing accent', () {
      expect(base.copyWith(soundsEnabled: false).accentColor, 0xFF112233);
    });

    test('other fields are updated independently', () {
      final result = base.copyWith(
        themePreset: AppThemePreset.light,
        sfxVolume: 0.5,
        recentEmoji: ['x'],
      );
      expect(result.themePreset, AppThemePreset.light);
      expect(result.sfxVolume, 0.5);
      expect(result.recentEmoji, ['x']);
      // Untouched field unchanged.
      expect(result.notificationsEnabled, isTrue);
    });
  });
}
