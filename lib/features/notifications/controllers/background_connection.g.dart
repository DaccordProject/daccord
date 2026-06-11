// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'background_connection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Starts/stops the Android foreground service (`BackgroundConnectionService`)
/// that exempts the app process from Android's cached-app freezer while
/// backgrounded, so the gateway sockets stay alive and mention notifications
/// keep firing. The service holds no logic of its own — keeping the process
/// unfrozen is the whole job.
///
/// Mirrors the MCP server controller pattern: kept alive by a `ref.watch` in
/// `MainWindow`, reacting to the persisted "Background connection" setting and
/// the login state. A no-op on every platform but Android.

@ProviderFor(BackgroundConnectionController)
const backgroundConnectionControllerProvider =
    BackgroundConnectionControllerProvider._();

/// Starts/stops the Android foreground service (`BackgroundConnectionService`)
/// that exempts the app process from Android's cached-app freezer while
/// backgrounded, so the gateway sockets stay alive and mention notifications
/// keep firing. The service holds no logic of its own — keeping the process
/// unfrozen is the whole job.
///
/// Mirrors the MCP server controller pattern: kept alive by a `ref.watch` in
/// `MainWindow`, reacting to the persisted "Background connection" setting and
/// the login state. A no-op on every platform but Android.
final class BackgroundConnectionControllerProvider
    extends $NotifierProvider<BackgroundConnectionController, void> {
  /// Starts/stops the Android foreground service (`BackgroundConnectionService`)
  /// that exempts the app process from Android's cached-app freezer while
  /// backgrounded, so the gateway sockets stay alive and mention notifications
  /// keep firing. The service holds no logic of its own — keeping the process
  /// unfrozen is the whole job.
  ///
  /// Mirrors the MCP server controller pattern: kept alive by a `ref.watch` in
  /// `MainWindow`, reacting to the persisted "Background connection" setting and
  /// the login state. A no-op on every platform but Android.
  const BackgroundConnectionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'backgroundConnectionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$backgroundConnectionControllerHash();

  @$internal
  @override
  BackgroundConnectionController create() => BackgroundConnectionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$backgroundConnectionControllerHash() =>
    r'8430eb8e85f11ec016f7145f5c9e8188dfd22f5a';

/// Starts/stops the Android foreground service (`BackgroundConnectionService`)
/// that exempts the app process from Android's cached-app freezer while
/// backgrounded, so the gateway sockets stay alive and mention notifications
/// keep firing. The service holds no logic of its own — keeping the process
/// unfrozen is the whole job.
///
/// Mirrors the MCP server controller pattern: kept alive by a `ref.watch` in
/// `MainWindow`, reacting to the persisted "Background connection" setting and
/// the login state. A no-op on every platform but Android.

abstract class _$BackgroundConnectionController extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  void runBuild() {
    build();
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleValue(ref, null);
  }
}
