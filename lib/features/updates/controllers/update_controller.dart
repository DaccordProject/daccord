import 'dart:async';
import 'dart:convert';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/features/updates/services/update_installer.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:universal_platform/universal_platform.dart';

part 'update_controller.g.dart';

/// Where an in-place install currently is. Drives the update UI's progress and
/// disabled states; [idle] also covers "not started" and "completed on Android"
/// (where the system installer takes over and the app keeps running). [ready]
/// means the new build has been downloaded and verified in the background and is
/// staged for a one-click apply (restart-and-swap).
enum UpdatePhase { idle, downloading, verifying, ready, installing, failed }

/// Snapshot of the update checker.
@immutable
class UpdateState {
  const UpdateState({
    this.latest,
    this.checking = false,
    this.error,
    this.checkedOnce = false,
    this.dismissedVersion,
    this.phase = UpdatePhase.idle,
    this.progress = 0.0,
    this.installError,
    this.stagedArchivePath,
    this.preparedVersion,
  });

  /// The latest release fetched, or null if none/unknown.
  final AppRelease? latest;

  /// Whether a check is currently in flight.
  final bool checking;

  /// The last check's error message, or null on success.
  final String? error;

  /// Whether at least one check has completed (so the UI can distinguish
  /// "not checked yet" from "up to date").
  final bool checkedOnce;

  /// A version the user dismissed for *this session only* (cleared on restart).
  /// Distinct from the persistent "skip this version" preference.
  final String? dismissedVersion;

  /// Current phase of an in-place install (download → verify → swap).
  final UpdatePhase phase;

  /// Download progress (0..1) while [phase] is [UpdatePhase.downloading].
  final double progress;

  /// The last install failure's user-facing message, or null.
  final String? installError;

  /// Path to the downloaded-and-verified bundle staged for a one-click apply,
  /// set when [phase] reaches [UpdatePhase.ready]. Null until then.
  final String? stagedArchivePath;

  /// The version currently being prepared or staged (download → ready), used to
  /// dedupe repeated background prepares and to detect a stale staged archive
  /// when a newer release ships. Null when nothing has been prepared.
  final String? preparedVersion;

  /// Whether an install is actively in flight (download/verify/swap).
  bool get installing =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.installing;

  /// Whether a verified build is staged and one click away from being applied.
  bool get updateReady => phase == UpdatePhase.ready && stagedArchivePath != null;

  /// Whether [latest] is a newer build than the running one. Pre-releases are
  /// ignored unless this build is itself a pre-release (matching the reference
  /// updater); GitHub's `/releases/latest` already excludes pre-releases, so
  /// this is belt-and-suspenders.
  bool get updateAvailable {
    final r = latest;
    if (r == null || !isNewerVersion(r.version, kAppVersion)) return false;
    if (r.prerelease && !isPrerelease(kAppVersion)) return false;
    return true;
  }

  UpdateState copyWith({
    AppRelease? latest,
    bool? checking,
    String? error,
    bool clearError = false,
    bool? checkedOnce,
    String? dismissedVersion,
    UpdatePhase? phase,
    double? progress,
    String? installError,
    bool clearInstallError = false,
    String? stagedArchivePath,
    String? preparedVersion,
    bool clearStaged = false,
  }) => UpdateState(
    latest: latest ?? this.latest,
    checking: checking ?? this.checking,
    error: clearError ? null : (error ?? this.error),
    checkedOnce: checkedOnce ?? this.checkedOnce,
    dismissedVersion: dismissedVersion ?? this.dismissedVersion,
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    installError: clearInstallError ? null : (installError ?? this.installError),
    stagedArchivePath: clearStaged ? null : (stagedArchivePath ?? this.stagedArchivePath),
    preparedVersion: clearStaged ? null : (preparedVersion ?? this.preparedVersion),
  );
}

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a startup check plus an
/// hourly periodic check (both gated on the auto-update-check setting and
/// throttled), a manual check, session-dismiss + persistent skip, and
/// platform-aware download links.
///
/// In-place self-replacement is split for a one-click experience: as soon as a
/// check finds a newer build, [prepareUpdate] downloads + verifies the matching
/// bundle in the background and stages it ([UpdatePhase.ready]); the user's
/// single click then calls [applyUpdate], where a detached helper swaps the
/// binary tree and relaunches (see [UpdateInstaller]). On Android the staged APK
/// is handed to the system installer. Platforms without an in-place path (or
/// older releases) still fall back to a plain download link, and web prompts a
/// service-worker reload.
@Riverpod(keepAlive: true)
class UpdateController extends _$UpdateController {
  static const _throttle = Duration(hours: 1);
  Timer? _timer;

