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
/// it just leaves the fallback in place.

@ProviderFor(ServerLimitsController)
final serverLimitsControllerProvider = ServerLimitsControllerProvider._();

/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place.
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
  /// it just leaves the fallback in place.
  ServerLimitsControllerProvider._()
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
    r'63cad80fa88b4af4d28e817fa7c2a3293ec69df2';

/// The connected server's upload limits, refreshed on connect.
///
/// Watches the authenticated client, so switching accounts or servers resets to
/// [AccordServerLimits.fallback] and re-fetches — the limits belong to the
/// deployment, not to the app.
///
/// The fetch is fire-and-forget on purpose: the composer must be usable the
/// instant a channel opens, so it starts on the fallback limits and tightens
/// (or loosens) them a round-trip later. A failed fetch is not an error state —
/// it just leaves the fallback in place.

abstract class _$ServerLimitsController extends $Notifier<AccordServerLimits> {
  AccordServerLimits build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AccordServerLimits, AccordServerLimits>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccordServerLimits, AccordServerLimits>,
              AccordServerLimits,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
