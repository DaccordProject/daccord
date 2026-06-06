import 'dart:async';
import 'dart:convert';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:universal_platform/universal_platform.dart';

part 'update_controller.g.dart';

/// Snapshot of the update checker.
@immutable
class UpdateState {
  const UpdateState({
    this.latest,
    this.checking = false,
    this.error,
    this.checkedOnce = false,
    this.dismissedVersion,
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
  }) => UpdateState(
    latest: latest ?? this.latest,
    checking: checking ?? this.checking,
    error: clearError ? null : (error ?? this.error),
    checkedOnce: checkedOnce ?? this.checkedOnce,
    dismissedVersion: dismissedVersion ?? this.dismissedVersion,
  );
}

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a startup check plus an
/// hourly periodic check (both gated on the auto-update-check setting and
/// throttled), a manual check, session-dismiss + persistent skip, and
/// platform-aware download links.
///
/// In-place self-replacement (binary swap + relaunch on desktop, APK install on
/// Android) is intentionally deferred — it needs untestable per-platform native
/// machinery. For now an available update links straight to the matching
/// platform asset's download (or the release page), and web prompts a refresh.
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

  /// The download URL of the release asset matching the current platform, or
  /// null when none is found (the caller then falls back to the release page).
  /// Always null on web (no downloadable binary applies).
  String? platformAssetUrl() {
    final assets = state.latest?.assets ?? const [];
    if (assets.isEmpty || UniversalPlatform.isWeb) return null;
    bool hasExt(AppReleaseAsset a, List<String> exts) {
      final n = a.name.toLowerCase();
      return exts.any(n.endsWith);
    }

    List<String> exts;
    if (UniversalPlatform.isAndroid) {
      exts = const ['.apk'];
    } else if (UniversalPlatform.isWindows) {
      exts = const ['.exe', '.msi', '.zip'];
    } else if (UniversalPlatform.isMacOS) {
      exts = const ['.dmg', '.pkg', '.zip'];
    } else if (UniversalPlatform.isLinux) {
      exts = const ['.appimage', '.tar.gz', '.deb', '.rpm'];
    } else if (UniversalPlatform.isIOS) {
      return null; // iOS updates come from the App Store.
    } else {
      return null;
    }
    for (final a in assets) {
      if (hasExt(a, exts)) return a.url;
    }
    return null;
  }

  void _stampChecked() {
    ref
        .read(settingsControllerProvider.notifier)
        .setLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);
  }
}
