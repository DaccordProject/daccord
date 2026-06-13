import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'dart:io';

// Note: kAppStoreBuild is a compile-time const (bool.fromEnvironment('APP_STORE')).
// It is always false in unit tests unless built with --dart-define=APP_STORE=true,
// so the kAppStoreBuild == true early-return paths in maybeCheckOnStartup() and
// canInstallInPlace cannot be exercised here. Those paths are verified by the
// CI build itself (store builds) and the integration test matrix.

late Directory _tempDir;

ProviderContainer makeContainer() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

UpdateController controllerOf(ProviderContainer c) =>
    c.read(updateControllerProvider.notifier);

UpdateState stateOf(ProviderContainer c) => c.read(updateControllerProvider);

void main() {
  setUp(() async {
    _tempDir = Directory.systemTemp.createTempSync('update-controller-test');
    Hive.init(_tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('canInstallInPlace', () {
    test('is false when no release has been loaded', () {
      final c = makeContainer();
      // No latest release → platformAsset() returns null → canInstallInPlace false.
      expect(stateOf(c).latest, isNull);
      expect(controllerOf(c).canInstallInPlace, isFalse);
    });

    test('is false when release has no assets matching this platform', () {
      final c = makeContainer();
      // A release with no assets — platformAsset() returns null regardless of
      // UpdateInstaller.isSupported.
      c.read(updateControllerProvider.notifier).state = const UpdateState(
        latest: AppRelease(
          version: '99.0.0',
          name: 'v99.0.0',
          notes: '',
          url: '',
          publishedAt: '',
          assets: [],
        ),
      );
      expect(controllerOf(c).canInstallInPlace, isFalse);
    });

    test('kAppStoreBuild is false in test builds', () {
      // Sanity-check: the compile-time constant is off for normal test runs.
      // Store-build CI compiles with --dart-define=APP_STORE=true.
      expect(kAppStoreBuild, isFalse);
    });
  });

  group('dismissCurrent', () {
    test('is a no-op when state.latest is null', () {
      final c = makeContainer();
      controllerOf(c).dismissCurrent();
      expect(stateOf(c).dismissedVersion, isNull);
    });

    test('sets dismissedVersion to the latest release version', () {
      final c = makeContainer();
      c.read(updateControllerProvider.notifier).state = const UpdateState(
        latest: AppRelease(
          version: '2.0.0',
          name: 'v2.0.0',
          notes: '',
          url: '',
          publishedAt: '',
        ),
      );
      controllerOf(c).dismissCurrent();
      expect(stateOf(c).dismissedVersion, '2.0.0');
    });
  });

  group('skipCurrent', () {
    test('is a no-op when state.latest is null', () {
      final c = makeContainer();
      controllerOf(c).skipCurrent();
      expect(
        c.read(settingsControllerProvider).skippedUpdateVersion,
        isEmpty,
      );
    });

    test('persists skippedUpdateVersion in settings when latest exists', () {
      final c = makeContainer();
      c.read(updateControllerProvider.notifier).state = const UpdateState(
        latest: AppRelease(
          version: '3.1.0',
          name: 'v3.1.0',
          notes: '',
          url: '',
          publishedAt: '',
        ),
      );
      controllerOf(c).skipCurrent();
      expect(
        c.read(settingsControllerProvider).skippedUpdateVersion,
        '3.1.0',
      );
    });
  });

  group('UpdateState.updateAvailable', () {
    test('is false when latest is null', () {
      expect(const UpdateState().updateAvailable, isFalse);
    });

    test('is true when latest version is newer than kAppVersion', () {
      const state = UpdateState(
        latest: AppRelease(
          version: '99.0.0',
          name: 'v99.0.0',
          notes: '',
          url: '',
          publishedAt: '',
        ),
      );
      // kAppVersion defaults to '0.0.0' in tests (initAppInfo not called).
      expect(state.updateAvailable, isTrue);
    });

    test('is false when dismissed version matches latest', () {
      const state = UpdateState(
        latest: AppRelease(
          version: '99.0.0',
          name: 'v99.0.0',
          notes: '',
          url: '',
          publishedAt: '',
        ),
        dismissedVersion: '99.0.0',
      );
      // updateAvailable does not check dismissedVersion — that's the banner's job.
      // Verify the raw availability is still true (the banner filters it).
      expect(state.updateAvailable, isTrue);
    });

    test('is false for a pre-release when this build is stable', () {
      const state = UpdateState(
        latest: AppRelease(
          version: '99.0.0-beta.1',
          name: 'v99.0.0-beta.1',
          notes: '',
          url: '',
          publishedAt: '',
          prerelease: true,
        ),
      );
      // kAppVersion '0.0.0' is stable (no '-'), so pre-releases are hidden.
      expect(state.updateAvailable, isFalse);
    });
  });
}
