import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_controller.g.dart';

/// Why (or why not) the first-launch walkthrough should run.
enum OnboardingTrigger {
  /// Nothing stored and no trace of a previous life → show the tour.
  firstLaunch,

  /// The tour has already been shown (or skipped) on this install.
  alreadySeen,

  /// No marker, but this install has clearly been used before — it predates the
  /// tour shipping. Showing a "welcome, here is a rail" walkthrough to someone
  /// with five spaces and a year of history is noise, so the marker is stamped
  /// and the tour never fires. They can still replay it from Settings.
  existingUser,

  /// Explicitly requested from Settings; ignores the marker entirely.
  replay,
}

/// Pure gating decision, split out so first-launch / second-launch / replay /
/// upgrade can be exercised without Hive.
OnboardingTrigger onboardingTrigger({
  required bool hasSeen,
  required bool existingUser,
  bool force = false,
}) {
  if (force) return OnboardingTrigger.replay;
  if (hasSeen) return OnboardingTrigger.alreadySeen;
  if (existingUser) return OnboardingTrigger.existingUser;
  return OnboardingTrigger.firstLaunch;
}

/// Whether this install has been used before, from the traces a previous launch
/// leaves behind. Any one of these is conclusive; a genuinely fresh install (or
/// a brand-new device profile) has none of them *at startup*, which is the only
/// moment they can be trusted — signing in writes a session, and opening the
/// first channel writes a last-selection, within a second of the home screen
/// mounting.
bool onboardingLooksLikeExistingUser({
  required bool hasPersistedSession,
  required bool hasSavedAccounts,
  required bool hasCachedSpaces,
  required bool hasPriorSelection,
}) =>
    hasPersistedSession ||
    hasSavedAccounts ||
    hasCachedSpaces ||
    hasPriorSelection;

