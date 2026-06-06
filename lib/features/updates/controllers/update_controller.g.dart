// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a passive check throttled
/// to once an hour (gated on the auto-update-check setting) plus a manual check
/// from the Updates settings page. The client does not self-install — the UI
/// links to the release page for manual download.

@ProviderFor(UpdateController)
const updateControllerProvider = UpdateControllerProvider._();

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a passive check throttled
/// to once an hour (gated on the auto-update-check setting) plus a manual check
/// from the Updates settings page. The client does not self-install — the UI
/// links to the release page for manual download.
final class UpdateControllerProvider
    extends $NotifierProvider<UpdateController, UpdateState> {
  /// Checks the project's GitHub Releases for a newer build and exposes the
  /// result. Ports the reference client's `updater.gd`: a passive check throttled
  /// to once an hour (gated on the auto-update-check setting) plus a manual check
  /// from the Updates settings page. The client does not self-install — the UI
  /// links to the release page for manual download.
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

String _$updateControllerHash() => r'491ccc5038220d7481117661d3fa6266e7a7db30';

/// Checks the project's GitHub Releases for a newer build and exposes the
/// result. Ports the reference client's `updater.gd`: a passive check throttled
/// to once an hour (gated on the auto-update-check setting) plus a manual check
/// from the Updates settings page. The client does not self-install — the UI
/// links to the release page for manual download.

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
