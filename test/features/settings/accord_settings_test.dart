import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:bonfire/features/spaces/models/space_folder.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/shared/models/server_entity_key.dart';
import 'package:bonfire/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccordSettings round-trip', () {
    test('toJson -> fromJson preserves every field', () {
      final settings = AccordSettings(
        themePreset: AppThemePreset.nord,
        accentColor: 0xFF00FF00,
        notificationsEnabled: false,
        suppressEveryone: true,
        soundsEnabled: false,
        sfxVolume: 0.42,
        recentEmoji: ['😀', 'party:123'],
        masterServerUrl: 'https://master.example.com',
        mutedSpaces: [
          ServerEntityKey('server', 'space-1').encoded,
          ServerEntityKey('server', 'space-2').encoded,
        ],
        hiddenSpaces: [ServerEntityKey('server', 'space-3').encoded],
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
      expect(restored.mutedSpaces, settings.mutedSpaces);
      expect(restored.hiddenSpaces, settings.hiddenSpaces);
      expect(restored.isSpaceMuted('server', 'space-1'), isTrue);
      expect(restored.isSpaceHidden('server', 'space-3'), isTrue);
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

  group('AccordSettings screen-share quality', () {
    test('defaults are motion-friendly and independent of the camera', () {
      const settings = AccordSettings();
      // Camera stays where it was: 720p30.
      expect(settings.videoDimensions, (1280, 720));
      expect(settings.videoFps, 30);
      // Screen share gets its own, 60 fps ladder.
      expect(settings.screenShareResolution, 0);
      expect(settings.screenShareDimensions, (1280, 720));
      expect(settings.screenShareFps, 60);
      expect(settings.screenShareMotionPriority, isTrue);
    });

    test('installs saved before the setting existed get the new defaults, '
        'not the camera values', () {
      // A pre-#151 settings blob: camera tuned down, no screen-share keys.
      final settings = AccordSettings.fromJson(const {
        'videoResolution': 0,
        'videoFps': 15,
      });
      expect(settings.videoResolution, 0);
      expect(settings.videoFps, 15);
      expect(
        settings.screenShareResolution,
        AccordSettings.defaultScreenShareResolution,
      );
      expect(settings.screenShareFps, AccordSettings.defaultScreenShareFps);
      expect(settings.screenShareMotionPriority, isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      const settings = AccordSettings(
        screenShareResolution: 2,
        screenShareFps: 30,
        screenShareMotionPriority: false,
      );
      final restored = AccordSettings.fromJson(settings.toJson());
      expect(restored.screenShareResolution, 2);
      expect(restored.screenShareFps, 30);
      expect(restored.screenShareMotionPriority, isFalse);
    });

    test('an out-of-range persisted resolution is clamped', () {
      expect(
        AccordSettings.fromJson(const {
          'screenShareResolution': 99,
        }).screenShareResolution,
        AccordSettings.screenShareResolutionLabels.length - 1,
      );
      expect(
        AccordSettings.fromJson(const {
          'screenShareResolution': -3,
        }).screenShareResolution,
        0,
      );
    });

    test('an unsupported persisted frame rate falls back to the default', () {
      expect(
        AccordSettings.fromJson(const {'screenShareFps': 7}).screenShareFps,
        AccordSettings.defaultScreenShareFps,
      );
      expect(
        AccordSettings.fromJson(const {'screenShareFps': 30}).screenShareFps,
        30,
      );
    });

    test('dimensions follow the resolution index', () {
      expect(
        const AccordSettings(screenShareResolution: 0).screenShareDimensions,
        (1280, 720),
      );
      expect(
        const AccordSettings(screenShareResolution: 1).screenShareDimensions,
        (1920, 1080),
      );
      expect(
        const AccordSettings(screenShareResolution: 2).screenShareDimensions,
        (2560, 1440),
      );
    });

    test('bitrate ceilings sit in the live-streaming range for 60 fps', () {
      const p720 = AccordSettings(screenShareResolution: 0);
      const p1080 = AccordSettings(screenShareResolution: 1);
      const p1440 = AccordSettings(screenShareResolution: 2);
      expect(p720.screenShareBitrate, 3000000);
      expect(p1080.screenShareBitrate, 6000000);
      expect(p1440.screenShareBitrate, 9000000);
      // And well clear of the camera presets they used to inherit.
      expect(p720.screenShareBitrate, greaterThan(p720.videoBitrate));
    });

    test('bitrate scales down sub-linearly with frame rate', () {
      const base = AccordSettings(screenShareResolution: 0);
      const at30 = AccordSettings(screenShareResolution: 0, screenShareFps: 30);
      const at15 = AccordSettings(screenShareResolution: 0, screenShareFps: 15);
      expect(at30.screenShareBitrate, 2100000);
      expect(at15.screenShareBitrate, 1500000);
      // Halving fps must not halve the budget.
      expect(
        at30.screenShareBitrate,
        greaterThan(base.screenShareBitrate ~/ 2),
      );
    });

    test('copyWith updates the screen-share fields independently', () {
      const base = AccordSettings();
      final next = base.copyWith(
        screenShareResolution: 1,
        screenShareFps: 30,
        screenShareMotionPriority: false,
      );
      expect(next.screenShareResolution, 1);
      expect(next.screenShareFps, 30);
      expect(next.screenShareMotionPriority, isFalse);
      // Camera untouched.
      expect(next.videoResolution, base.videoResolution);
      expect(next.videoFps, base.videoFps);
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
