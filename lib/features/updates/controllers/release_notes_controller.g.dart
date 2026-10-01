// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_notes_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Shows the release notes for the running build once after an update. The
/// staged [AppRelease] dies with the old process, so this fetches the running
/// tag ([kGithubReleaseByTagUrl]), which also covers updates applied outside
/// the app.
///
/// The seen marker lives in the `accord-settings` box under [_seenKey], not in
/// `AccordSettings`: settings are exportable between devices, and a carried
/// marker would suppress (or fake) notes on the receiving one.
///
/// Notes still show on store builds: [kAppStoreBuild] forbids installing code,
/// and reading a release body installs nothing. A failed fetch or empty body
/// shows nothing.

@ProviderFor(ReleaseNotesController)
final releaseNotesControllerProvider = ReleaseNotesControllerProvider._();

/// Shows the release notes for the running build once after an update. The
/// staged [AppRelease] dies with the old process, so this fetches the running
/// tag ([kGithubReleaseByTagUrl]), which also covers updates applied outside
/// the app.
///
/// The seen marker lives in the `accord-settings` box under [_seenKey], not in
/// `AccordSettings`: settings are exportable between devices, and a carried
/// marker would suppress (or fake) notes on the receiving one.
///
/// Notes still show on store builds: [kAppStoreBuild] forbids installing code,
/// and reading a release body installs nothing. A failed fetch or empty body
/// shows nothing.
final class ReleaseNotesControllerProvider
    extends $NotifierProvider<ReleaseNotesController, ReleaseNotesState> {
  /// Shows the release notes for the running build once after an update. The
  /// staged [AppRelease] dies with the old process, so this fetches the running
  /// tag ([kGithubReleaseByTagUrl]), which also covers updates applied outside
  /// the app.
  ///
  /// The seen marker lives in the `accord-settings` box under [_seenKey], not in
  /// `AccordSettings`: settings are exportable between devices, and a carried
  /// marker would suppress (or fake) notes on the receiving one.
  ///
  /// Notes still show on store builds: [kAppStoreBuild] forbids installing code,
  /// and reading a release body installs nothing. A failed fetch or empty body
  /// shows nothing.
  ReleaseNotesControllerProvider._()
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
    r'69fea23bd74af2c19d876e4e7fec00a2bd8f99eb';

/// Shows the release notes for the running build once after an update. The
/// staged [AppRelease] dies with the old process, so this fetches the running
/// tag ([kGithubReleaseByTagUrl]), which also covers updates applied outside
/// the app.
///
/// The seen marker lives in the `accord-settings` box under [_seenKey], not in
/// `AccordSettings`: settings are exportable between devices, and a carried
/// marker would suppress (or fake) notes on the receiving one.
///
/// Notes still show on store builds: [kAppStoreBuild] forbids installing code,
/// and reading a release body installs nothing. A failed fetch or empty body
/// shows nothing.

abstract class _$ReleaseNotesController extends $Notifier<ReleaseNotesState> {
  ReleaseNotesState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ReleaseNotesState, ReleaseNotesState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReleaseNotesState, ReleaseNotesState>,
              ReleaseNotesState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
