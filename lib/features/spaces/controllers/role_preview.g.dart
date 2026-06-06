// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'role_preview.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the active role preview (null when not previewing). Permission checks
/// read this to gate the UI as the previewed role, and the preview banner reads
/// it to show the exit control. App-wide (keepAlive) so it survives navigation.

@ProviderFor(RolePreviewController)
const rolePreviewControllerProvider = RolePreviewControllerProvider._();

/// Holds the active role preview (null when not previewing). Permission checks
/// read this to gate the UI as the previewed role, and the preview banner reads
/// it to show the exit control. App-wide (keepAlive) so it survives navigation.
final class RolePreviewControllerProvider
    extends $NotifierProvider<RolePreviewController, RolePreview?> {
  /// Holds the active role preview (null when not previewing). Permission checks
  /// read this to gate the UI as the previewed role, and the preview banner reads
  /// it to show the exit control. App-wide (keepAlive) so it survives navigation.
  const RolePreviewControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'rolePreviewControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$rolePreviewControllerHash();

  @$internal
  @override
  RolePreviewController create() => RolePreviewController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RolePreview? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RolePreview?>(value),
    );
  }
}

String _$rolePreviewControllerHash() =>
    r'f58cb4d5014e6bfb0d91734e9017d8ba97b8bf83';

/// Holds the active role preview (null when not previewing). Permission checks
/// read this to gate the UI as the previewed role, and the preview banner reads
/// it to show the exit control. App-wide (keepAlive) so it survives navigation.

abstract class _$RolePreviewController extends $Notifier<RolePreview?> {
  RolePreview? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<RolePreview?, RolePreview?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<RolePreview?, RolePreview?>,
              RolePreview?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