  @override
  UpdateState build() {
    ref.onDispose(() => _timer?.cancel());
    return const UpdateState();
  }

  /// Runs a startup check (throttled, gated on the setting) and arms the hourly
  /// periodic check. Safe to call repeatedly — the timer is armed only once.
  Future<void> maybeCheckOnStartup() async {
    // App Store builds update through the store; never check GitHub or arm the
    // periodic timer (see [kAppStoreBuild]).
    if (kAppStoreBuild) return;
    _timer ??= Timer.periodic(_throttle, (_) {
      if (ref.read(settingsControllerProvider).autoUpdateCheck) check();
    });
    final settings = ref.read(settingsControllerProvider);
    if (!settings.autoUpdateCheck) return;
    final last = DateTime.fromMillisecondsSinceEpoch(
      settings.lastUpdateCheckMs,
    );
    if (DateTime.now().difference(last) < _throttle) return;
    await check();
  }

  /// Fetches the latest release. [manual] checks just surface errors to the
  /// user. Returns the resulting state.
  Future<UpdateState> check({bool manual = false}) async {
    if (state.checking) return state;
    state = state.copyWith(checking: true, clearError: true);
    try {
      final res = await http
          .get(
            Uri.parse(kGithubLatestReleaseUrl),
            headers: {
              'User-Agent': 'daccord/$kAppVersion',
              'Accept': 'application/vnd.github+json',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 404) {
        // No releases published yet — treat as "up to date", not an error.
        _stampChecked();
        state = state.copyWith(checking: false, checkedOnce: true);
        return state;
      }
      if (res.statusCode != 200) {
        state = state.copyWith(
          checking: false,
          checkedOnce: true,
          error: 'GitHub returned ${res.statusCode}',
        );
        return state;
      }
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) {
        state = state.copyWith(
          checking: false,
          checkedOnce: true,
          error: 'Invalid response',
        );
        return state;
      }
      final release = AppRelease.fromJson(json);
      _stampChecked();
      state = state.copyWith(
        latest: release,
        checking: false,
        checkedOnce: true,
        clearError: true,
      );
      // Pull the new build down in the background so the user only ever clicks
      // once (to apply). No-op on platforms without an in-place install.
      unawaited(prepareUpdate());
      return state;
    } catch (e) {
      debugPrint('Update check failed: $e');
      state = state.copyWith(
        checking: false,
        checkedOnce: true,
        error: manual ? 'Could not reach the update server.' : null,
      );
      return state;
    }
  }

  /// Dismisses the current release for this session only (banner hides until
  /// restart or a newer release).
  void dismissCurrent() {
    final version = state.latest?.version;
    if (version == null) return;
    state = state.copyWith(dismissedVersion: version);
  }

  /// Permanently skips the current release (persisted; suppressed until a newer
  /// one ships).
  void skipCurrent() {
    final version = state.latest?.version;
    if (version == null) return;
    ref
        .read(settingsControllerProvider.notifier)
        .setSkippedUpdateVersion(version);
  }

