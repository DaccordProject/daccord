// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connection.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).

@ProviderFor(ConnectionController)
const connectionControllerProvider = ConnectionControllerProvider._();

/// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).
final class ConnectionControllerProvider
    extends $NotifierProvider<ConnectionController, ConnectionStatus> {
  /// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).
  const ConnectionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionControllerHash();

  @$internal
  @override
  ConnectionController create() => ConnectionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionStatus>(value),
    );
  }
}

String _$connectionControllerHash() =>
    r'4bd9ec90f04afbb97228d8764103fbc92ff66033';

/// Exposes the current [ConnectionStatus] to the UI (e.g. a connecting banner).

abstract class _$ConnectionController extends $Notifier<ConnectionStatus> {
  ConnectionStatus build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ConnectionStatus, ConnectionStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectionStatus, ConnectionStatus>,
              ConnectionStatus,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