/// Owns the first-launch walkthrough's persistence and gating (#175).
///
/// **Persistence.** The seen-marker lives in the existing `accord-settings` Hive
/// box under its own [seenKey] (no new box), exactly as the release-notes
/// marker does. It is deliberately *not* a field on `AccordSettings`: settings
/// are exportable/importable between devices, and a "seen" marker that travels
/// with them would suppress the tour on a machine the user has never used.
///
/// The value stored is the app version that showed the tour, which costs
/// nothing and leaves the door open for a "this release changed the layout,
/// re-introduce it" decision later. Any non-empty value counts as seen.
@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  static const String boxName = 'accord-settings';
  static const String seenKey = 'onboarding-seen-version';

  static String get _activeSettingsBoxName =>
      ProfileStore.activeSettingsBoxName;

  /// Overridable marker storage, for widget tests.
  ///
  /// A Hive write issued from inside a `testWidgets` body never completes: the
  /// real file I/O finishes on the real event loop but its continuation is a
  /// microtask captured by the test binding's `FakeAsync`, so the box's write
  /// lock is held forever and any later `flush`/`close`/`deleteFromDisk`
  /// deadlocks. Pointing the marker at a plain map keeps the end-to-end
  /// push → skip → stamp path testable without disk. Null in production.
  @visibleForTesting
  static Map<String, Object?>? debugStore;

  /// Whether this launch belonged to an existing user, captured once at startup
  /// before sign-in can write a session (see [captureLaunchState]).
  bool? _existingUserAtLaunch;

  /// One-shot guard: the startup hook is a post-frame callback that can run
  /// again after an in-app restart (profile switch), and the provider survives.
  bool _startupHandled = false;

  @override
  bool build() => false;

  // -- persistence ----------------------------------------------------------

  /// The app version that last showed the tour; empty when it never has.
  String get seenVersion {
    final store = debugStore;
    final activeBoxName = _activeSettingsBoxName;
    final raw = store != null
        ? store[seenKey]
        : (Hive.isBoxOpen(activeBoxName)
              ? Hive.box(activeBoxName).get(seenKey)
              : null);
    return raw is String ? raw : '';
  }

  /// Whether the walkthrough has been shown (or skipped) on this install.
  bool get hasSeenTour => seenVersion.isNotEmpty;

  /// Stamps the tour as seen. Called when it finishes *and* when it is skipped —
  /// a skip is an answer — and when an existing user is detected.
  void markSeen([String? version]) {
    // kAppVersion can still be the '0.0.0' fallback if `initAppInfo` failed;
    // that is fine here, since only emptiness means "never shown".
    final value = version ?? kAppVersion;
    final store = debugStore;
    if (store != null) {
      store[seenKey] = value;
      return;
    }
    final activeBoxName = _activeSettingsBoxName;
    if (!Hive.isBoxOpen(activeBoxName)) return;
    Hive.box(activeBoxName).put(seenKey, value);
  }

  /// Clears the marker, so the next launch offers the tour again. Not used by
  /// the Settings replay (which shows it immediately instead), but it is what a
  /// "reset the app" flow would want.
  void clearSeen() {
    final store = debugStore;
    if (store != null) {
      store.remove(seenKey);
      return;
    }
    final activeBoxName = _activeSettingsBoxName;
    if (!Hive.isBoxOpen(activeBoxName)) return;
    Hive.box(activeBoxName).delete(seenKey);
  }

  // -- gating ---------------------------------------------------------------

  /// Reads the "has this install been used before" traces out of Hive *now*.
  /// Prefer [existingUserAtLaunch], which freezes this at startup.
  bool readLooksLikeExistingUser() {
    Map<dynamic, dynamic>? settings;
    final settingsBoxName = _activeSettingsBoxName;
    final sessionBoxName = ProfileStore.activeSessionBoxName;
    if (Hive.isBoxOpen(settingsBoxName)) {
      final raw = Hive.box(settingsBoxName).get('settings');
      if (raw is Map) settings = raw;
    }
    final lastSpace = settings?['lastSpaceId'];
    final lastChannel = settings?['lastChannelId'];
    return onboardingLooksLikeExistingUser(
      hasPersistedSession:
          Hive.isBoxOpen(sessionBoxName) &&
          Hive.box(sessionBoxName).get('session') != null,
      hasSavedAccounts:
          Hive.isBoxOpen(sessionBoxName) &&
          (Hive.box(sessionBoxName).get('accounts') as Map?)?.isNotEmpty ==
              true,
      hasCachedSpaces:
          Hive.isBoxOpen('space-cache') && Hive.box('space-cache').isNotEmpty,
      hasPriorSelection:
          (lastSpace is String && lastSpace.isNotEmpty) ||
          (lastChannel is String && lastChannel.isNotEmpty),
    );
  }

  /// Freezes the "existing user?" answer. Must be called at startup, before the
  /// sign-in flow persists a session or the home screen persists a selection —
  /// after that every user looks like an existing one.
  void captureLaunchState() {
    _existingUserAtLaunch ??= readLooksLikeExistingUser();
  }

  /// The frozen answer, capturing it now if nobody has yet.
  bool get existingUserAtLaunch {
    captureLaunchState();
    return _existingUserAtLaunch!;
  }

  /// What this launch should do, ignoring the one-shot guard.
  OnboardingTrigger get startupTrigger => onboardingTrigger(
    hasSeen: hasSeenTour,
    existingUser: existingUserAtLaunch,
  );

  /// The startup decision, once per launch. Returns null on every call after the
  /// first so a re-entrant post-frame callback can't queue a second tour.
  OnboardingTrigger? consumeStartupTrigger() {
    if (_startupHandled) return null;
    _startupHandled = true;
    return startupTrigger;
  }

  /// Test hook: forget that the startup decision was already taken.
  @visibleForTesting
  void resetStartupGuard() {
    _startupHandled = false;
    _existingUserAtLaunch = null;
  }

  // -- live state -----------------------------------------------------------

  /// Marks the tour route as on/off screen.
  void setActive(bool active) {
    if (state == active) return;
    state = active;
  }
}
