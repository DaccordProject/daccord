// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a startup check plus an
/// hourly periodic check (both gated on the auto-update-check setting and
/// throttled), a manual check, session-dismiss + persistent skip, and
/// platform-aware download links.
///
/// In-place self-replacement is handled by [installUpdate]: on desktop it
/// downloads + verifies the matching bundle and a detached helper swaps the
/// binary tree and relaunches (see [UpdateInstaller]); on Android it hands the
/// APK to the system installer. Platforms without an in-place path (or older
/// releases) still fall back to a plain download link, and web prompts a
/// service-worker reload.

@ProviderFor(UpdateController)
const updateControllerProvider = UpdateControllerProvider._();

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a startup check plus an
/// hourly periodic check (both gated on the auto-update-check setting and
/// throttled), a manual check, session-dismiss + persistent skip, and
/// platform-aware download links.
///
/// In-place self-replacement is handled by [installUpdate]: on desktop it
/// downloads + verifies the matching bundle and a detached helper swaps the
/// binary tree and relaunches (see [UpdateInstaller]); on Android it hands the
/// APK to the system installer. Platforms without an in-place path (or older
/// releases) still fall back to a plain download link, and web prompts a
/// service-worker reload.
final class UpdateControllerProvider
    extends $NotifierProvider<UpdateController, UpdateState> {
  /// Checks the project's GitHub Releases for a newer build and exposes the
  /// result. Ports the reference client's `updater.gd`: a startup check plus an
  /// hourly periodic check (both gated on the auto-update-check setting and
  /// throttled), a manual check, session-dismiss + persistent skip, and
  /// platform-aware download links.
  ///
  /// In-place self-replacement is handled by [installUpdate]: on desktop it
  /// downloads + verifies the matching bundle and a detached helper swaps the
  /// binary tree and relaunches (see [UpdateInstaller]); on Android it hands the
  /// APK to the system installer. Platforms without an in-place path (or older
  /// releases) still fall back to a plain download link, and web prompts a
  /// service-worker reload.
  const UpdateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'updateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$updateControllerHash();

  @$internal
  @override
  UpdateController create() => UpdateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(UpdateState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<UpdateState>(value),
    );
  }
}

String _$updateControllerHash() => r'2d2cf3dcf8973087f9462dcc72d2499ed3f42865';

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a startup check plus an
/// hourly periodic check (both gated on the auto-update-check setting and
/// throttled), a manual check, session-dismiss + persistent skip, and
/// platform-aware download links.
///
/// In-place self-replacement is handled by [installUpdate]: on desktop it
/// downloads + verifies the matching bundle and a detached helper swaps the
/// binary tree and relaunches (see [UpdateInstaller]); on Android it hands the
/// APK to the system installer. Platforms without an in-place path (or older
/// releases) still fall back to a plain download link, and web prompts a
/// service-worker reload.

abstract class _$UpdateController extends $Notifier<UpdateState> {
  UpdateState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<UpdateState, UpdateState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<UpdateState, UpdateState>,
              UpdateState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
