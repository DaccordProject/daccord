// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'server_limits.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place, which is what the client did
/// unconditionally before this existed.

@ProviderFor(ServerLimitsController)
const serverLimitsControllerProvider = ServerLimitsControllerProvider._();

/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place, which is what the client did
/// unconditionally before this existed.
final class ServerLimitsControllerProvider
    extends $NotifierProvider<ServerLimitsController, AccordServerLimits> {
  /// The connected server's upload limits, refreshed on connect.
  ///
  /// Watches the authenticated client, so switching accounts or servers resets to
  /// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
  /// deployment, not to the app.
  ///
  /// The fetch is fire-and-forget on purpose: the composer must be usable the
  /// instant a channel opens, so it starts on the fallback limits and tightens
  /// (or loosens) them a round-trip later. A failed fetch is not an error state —
  /// it just leaves the fallback in place, which is what the client did
  /// unconditionally before this existed.
  const ServerLimitsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'serverLimitsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$serverLimitsControllerHash();

  @$internal
  @override
  ServerLimitsController create() => ServerLimitsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccordServerLimits value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccordServerLimits>(value),
    );
  }
}

String _$serverLimitsControllerHash() =>
    r'ad1e49b942e1444d5b85cb2eb70f8381d4afb4b7';

/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place, which is what the client did
/// unconditionally before this existed.

abstract class _$ServerLimitsController extends $Notifier<AccordServerLimits> {
  AccordServerLimits build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<AccordServerLimits, AccordServerLimits>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccordServerLimits, AccordServerLimits>,
              AccordServerLimits,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
