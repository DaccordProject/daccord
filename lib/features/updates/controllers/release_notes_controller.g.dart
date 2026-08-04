// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_notes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(ReleaseNotesController)
const releaseNotesControllerProvider = ReleaseNotesControllerProvider._();

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
final class ReleaseNotesControllerProvider
    extends $NotifierProvider<ReleaseNotesController, ReleaseNotesState> {
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
  const ReleaseNotesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'releaseNotesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$releaseNotesControllerHash();

  @$internal
  @override
  ReleaseNotesController create() => ReleaseNotesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReleaseNotesState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReleaseNotesState>(value),
    );
  }
}

String _$releaseNotesControllerHash() =>
    r'5cef8737f7a9847dcf7f6a6f5cac56c39c131c25';

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

abstract class _$ReleaseNotesController extends $Notifier<ReleaseNotesState> {
  ReleaseNotesState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ReleaseNotesState, ReleaseNotesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReleaseNotesState, ReleaseNotesState>,
              ReleaseNotesState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
