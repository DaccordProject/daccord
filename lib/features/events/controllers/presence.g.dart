// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Global per-user presence cache, keyed by user ID. Mirrors the reference
/// client's global `_user_cache[...]["status"]` rather than a per-space store:
/// a user has one presence regardless of how many spaces they share with us.
///
/// Seeded from the gateway READY payload's `presences` array and kept in sync
/// by `presence.update` events (both wired in `accord_event_handler.dart`).
/// Consumers resolve a member's status by user ID; an absent entry means
/// "offline" (the gateway only pushes presence for non-offline users).

@ProviderFor(PresenceController)
const presenceControllerProvider = PresenceControllerProvider._();

/// Global per-user presence cache, keyed by user ID. Mirrors the reference
/// client's global `_user_cache[...]["status"]` rather than a per-space store:
/// a user has one presence regardless of how many spaces they share with us.
///
/// Seeded from the gateway READY payload's `presences` array and kept in sync
/// by `presence.update` events (both wired in `accord_event_handler.dart`).
/// Consumers resolve a member's status by user ID; an absent entry means
/// "offline" (the gateway only pushes presence for non-offline users).
final class PresenceControllerProvider
    extends $NotifierProvider<PresenceController, Map<String, AccordPresence>> {
  /// Global per-user presence cache, keyed by user ID. Mirrors the reference
  /// client's global `_user_cache[...]["status"]` rather than a per-space store:
  /// a user has one presence regardless of how many spaces they share with us.
  ///
  /// Seeded from the gateway READY payload's `presences` array and kept in sync
  /// by `presence.update` events (both wired in `accord_event_handler.dart`).
  /// Consumers resolve a member's status by user ID; an absent entry means
  /// "offline" (the gateway only pushes presence for non-offline users).
  const PresenceControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'presenceControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$presenceControllerHash();

  @$internal
  @override
  PresenceController create() => PresenceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AccordPresence> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AccordPresence>>(value),
    );
  }
}

String _$presenceControllerHash() =>
    r'e6a7155f260c87947cda63ecb1ac0ce8d272a47e';

/// Global per-user presence cache, keyed by user ID. Mirrors the reference
/// client's global `_user_cache[...]["status"]` rather than a per-space store:
/// a user has one presence regardless of how many spaces they share with us.
///
/// Seeded from the gateway READY payload's `presences` array and kept in sync
/// by `presence.update` events (both wired in `accord_event_handler.dart`).
/// Consumers resolve a member's status by user ID; an absent entry means
/// "offline" (the gateway only pushes presence for non-offline users).

abstract class _$PresenceController
    extends $Notifier<Map<String, AccordPresence>> {
  Map<String, AccordPresence> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref =
        this.ref
            as $Ref<Map<String, AccordPresence>, Map<String, AccordPresence>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AccordPresence>,
                Map<String, AccordPresence>
              >,
              Map<String, AccordPresence>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
