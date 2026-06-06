// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'read_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Client-side read/unread tracker. Mirrors the reference client's
/// `client_unread.gd`: the gateway handler marks channels unread on incoming
/// messages (skipping the visible channel and own messages), and the home
/// screen marks the visible channel read when it's selected — which also acks
/// the latest message ID to the server. State is in-memory only; on cold start
/// the user just sees no unread badges until the gateway reports new traffic,
/// matching the reference's behavior.

@ProviderFor(ReadStateController)
const readStateControllerProvider = ReadStateControllerProvider._();

/// Client-side read/unread tracker. Mirrors the reference client's
/// `client_unread.gd`: the gateway handler marks channels unread on incoming
/// messages (skipping the visible channel and own messages), and the home
/// screen marks the visible channel read when it's selected — which also acks
/// the latest message ID to the server. State is in-memory only; on cold start
/// the user just sees no unread badges until the gateway reports new traffic,
/// matching the reference's behavior.
final class ReadStateControllerProvider
    extends $NotifierProvider<ReadStateController, ReadStateSnapshot> {
  /// Client-side read/unread tracker. Mirrors the reference client's
  /// `client_unread.gd`: the gateway handler marks channels unread on incoming
  /// messages (skipping the visible channel and own messages), and the home
  /// screen marks the visible channel read when it's selected — which also acks
  /// the latest message ID to the server. State is in-memory only; on cold start
  /// the user just sees no unread badges until the gateway reports new traffic,
  /// matching the reference's behavior.
  const ReadStateControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'readStateControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$readStateControllerHash();

  @$internal
  @override
  ReadStateController create() => ReadStateController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReadStateSnapshot value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReadStateSnapshot>(value),
    );
  }
}

String _$readStateControllerHash() =>
    r'1d0ce8afa2edb08a6937f422029e6056c7515348';

/// Client-side read/unread tracker. Mirrors the reference client's
/// `client_unread.gd`: the gateway handler marks channels unread on incoming
/// messages (skipping the visible channel and own messages), and the home
/// screen marks the visible channel read when it's selected — which also acks
/// the latest message ID to the server. State is in-memory only; on cold start
/// the user just sees no unread badges until the gateway reports new traffic,
/// matching the reference's behavior.

abstract class _$ReadStateController extends $Notifier<ReadStateSnapshot> {
  ReadStateSnapshot build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<ReadStateSnapshot, ReadStateSnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ReadStateSnapshot, ReadStateSnapshot>,
              ReadStateSnapshot,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
