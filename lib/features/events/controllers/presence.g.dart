// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'presence.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-connection presence cache seeded from READY and `presence.update` for
/// every connection; offline transitions wait [offlineGrace] so reconnect blips
/// don't reshuffle the roster, and an absent entry means offline. Read the
/// active connection's map through [activePresencesProvider].

@ProviderFor(PresenceController)
final presenceControllerProvider = PresenceControllerFamily._();

/// Per-connection presence cache seeded from READY and `presence.update` for
/// every connection; offline transitions wait [offlineGrace] so reconnect blips
/// don't reshuffle the roster, and an absent entry means offline. Read the
/// active connection's map through [activePresencesProvider].
final class PresenceControllerProvider
    extends $NotifierProvider<PresenceController, PresenceMap> {
  /// Per-connection presence cache seeded from READY and `presence.update` for
  /// every connection; offline transitions wait [offlineGrace] so reconnect blips
  /// don't reshuffle the roster, and an absent entry means offline. Read the
  /// active connection's map through [activePresencesProvider].
  PresenceControllerProvider._({
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
  Override overrideWithValue(PresenceMap value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PresenceMap>(value),
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
    r'5215467acb6d4a203b24ce5be0afc5ecf867f8ab';

/// Per-connection presence cache seeded from READY and `presence.update` for
/// every connection; offline transitions wait [offlineGrace] so reconnect blips
/// don't reshuffle the roster, and an absent entry means offline. Read the
/// active connection's map through [activePresencesProvider].

final class PresenceControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PresenceController,
          PresenceMap,
          PresenceMap,
          PresenceMap,
          String
        > {
  PresenceControllerFamily._()
    : super(
        retry: null,
        name: r'presenceControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-connection presence cache seeded from READY and `presence.update` for
  /// every connection; offline transitions wait [offlineGrace] so reconnect blips
  /// don't reshuffle the roster, and an absent entry means offline. Read the
  /// active connection's map through [activePresencesProvider].

  PresenceControllerProvider call(String serverKey) =>
      PresenceControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'presenceControllerProvider';
}

/// Per-connection presence cache seeded from READY and `presence.update` for
/// every connection; offline transitions wait [offlineGrace] so reconnect blips
/// don't reshuffle the roster, and an absent entry means offline. Read the
/// active connection's map through [activePresencesProvider].

abstract class _$PresenceController extends $Notifier<PresenceMap> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  PresenceMap build(String serverKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<PresenceMap, PresenceMap>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PresenceMap, PresenceMap>,
              PresenceMap,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.

@ProviderFor(activePresences)
final activePresencesProvider = ActivePresencesProvider._();

/// The presence map of the connection currently driving the panes, or an empty
/// map when no server is active. Switching servers re-reads the new
/// connection's own (already-seeded, already-live) cache, so presence is
/// correct immediately on a switch with no reconnect.

final class ActivePresencesProvider
    extends $FunctionalProvider<PresenceMap, PresenceMap, PresenceMap>
    with $Provider<PresenceMap> {
  /// The presence map of the connection currently driving the panes, or an empty
  /// map when no server is active. Switching servers re-reads the new
  /// connection's own (already-seeded, already-live) cache, so presence is
  /// correct immediately on a switch with no reconnect.
  ActivePresencesProvider._()
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
  $ProviderElement<PresenceMap> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PresenceMap create(Ref ref) {
    return activePresences(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PresenceMap value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PresenceMap>(value),
    );
  }
}

String _$activePresencesHash() => r'cf19e8f8ef668b7b0bade324eaea6e93682c21d8';
