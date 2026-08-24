// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'open_tabs.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the open-channel tab strip (the reference client's `main_window_tabs`).
///
/// Selecting a channel [open]s a tab (or switches to it if already open);
/// closing/reordering mirror the reference's context-menu actions. The whole
/// strip is persisted to the `accord-settings` Hive box (a separate key from
/// [AccordSettings]) so open tabs survive a restart.

@ProviderFor(OpenTabsController)
const openTabsControllerProvider = OpenTabsControllerProvider._();

/// Owns the open-channel tab strip (the reference client's `main_window_tabs`).
///
/// Selecting a channel [open]s a tab (or switches to it if already open);
/// closing/reordering mirror the reference's context-menu actions. The whole
/// strip is persisted to the `accord-settings` Hive box (a separate key from
/// [AccordSettings]) so open tabs survive a restart.
final class OpenTabsControllerProvider
    extends $NotifierProvider<OpenTabsController, OpenTabsState> {
  /// Owns the open-channel tab strip (the reference client's `main_window_tabs`).
  ///
  /// Selecting a channel [open]s a tab (or switches to it if already open);
  /// closing/reordering mirror the reference's context-menu actions. The whole
  /// strip is persisted to the `accord-settings` Hive box (a separate key from
  /// [AccordSettings]) so open tabs survive a restart.
  const OpenTabsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'openTabsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$openTabsControllerHash();

  @$internal
  @override
  OpenTabsController create() => OpenTabsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OpenTabsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OpenTabsState>(value),
    );
  }
}

String _$openTabsControllerHash() =>
    r'644e0c037ac9997b5a93f0d2d5e731b1396b4305';

/// Owns the open-channel tab strip (the reference client's `main_window_tabs`).
///
/// Selecting a channel [open]s a tab (or switches to it if already open);
/// closing/reordering mirror the reference's context-menu actions. The whole
/// strip is persisted to the `accord-settings` Hive box (a separate key from
/// [AccordSettings]) so open tabs survive a restart.

abstract class _$OpenTabsController extends $Notifier<OpenTabsState> {
  OpenTabsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<OpenTabsState, OpenTabsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OpenTabsState, OpenTabsState>,
              OpenTabsState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
