// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One connection's per-user presence cache, keyed by user ID and scoped to
/// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
/// uses, and for the same reason: snowflake IDs are minted per server, so a
/// single global map lets two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.

@ProviderFor(PresenceController)
const presenceControllerProvider = PresenceControllerFamily._();

/// One connection's per-user presence cache, keyed by user ID and scoped to
/// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
/// uses, and for the same reason: snowflake IDs are minted per server, so a
/// single global map lets two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.
final class PresenceControllerProvider
    extends $NotifierProvider<PresenceController, Map<String, AccordPresence>> {
  /// One connection's per-user presence cache, keyed by user ID and scoped to
  /// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
  /// uses, and for the same reason: snowflake IDs are minted per server, so a
  /// single global map lets two servers' users collide.
  ///
  /// Every connection (active *or* background) seeds this from its gateway READY
  /// payload's `presences` array and keeps it current from `presence.update`
  /// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
  /// connection being the active one: with the cache keyed per server there is
  /// nothing for a background connection to clobber, and gating was what left a
  /// backgrounded server permanently showing everyone as offline (#191).
  ///
  /// Consumers resolve a member's status by user ID via [accordPresenceStatus];
  /// an absent entry means "offline" (the gateway only pushes presence for
  /// non-offline users). Read the active connection's map through
  /// [activePresencesProvider] rather than picking a key by hand.
  const PresenceControllerProvider._({
    required PresenceControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'presenceControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$presenceControllerHash();

  @override
  String toString() {
    return r'presenceControllerProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is PresenceControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$presenceControllerHash() =>
    r'8f6150eb46df1eaf7ffa212ab7d6fd5fa0e9b464';

/// One connection's per-user presence cache, keyed by user ID and scoped to
/// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
/// uses, and for the same reason: snowflake IDs are minted per server, so a
/// single global map lets two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.

final class PresenceControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PresenceController,
          Map<String, AccordPresence>,
          Map<String, AccordPresence>,
          Map<String, AccordPresence>,
          String
        > {
  const PresenceControllerFamily._()
    : super(
        retry: null,
        name: r'presenceControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// One connection's per-user presence cache, keyed by user ID and scoped to
  /// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
  /// uses, and for the same reason: snowflake IDs are minted per server, so a
  /// single global map lets two servers' users collide.
  ///
  /// Every connection (active *or* background) seeds this from its gateway READY
  /// payload's `presences` array and keeps it current from `presence.update`
  /// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
  /// connection being the active one: with the cache keyed per server there is
  /// nothing for a background connection to clobber, and gating was what left a
  /// backgrounded server permanently showing everyone as offline (#191).
  ///
  /// Consumers resolve a member's status by user ID via [accordPresenceStatus];
  /// an absent entry means "offline" (the gateway only pushes presence for
  /// non-offline users). Read the active connection's map through
  /// [activePresencesProvider] rather than picking a key by hand.

  PresenceControllerProvider call(String serverKey) =>
      PresenceControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'presenceControllerProvider';
}

/// One connection's per-user presence cache, keyed by user ID and scoped to
/// [serverKey] (`userId@baseUrl`) — the same scoping [ReadStateController]
/// uses, and for the same reason: snowflake IDs are minted per server, so a
/// single global map lets two servers' users collide.
///
/// Every connection (active *or* background) seeds this from its gateway READY
/// payload's `presences` array and keeps it current from `presence.update`
/// events — both wired in `accord_event_handler.dart`. Nothing is gated on the
/// connection being the active one: with the cache keyed per server there is
/// nothing for a background connection to clobber, and gating was what left a
/// backgrounded server permanently showing everyone as offline (#191).
///
/// Consumers resolve a member's status by user ID via [accordPresenceStatus];
/// an absent entry means "offline" (the gateway only pushes presence for
/// non-offline users). Read the active connection's map through
/// [activePresencesProvider] rather than picking a key by hand.

abstract class _$PresenceController
    extends $Notifier<Map<String, AccordPresence>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  Map<String, AccordPresence> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
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

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.

@ProviderFor(activePresences)
const activePresencesProvider = ActivePresencesProvider._();

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.

final class ActivePresencesProvider
    extends
        $FunctionalProvider<
          Map<String, AccordPresence>,
          Map<String, AccordPresence>,
          Map<String, AccordPresence>
        >
    with $Provider<Map<String, AccordPresence>> {
  /// The presence map of the connection currently driving the panes, or an empty
  /// map when no server is active. Switching servers re-reads the new
  /// connection's own (already-seeded, already-live) cache, so presence is
  /// correct immediately on a switch with no reconnect.
  const ActivePresencesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'activePresencesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$activePresencesHash();

  @$internal
  @override
  $ProviderElement<Map<String, AccordPresence>> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Map<String, AccordPresence> create(Ref ref) {
    return activePresences(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AccordPresence> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AccordPresence>>(value),
    );
  }
}

String _$activePresencesHash() => r'f9e957be30d12be3772e383f81b825fddd90e29a';