  /// File extensions the in-place installer can actually apply for the current
  /// platform, in priority order. Kept in lockstep with [UpdateInstaller]: it
  /// extracts a `.tar.gz`/`.zip` bundle on Linux/Windows, mounts a `.dmg` on
  /// macOS, and hands a `.apk` to the system installer on Android. Package
  /// formats the swap helper can't apply (`.deb`/`.rpm`/`.appimage`, setup
  /// `.exe`/`.msi`) are deliberately excluded — they're download-only.
  List<String> get _installableExts {
    if (UniversalPlatform.isAndroid) return const ['.apk'];
    if (UniversalPlatform.isWindows) return const ['.zip'];
    if (UniversalPlatform.isMacOS) return const ['.dmg'];
    if (UniversalPlatform.isLinux) return const ['.tar.gz'];
    return const [];
  }

  /// Extensions worth offering as a direct download for the platform, in
  /// priority order. A superset of [_installableExts] that also includes
  /// package formats a user can install manually but the swap helper can't
  /// apply in place.
  List<String> get _downloadExts {
    if (UniversalPlatform.isAndroid) return const ['.apk'];
    if (UniversalPlatform.isWindows) return const ['.zip', '.exe', '.msi'];
    if (UniversalPlatform.isMacOS) return const ['.dmg', '.pkg', '.zip'];
    if (UniversalPlatform.isLinux) {
      return const ['.tar.gz', '.deb', '.rpm', '.appimage'];
    }
    return const [];
  }

  /// First release asset whose name ends with one of [exts], honouring [exts]
  /// as a priority list (GitHub returns assets in upload/alphabetical order, so
  /// iterating assets first would ignore our preference — e.g. picking the
  /// unextractable `.deb` over the `.tar.gz`). Returns null when none match.
  AppReleaseAsset? _assetForExts(List<String> exts) {
    final assets = state.latest?.assets ?? const [];
    if (assets.isEmpty) return null;
    for (final ext in exts) {
      final match = assets.firstWhereOrNull(
        (a) => a.name.toLowerCase().endsWith(ext),
      );
      if (match != null) return match;
    }
    return null;
  }

  /// The download URL of the best release asset for the current platform, or
  /// null when none is found (the caller then falls back to the release page).
  /// Always null on web/iOS (no self-served binary applies).
  String? platformAssetUrl() {
    if (UniversalPlatform.isWeb || UniversalPlatform.isIOS) return null;
    return _assetForExts(_downloadExts)?.url;
  }

  /// The release asset the in-place installer can apply for the current
  /// platform, or null when none applies (the UI then offers a plain download).
  AppReleaseAsset? platformAsset() => _assetForExts(_installableExts);

  /// Whether the running platform supports an in-place download-and-install
  /// (desktop binary swap or Android APK install), and a matching asset exists.
  bool get canInstallInPlace =>
      !kAppStoreBuild && UpdateInstaller.isSupported && platformAsset() != null;

  /// Downloads and verifies the matching platform asset in the background,
  /// leaving it staged at [UpdatePhase.ready] for a one-click [applyUpdate].
  /// Triggered automatically after a check finds a newer build. A no-op when the
  /// platform can't self-install, the version is skipped, or a prepare for the
  /// current version is already in flight or done — so it's safe to call on
  /// every periodic check.
  Future<void> prepareUpdate() async {
    if (!canInstallInPlace || !state.updateAvailable) return;
    final version = state.latest?.version;
    if (version == null) return;
    final skipped = ref.read(settingsControllerProvider).skippedUpdateVersion;
    if (version == skipped) return;
    // Already downloading/verifying/installing, or already staged for this same
    // version — don't re-download. The second guard also covers the case where
    // a staged archive survived an Android install hand-off before the idle
    // transition cleared it (belt-and-suspenders for any future callers).
    if (state.installing) return;
    if (state.preparedVersion == version && state.stagedArchivePath != null) return;
    final asset = platformAsset();
    if (asset == null) return;
    try {
      final archivePath = await _downloadAndVerify(asset);
      state = state.copyWith(
        phase: UpdatePhase.ready,
        stagedArchivePath: archivePath,
        preparedVersion: version,
      );
    } on UpdateInstallException catch (e) {
      state = state.copyWith(phase: UpdatePhase.failed, installError: e.message);
    } catch (e) {
      debugPrint('Background update download failed: $e');
      state = state.copyWith(
        phase: UpdatePhase.failed,
        installError: 'Could not download the update.',
      );
    }
  }

