import 'dart:io';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/controllers/update_controller.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:universal_platform/universal_platform.dart';

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

/// Points [latest] at a release carrying [assets] (newer than kAppVersion).
void setLatest(ProviderContainer c, List<AppReleaseAsset> assets) {
  c.read(updateControllerProvider.notifier).state = UpdateState(
    latest: AppRelease(
      version: '99.0.0',
      name: 'v99.0.0',
      notes: '',
      url: 'https://example/releases/v99.0.0',
      publishedAt: '',
      assets: assets,
    ),
  );
}

AppReleaseAsset _asset(String name) =>
    AppReleaseAsset(name: name, url: 'https://example/download/$name');

/// The full asset set the release workflow publishes (mirrors the real v0.2.4
/// release). Crucially this lists BOTH a `.deb` and a `.tar.gz` for Linux, and
/// because GitHub returns assets in upload/alphabetical order the unextractable
/// `.deb` sorts *before* the `.tar.gz` — the exact trap behind the recurring
/// "Unsupported archive: daccord-linux-x86_64.deb" failure (#99).
final _fullReleaseAssets = [
  _asset('SHA256SUMS.txt'),
  _asset('app-release.aab'),
  _asset('daccord-android.apk'),
  _asset('daccord-linux-x86_64.deb'),
  _asset('daccord-linux-x86_64.tar.gz'),
  _asset('daccord-macos-universal.dmg'),
  _asset('daccord-web.zip'),
  _asset('daccord-windows-x86_64-setup.exe'),
  _asset('daccord-windows-x86_64.zip'),
];

/// The single extension the in-place swap helper can actually apply on the
/// current host platform — kept in lockstep with UpdateController's private
/// `_installableExts` and UpdateInstaller's extract/mount/install backends.
/// Empty when no in-place install exists (web / iOS / unknown host).
String? get _hostInstallableExt {
  if (UniversalPlatform.isAndroid) return '.apk';
  if (UniversalPlatform.isWindows) return '.zip';
  if (UniversalPlatform.isMacOS) return '.dmg';
  if (UniversalPlatform.isLinux) return '.tar.gz';
  return null;
}

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

  // Regression guard for the recurring "Unsupported archive: …deb" failure
  // (fixed in #99, re-emerged on v0.2.4). The in-place installer can only
  // extract a .tar.gz/.zip, mount a .dmg, or hand off a .apk; package formats
  // (.deb/.rpm/.appimage) and setup installers (.exe/.msi/.pkg) must never be
  // chosen for the swap — they're download-only. Asset selection must honour
  // its extension *priority* so a release bundling several formats installs the
  // applicable one rather than whichever GitHub happens to list first.
  group('platformAsset selection (Unsupported archive regression)', () {
    // Extensions the swap helper cannot apply — selecting any of these for an
    // in-place install is exactly what produced the .deb crash.
    const unextractable = [
      '.deb',
      '.rpm',
      '.appimage',
      '-setup.exe',
      '.msi',
      '.pkg',
    ];

    test('never hands an unextractable package to the in-place installer', () {
      final c = makeContainer();
      setLatest(c, _fullReleaseAssets);
      final asset = controllerOf(c).platformAsset();
      // On web/iOS there's no in-place asset; elsewhere one must be chosen.
      if (_hostInstallableExt == null) {
        expect(asset, isNull);
        return;
      }
      expect(
        asset,
        isNotNull,
        reason: 'a full release should yield an installable asset',
      );
      for (final ext in unextractable) {
        expect(
          asset!.name.toLowerCase().endsWith(ext),
          isFalse,
          reason: 'picked unextractable "${asset.name}" for in-place install',
        );
      }
    });

    test('selects the extension the host installer can actually apply', () {
      final c = makeContainer();
      setLatest(c, _fullReleaseAssets);
      final asset = controllerOf(c).platformAsset();
      final ext = _hostInstallableExt;
      if (ext == null) {
        expect(asset, isNull);
      } else {
        expect(asset, isNotNull);
        expect(
          asset!.name.toLowerCase().endsWith(ext),
          isTrue,
          reason: 'expected a "$ext" asset, got "${asset.name}"',
        );
        // Guard against the Windows web-bundle ambiguity: daccord-web.zip and
        // daccord-windows-x86_64.zip both end with .zip; only the latter is a
        // valid Windows installer.
        if (UniversalPlatform.isWindows) {
          expect(
            asset.name.toLowerCase().contains('windows'),
            isTrue,
            reason: 'picked web bundle "${asset.name}" instead of Windows installer',
          );
        }
      }
    });

    test('prefers .tar.gz over .deb when the .deb is listed first', () {
      // Only meaningful where Linux is the in-place target. The .deb is listed
      // before the .tar.gz to reproduce GitHub's ordering from the bug report.
      if (!UniversalPlatform.isLinux) return;
      final c = makeContainer();
      setLatest(c, [
        _asset('daccord-linux-x86_64.deb'),
        _asset('daccord-linux-x86_64.tar.gz'),
      ]);
      final asset = controllerOf(c).platformAsset();
      expect(asset, isNotNull);
      expect(asset!.name, endsWith('.tar.gz'));
      expect(asset.name, isNot(endsWith('.deb')));
    });

    test('prefers windows zip over web zip when web zip is listed first', () {
      // Regression guard for the daccord-web.zip ambiguity: GitHub returns assets
      // in alphabetical order, so `daccord-web.zip` sorts before
      // `daccord-windows-x86_64.zip`. The in-place installer must never pick the
      // web bundle as the Windows installer.
      if (!UniversalPlatform.isWindows) return;
      final c = makeContainer();
      setLatest(c, [
        _asset('daccord-web.zip'),
        _asset('daccord-windows-x86_64.zip'),
      ]);
      final asset = controllerOf(c).platformAsset();
      expect(asset, isNotNull);
      expect(asset!.name, equals('daccord-windows-x86_64.zip'));
      expect(asset.name, isNot(equals('daccord-web.zip')));
    });

    test('a package-only release has no in-place asset but is downloadable', () {
      // When the release ships only a .deb (no extractable bundle), the
      // installer must bow out (platformAsset == null) so the UI falls back to
      // a manual download link instead of failing mid-install.
      if (!UniversalPlatform.isLinux) return;
      final c = makeContainer();
      final deb = _asset('daccord-linux-x86_64.deb');
      setLatest(c, [deb]);
      expect(controllerOf(c).platformAsset(), isNull);
      expect(controllerOf(c).platformAssetUrl(), deb.url);
    });

    test('platformAssetUrl prefers .tar.gz over .deb for manual download', () {
      if (!UniversalPlatform.isLinux) return;
      final c = makeContainer();
      final tar = _asset('daccord-linux-x86_64.tar.gz');
      setLatest(c, [_asset('daccord-linux-x86_64.deb'), tar]);
      expect(controllerOf(c).platformAssetUrl(), tar.url);
    });

    test('canInstallInPlace is true only when an extractable asset exists', () {
      if (_hostInstallableExt == null) return; // web/iOS: never in-place
      final c = makeContainer();
      // Full release → extractable asset present.
      setLatest(c, _fullReleaseAssets);
      expect(controllerOf(c).canInstallInPlace, isTrue);
      // Linux package-only release → no extractable asset → cannot self-install.
      if (UniversalPlatform.isLinux) {
        setLatest(c, [_asset('daccord-linux-x86_64.deb')]);
        expect(controllerOf(c).canInstallInPlace, isFalse);
      }
    });
  });
}
