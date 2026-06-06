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
/// In-place self-replacement (binary swap + relaunch on desktop, APK install on
/// Android) is intentionally deferred — it needs untestable per-platform native
/// machinery. For now an available update links straight to the matching
/// platform asset's download (or the release page), and web prompts a refresh.

@ProviderFor(UpdateController)
const updateControllerProvider = UpdateControllerProvider._();

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
final class UpdateControllerProvider
    extends $NotifierProvider<UpdateController, UpdateState> {
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

String _$updateControllerHash() => r'f1ef891a0558743369237ab832c5fc12acb4c8af';

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
