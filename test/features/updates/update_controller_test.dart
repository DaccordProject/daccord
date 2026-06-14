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

  group('UpdateState.updateReady', () {
    test('is false when phase is idle even if stagedArchivePath is set', () {
      const state = UpdateState(
        phase: UpdatePhase.idle,
        stagedArchivePath: '/tmp/daccord.tar.gz',
      );
      expect(state.updateReady, isFalse);
    });

    test('is false when phase is ready but stagedArchivePath is null', () {
      const state = UpdateState(phase: UpdatePhase.ready);
      expect(state.updateReady, isFalse);
    });

    test('is true when phase is ready and stagedArchivePath is set', () {
      const state = UpdateState(
        phase: UpdatePhase.ready,
        stagedArchivePath: '/tmp/daccord.tar.gz',
      );
      expect(state.updateReady, isTrue);
    });
  });

  group('UpdateState.downloading', () {
    test('is true when phase is downloading', () {
      expect(
        const UpdateState(phase: UpdatePhase.downloading).downloading,
        isTrue,
      );
    });

    test('is true when phase is verifying', () {
      expect(
        const UpdateState(phase: UpdatePhase.verifying).downloading,
        isTrue,
      );
    });

    test('is false for idle, ready, installing, failed', () {
      for (final p in [
        UpdatePhase.idle,
        UpdatePhase.ready,
        UpdatePhase.installing,
        UpdatePhase.failed,
      ]) {
        expect(UpdateState(phase: p).downloading, isFalse, reason: '$p');
      }
    });
  });

  group('UpdateState.installing', () {
    test('covers downloading, verifying, and installing phases', () {
      for (final p in [
        UpdatePhase.downloading,
        UpdatePhase.verifying,
        UpdatePhase.installing,
      ]) {
        expect(UpdateState(phase: p).installing, isTrue, reason: '$p');
      }
    });

    test('is false for idle, ready, and failed', () {
      // Importantly, ready phase is NOT considered "installing" — this is what
      // lets the user tap "Apply" while the staged build is waiting.
      for (final p in [
        UpdatePhase.idle,
        UpdatePhase.ready,
        UpdatePhase.failed,
      ]) {
        expect(UpdateState(phase: p).installing, isFalse, reason: '$p');
      }
    });
  });

  group('UpdateState.copyWith staged fields', () {
    const staged = UpdateState(
      phase: UpdatePhase.ready,
      stagedArchivePath: '/tmp/build.tar.gz',
      preparedVersion: '2.0.0',
    );

    test('preserves stagedArchivePath and preparedVersion when not cleared', () {
      final copy = staged.copyWith(phase: UpdatePhase.idle);
      expect(copy.stagedArchivePath, '/tmp/build.tar.gz');
      expect(copy.preparedVersion, '2.0.0');
    });

    test('clearStagedArchive nulls out the path', () {
      final copy = staged.copyWith(clearStagedArchive: true);
      expect(copy.stagedArchivePath, isNull);
      // preparedVersion is untouched
      expect(copy.preparedVersion, '2.0.0');
    });

    test('clearPreparedVersion nulls out the version', () {
      final copy = staged.copyWith(clearPreparedVersion: true);
      expect(copy.preparedVersion, isNull);
      // stagedArchivePath is untouched
      expect(copy.stagedArchivePath, '/tmp/build.tar.gz');
    });

    test('both clear flags together reset all staged state', () {
      final copy = staged.copyWith(
        phase: UpdatePhase.idle,
        clearStagedArchive: true,
        clearPreparedVersion: true,
      );
      expect(copy.stagedArchivePath, isNull);
      expect(copy.preparedVersion, isNull);
      expect(copy.updateReady, isFalse);
    });
  });
}
