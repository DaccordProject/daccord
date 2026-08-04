import 'dart:async';
import 'dart:convert';

import 'package:bonfire/features/updates/models/app_release.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'release_notes_controller.g.dart';

/// Why (or why not) the "What's new" notes should be shown on this launch,
/// derived from the last version we showed notes for vs. the running build.
enum ReleaseNotesTrigger {
  /// Nothing recorded yet — a fresh install (or the first launch after this
  /// feature shipped). Notes would read as noise, so they're suppressed and the
  /// marker is seeded with the running version. Onboarding is #175's job.
  firstInstall,

  /// Same version as the last launch: notes were already shown (or suppressed)
  /// for this build.
  unchanged,

  /// The running build is newer than the one we last recorded → show the notes.
  updated,

  /// The running build is *older* than the one we last recorded (a rollback, a
  /// downgrade install, or an older portable copy launched by mistake). There's
  /// nothing "new" to announce, so no notes — but the marker is restamped to the
  /// running version, so upgrading forward again shows that release's notes.
  downgraded,

  /// The running version is unknown (`initAppInfo` failed, leaving the `0.0.0`
  /// fallback). Neither show nor stamp — a bogus `0.0.0` marker would fake an
  /// "update" on the next launch.
  unknownVersion,
}

/// Pure "did we just update?" decision, split out from the controller so it can
/// be exercised without Hive or a network. [lastSeenVersion] is the persisted
/// marker (empty when absent), [currentVersion] the running build.
ReleaseNotesTrigger releaseNotesTrigger({
  required String lastSeenVersion,
  required String currentVersion,
}) {
  final current = normalizeVersion(currentVersion);
  if (current.isEmpty || current == '0.0.0') {
    return ReleaseNotesTrigger.unknownVersion;
  }
  final last = normalizeVersion(lastSeenVersion);
  if (last.isEmpty) return ReleaseNotesTrigger.firstInstall;
  if (last == current) return ReleaseNotesTrigger.unchanged;
  if (isNewerVersion(current, last)) return ReleaseNotesTrigger.updated;
  if (isNewerVersion(last, current)) return ReleaseNotesTrigger.downgraded;
  // Same numeric core, different suffix (e.g. `1.2.0-beta.1` → `1.2.0`):
  // isNewerVersion ignores the suffix, but the build did change — treat it as
  // an update rather than silently swallowing the notes.
  return ReleaseNotesTrigger.updated;
}

/// Snapshot of the release notes for the *running* build.
@immutable
class ReleaseNotesState {
  const ReleaseNotesState({
    this.loading = false,
    this.release,
    this.checked = false,
  });

  /// Whether a fetch is in flight.
  final bool loading;

  /// The fetched release for the running version, or null when unknown / the
  /// fetch failed / GitHub has no release for this tag.
  final AppRelease? release;

  /// Whether a fetch has completed (so the UI can tell "not looked yet" from
  /// "looked and found nothing").
  final bool checked;

  /// Whether there is a non-empty body worth rendering.
  bool get hasNotes => (release?.notes.trim().isNotEmpty ?? false);

  ReleaseNotesState copyWith({
    bool? loading,
    AppRelease? release,
    bool clearRelease = false,
    bool? checked,
  }) => ReleaseNotesState(
    loading: loading ?? this.loading,
    release: clearRelease ? null : (release ?? this.release),
    checked: checked ?? this.checked,
  );
}

/// Shows the release notes for the build the user is *now* running, once, after
/// an update is applied (#183).
///
/// The updater already fetches notes for the release it's about to install, but
/// the one-click flow (stage in the background → tap → relaunch) means most
/// users never read them, and the staged [AppRelease] dies with the old process.
/// So this fetches the notes for the running tag instead
/// ([kGithubReleaseByTagUrl]) — which also covers updates applied outside the
/// app (package manager, Play Store, a fresh download).
///
/// **Persistence.** The last version we showed notes for lives in the existing
/// `accord-settings` Hive box under its own [_seenKey] (no new box). It is
/// deliberately *not* part of `AccordSettings`: settings are exportable /
/// importable between devices, and carrying a "seen" marker across machines
/// would suppress (or fake) notes on the receiving one.
///
/// **App Store / Play builds.** [kAppStoreBuild] disables the *updater*
/// (downloading and running executable code outside the store); reading a
/// release's markdown body is not that, so notes still show on those builds —
/// the user updated through the store and still deserves to know what changed.
/// Nothing here can install anything, and when the fetch fails or the release
/// has no body nothing is shown at all (never a broken/empty sheet).
@Riverpod(keepAlive: true)
class ReleaseNotesController extends _$ReleaseNotesController {
  static const _boxName = 'accord-settings';
  static const _seenKey = 'release-notes-seen-version';
  static const _timeout = Duration(seconds: 15);