  /// Applies the update in place: on desktop the app quits and the swap helper
  /// relaunches the new build; on Android the system package installer takes
  /// over. Uses the build already staged by [prepareUpdate] when present (the
  /// one-click path); otherwise downloads + verifies first. Surfaces
  /// progress/errors via [state].
  Future<void> applyUpdate() async {
    if (state.installing) return;
    final installer = UpdateInstaller();
    try {
      var archivePath = state.stagedArchivePath;
      // Re-download if nothing is staged, or the staged build is for an older
      // release than the one now offered.
      if (archivePath == null ||
          state.preparedVersion != state.latest?.version) {
        final asset = platformAsset();
        if (asset == null) {
          state = state.copyWith(
            phase: UpdatePhase.failed,
            installError: 'No downloadable build for this platform.',
          );
          return;
        }
        archivePath = await _downloadAndVerify(asset);
      }

      state = state.copyWith(phase: UpdatePhase.installing);
      // Desktop: install() quits the process and never returns here. Android:
      // returns once the system installer has been launched.
      await installer.install(archivePath, onReadyToQuit: () async {});
      // Android only: clear staged state so a future re-check can re-stage
      // if the user cancelled the system installer.
      state = state.copyWith(phase: UpdatePhase.idle, clearStaged: true);
    } on UpdateInstallException catch (e) {
      state = state.copyWith(
        phase: UpdatePhase.failed,
        installError: e.message,
      );
    } catch (e) {
      debugPrint('Install failed: $e');
      state = state.copyWith(
        phase: UpdatePhase.failed,
        installError: 'Update failed. Try downloading it manually instead.',
      );
    }
  }

  /// Downloads [asset] to a temp file (reporting progress) and verifies it
  /// against the release's published checksums when present. Returns the staged
  /// file path; throws [UpdateInstallException] on download/verify failure.
  Future<String> _downloadAndVerify(AppReleaseAsset asset) async {
    final installer = UpdateInstaller();
    state = state.copyWith(
      phase: UpdatePhase.downloading,
      progress: 0,
      clearInstallError: true,
    );
    final archivePath = await installer.download(
      asset.url,
      fileName: asset.name,
      onProgress: (value) => state = state.copyWith(progress: value),
    );

    final expected = await _expectedSha(asset.name);
    if (expected != null) {
      state = state.copyWith(phase: UpdatePhase.verifying);
      await installer.verify(archivePath, expected);
    } else {
      debugPrint('No published checksum for ${asset.name}; skipping verify.');
    }
    return archivePath;
  }

  /// Looks up the expected SHA-256 for [assetName] from the release's
  /// `SHA256SUMS` asset (lines of `<hex>  <filename>`). Returns null when the
  /// release publishes no checksums or the file isn't listed — callers then
  /// proceed without verification (older releases predate checksums).
  Future<String?> _expectedSha(String assetName) async {
    final sums = (state.latest?.assets ?? const []).firstWhereOrNull(
      (a) => a.name.toUpperCase().contains('SHA256SUMS'),
    );
    if (sums == null) return null;
    try {
      final res = await http
          .get(
            Uri.parse(sums.url),
            headers: {'User-Agent': 'daccord/$kAppVersion'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      for (final line in const LineSplitter().convert(res.body)) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2 && p.basename(parts.last) == assetName) {
          return parts.first;
        }
      }
    } catch (e) {
      debugPrint('Checksum fetch failed: $e');
    }
    return null;
  }

  void _stampChecked() {
    ref
        .read(settingsControllerProvider.notifier)
        .setLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);
  }
}
