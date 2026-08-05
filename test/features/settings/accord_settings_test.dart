import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
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
      expect(settings.convertEmoticons, isTrue);
    });

    test('voice AFK settings default on, at the documented timeout', () {
      final settings = AccordSettings.fromJson(const {});
      expect(settings.voiceAfkTimeoutMinutes, defaultAfkTimeoutMinutes);
      expect(settings.voiceAfkAutoMove, isTrue);
    });

    test('voice AFK settings round-trip', () {
      const settings = AccordSettings(
        voiceAfkTimeoutMinutes: 0,
        voiceAfkAutoMove: false,
      );
      final restored = AccordSettings.fromJson(settings.toJson());
      expect(restored.voiceAfkTimeoutMinutes, 0);
      expect(restored.voiceAfkAutoMove, isFalse);
    });

    test('convertEmoticons round-trips when turned off', () {
      const settings = AccordSettings(convertEmoticons: false);
      expect(settings.toJson()['convertEmoticons'], isFalse);
      expect(
        AccordSettings.fromJson(settings.toJson()).convertEmoticons,
        isFalse,
      );
    });

    test('convertEmoticons defaults to true for settings saved before it '
        'existed', () {
      expect(AccordSettings.fromJson(const {}).convertEmoticons, isTrue);
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
        AccordSettings.fromJson(const {
          'masterServerUrl': '   ',
        }).masterServerUrl,
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
    test(
      'a null themePreset falls back to dark via AppThemePreset.fromName',
      () {
        expect(
          AccordSettings.fromJson(const {'themePreset': null}).themePreset,
          AppThemePreset.dark,
        );
      },
    );

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

  group('AccordSettings spaceOrder and spaceFolders', () {
    test('round-trips spaceOrder', () {
      const settings = AccordSettings(spaceOrder: ['a', 'b', 'c']);
      final restored = AccordSettings.fromJson(settings.toJson());
      expect(restored.spaceOrder, ['a', 'b', 'c']);
    });

    test('missing spaceOrder defaults to empty list', () {
      final settings = AccordSettings.fromJson(const {});
      expect(settings.spaceOrder, isEmpty);
    });

    test('round-trips spaceFolders with all fields', () {
      const folder = SpaceFolder(
        id: 'f1',
        name: 'My Folder',
        color: 0xFF5865F2,
        collapsed: true,
        spaceIds: ['s1', 's2'],
      );
      const settings = AccordSettings(spaceFolders: [folder]);
      final restored = AccordSettings.fromJson(settings.toJson());
      expect(restored.spaceFolders.length, 1);
      final r = restored.spaceFolders.first;
      expect(r.id, 'f1');
      expect(r.name, 'My Folder');
      expect(r.color, 0xFF5865F2);
      expect(r.collapsed, isTrue);
      expect(r.spaceIds, ['s1', 's2']);
    });

    test('missing spaceFolders defaults to empty list', () {
      expect(AccordSettings.fromJson(const {}).spaceFolders, isEmpty);
    });
  });

  group('SpaceFolder', () {
    test('round-trips via toJson / fromJson', () {
      const folder = SpaceFolder(
        id: 'abc',
        name: 'Games',
        color: 0xFFED4245,
        collapsed: false,
        spaceIds: ['x', 'y'],
      );
      final restored = SpaceFolder.fromJson(folder.toJson());
      expect(restored.id, 'abc');
      expect(restored.name, 'Games');
      expect(restored.color, 0xFFED4245);
      expect(restored.collapsed, isFalse);
      expect(restored.spaceIds, ['x', 'y']);
    });

    test('null color round-trips as null', () {
      const folder = SpaceFolder(id: 'no-color');
      final restored = SpaceFolder.fromJson(folder.toJson());
      expect(restored.color, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const folder = SpaceFolder(
        id: 'f',
        name: 'Old',
        color: 0xFF112233,
        collapsed: false,
        spaceIds: ['a'],
      );
      final updated = folder.copyWith(name: 'New', collapsed: true);
      expect(updated.id, 'f');
      expect(updated.name, 'New');
      expect(updated.color, 0xFF112233);
      expect(updated.collapsed, isTrue);
      expect(updated.spaceIds, ['a']);
    });

    test('copyWith clearColor nulls the color', () {
      const folder = SpaceFolder(id: 'f', color: 0xFF112233);
      expect(folder.copyWith(clearColor: true).color, isNull);
    });

    test('fromJson with missing fields applies defaults', () {
      final folder = SpaceFolder.fromJson({'id': 'x'});
      expect(folder.name, '');
      expect(folder.color, isNull);
      expect(folder.collapsed, isFalse);
      expect(folder.spaceIds, isEmpty);
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

    test(
      'clearAccentColor takes precedence over accentColor when both given',
      () {
        final result = base.copyWith(
          accentColor: 0xFFAABBCC,
          clearAccentColor: true,
        );
        expect(result.accentColor, isNull);
      },
    );

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