  /// Overridable HTTP client so tests can stub the GitHub fetch.
  @visibleForTesting
  static http.Client? debugHttpClient;

  /// Guards against a second startup evaluation (the provider is keepAlive, but
  /// the caller is a post-frame callback that can run again after a restart).
  bool _startupHandled = false;

  @override
  ReleaseNotesState build() => const ReleaseNotesState();

  /// The version we last showed (or suppressed) notes for; empty when none.
  String get lastSeenVersion {
    if (!Hive.isBoxOpen(_boxName)) return '';
    final raw = Hive.box(_boxName).get(_seenKey);
    return raw is String ? raw : '';
  }

  /// Stamps [version] (default: the running build) as seen, so the notes are
  /// never shown twice for the same version.
  void markSeen([String? version]) {
    if (!Hive.isBoxOpen(_boxName)) return;
    Hive.box(_boxName).put(_seenKey, version ?? kAppVersion);
  }

  /// How this launch compares to the last one.
  ReleaseNotesTrigger get startupTrigger => releaseNotesTrigger(
    lastSeenVersion: lastSeenVersion,
    currentVersion: kAppVersion,
  );

  /// Startup path: decides whether this launch just updated, stamps the marker
  /// so it never repeats (even on a failed fetch), and returns the release to
  /// show — or null when there's nothing to show. Never throws; never blocks
  /// on more than one HTTP round trip.
  Future<AppRelease?> maybeLoadOnStartup() async {
    if (_startupHandled) return null;
    _startupHandled = true;
    final trigger = startupTrigger;
    // Unknown running version: don't stamp (a `0.0.0` marker would fake an
    // update next launch) and don't show.
    if (trigger == ReleaseNotesTrigger.unknownVersion) return null;
    markSeen();
    if (trigger != ReleaseNotesTrigger.updated) return null;
    final release = await loadNotesForCurrentVersion();
    if (release == null || release.notes.trim().isEmpty) return null;
    return release;
  }

  /// Fetches (and caches) the GitHub release for the running version. Also used
  /// by the Updates page's "What's new" action so a dismissed dialog isn't the
  /// only chance to read the notes. Returns null when there's no such release,
  /// the body is missing, or the fetch failed — callers fail silent.
  Future<AppRelease?> loadNotesForCurrentVersion({bool force = false}) async {
    if (state.loading) return state.release;
    if (state.checked && !force) return state.release;
    state = state.copyWith(loading: true);
    final release = await _fetchRelease(kAppVersion);
    state = ReleaseNotesState(loading: false, release: release, checked: true);
    return release;
  }

  Future<AppRelease?> _fetchRelease(String version) async {
    final normalized = normalizeVersion(version);
    if (normalized.isEmpty || normalized == '0.0.0') return null;
    final uri = Uri.parse(kGithubReleaseByTagUrl(normalized));
    const headers = <String, String>{'Accept': 'application/vnd.github+json'};
    try {
      final client = debugHttpClient;
      final res = await (client == null
              ? http.get(uri, headers: {
                  ...headers,
                  'User-Agent': 'daccord/$kAppVersion',
                })
              : client.get(uri, headers: {
                  ...headers,
                  'User-Agent': 'daccord/$kAppVersion',
                }))
          .timeout(_timeout);
      // 404 = unreleased/dev build or a tag that doesn't exist — not an error.
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      if (json is! Map<String, dynamic>) return null;
      return AppRelease.fromJson(json);
    } catch (e) {
      debugPrint('Release notes fetch failed: $e');
      return null;
    }
  }
}
