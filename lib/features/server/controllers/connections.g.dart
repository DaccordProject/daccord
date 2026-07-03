// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connections.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Rail-level registry of every connected server (see [AccordConnection]).
///
/// `AccordAuth` writes connection lifecycle here; the gateway event handler
/// writes each server's space cache here. The space rail watches this to render
/// spaces grouped across all connected servers.

@ProviderFor(ConnectionsController)
const connectionsControllerProvider = ConnectionsControllerProvider._();

/// Rail-level registry of every connected server (see [AccordConnection]).
///
/// `AccordAuth` writes connection lifecycle here; the gateway event handler
/// writes each server's space cache here. The space rail watches this to render
/// spaces grouped across all connected servers.
final class ConnectionsControllerProvider
    extends $NotifierProvider<ConnectionsController, ConnectionsState> {
  /// Rail-level registry of every connected server (see [AccordConnection]).
  ///
  /// `AccordAuth` writes connection lifecycle here; the gateway event handler
  /// writes each server's space cache here. The space rail watches this to render
  /// spaces grouped across all connected servers.
  const ConnectionsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectionsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectionsControllerHash();

  @$internal
  @override
  ConnectionsController create() => ConnectionsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionsState>(value),
    );
  }
}

String _$connectionsControllerHash() =>
    r'1ca50e7e1fd78221babbe99c29eee812d5157f6f';

/// Rail-level registry of every connected server (see [AccordConnection]).
///
/// `AccordAuth` writes connection lifecycle here; the gateway event handler
/// writes each server's space cache here. The space rail watches this to render
/// spaces grouped across all connected servers.

abstract class _$ConnectionsController extends $Notifier<ConnectionsState> {
  ConnectionsState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ConnectionsState, ConnectionsState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ConnectionsState, ConnectionsState>,
              ConnectionsState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
