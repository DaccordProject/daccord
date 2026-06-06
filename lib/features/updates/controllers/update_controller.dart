import 'dart:convert';

import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'update_controller.g.dart';

/// Snapshot of the update checker.
@immutable
class UpdateState {
  const UpdateState({
    this.latest,
    this.checking = false,
    this.error,
    this.checkedOnce = false,
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

  /// Whether [latest] is newer than the running build.
  bool get updateAvailable =>
      latest != null && isNewerVersion(latest!.version, kAppVersion);

  UpdateState copyWith({
    AppRelease? latest,
    bool? checking,
    String? error,
    bool clearError = false,
    bool? checkedOnce,
  }) => UpdateState(
    latest: latest ?? this.latest,
    checking: checking ?? this.checking,
    error: clearError ? null : (error ?? this.error),
    checkedOnce: checkedOnce ?? this.checkedOnce,
  );
}

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a passive check throttled
/// to once an hour (gated on the auto-update-check setting) plus a manual check
/// from the Updates settings page. The client does not self-install — the UI
/// links to the release page for manual download.
@Riverpod(keepAlive: true)
class UpdateController extends _$UpdateController {
  static const _throttle = Duration(hours: 1);

  @override
  UpdateState build() => const UpdateState();

  /// Runs a passive check at startup if enabled and not checked within the
  /// throttle window. Safe to call repeatedly.
  Future<void> maybeCheckOnStartup() async {
    final settings = ref.read(settingsControllerProvider);
    if (!settings.autoUpdateCheck) return;
    final last = DateTime.fromMillisecondsSinceEpoch(
      settings.lastUpdateCheckMs,
    );
    final now = DateTime.now();
    if (now.difference(last) < _throttle) return;
    await check();
  }

  /// Fetches the latest release. [manual] checks bypass nothing here (the
  /// throttle lives in [maybeCheckOnStartup]); they just surface errors to the
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

  /// Dismisses the currently-available release so the banner stays hidden until
  /// a newer one ships.
  void dismissCurrent() {
    final version = state.latest?.version;
    if (version == null) return;
    ref
        .read(settingsControllerProvider.notifier)
        .setDismissedUpdateVersion(version);
  }

  void _stampChecked() {
    ref
        .read(settingsControllerProvider.notifier)
        .setLastUpdateCheckMs(DateTime.now().millisecondsSinceEpoch);
  }
}
