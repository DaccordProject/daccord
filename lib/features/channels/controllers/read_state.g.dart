// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'read_state.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Client-side read/unread tracker, one instance per connected server (keyed by
/// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
/// servers don't clobber each other.
///
/// Three things feed it:
///  * the gateway READY handler [hydrate]s the server's authoritative unread
///    list on every (re)connect — this is what survives a cold start and what
///    lights up *background* servers;
///  * the gateway message handler [markUnread]s on incoming traffic for live
///    updates (every connection, not just the active one);
///  * the home screen / context menu / voice panel [markRead]s the channel the
///    user opens, which separately POSTs `channels.ack` to the server.

@ProviderFor(ReadStateController)
const readStateControllerProvider = ReadStateControllerFamily._();

/// Client-side read/unread tracker, one instance per connected server (keyed by
/// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
/// servers don't clobber each other.
///
/// Three things feed it:
///  * the gateway READY handler [hydrate]s the server's authoritative unread
///    list on every (re)connect — this is what survives a cold start and what
///    lights up *background* servers;
///  * the gateway message handler [markUnread]s on incoming traffic for live
///    updates (every connection, not just the active one);
///  * the home screen / context menu / voice panel [markRead]s the channel the
///    user opens, which separately POSTs `channels.ack` to the server.
final class ReadStateControllerProvider
    extends $NotifierProvider<ReadStateController, ReadStateSnapshot> {
  /// Client-side read/unread tracker, one instance per connected server (keyed by
  /// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
  /// servers don't clobber each other.
  ///
  /// Three things feed it:
  ///  * the gateway READY handler [hydrate]s the server's authoritative unread
  ///    list on every (re)connect — this is what survives a cold start and what
  ///    lights up *background* servers;
  ///  * the gateway message handler [markUnread]s on incoming traffic for live
  ///    updates (every connection, not just the active one);
  ///  * the home screen / context menu / voice panel [markRead]s the channel the
  ///    user opens, which separately POSTs `channels.ack` to the server.
  const ReadStateControllerProvider._({
    required ReadStateControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'readStateControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$readStateControllerHash();

  @override
  String toString() {
    return r'readStateControllerProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is ReadStateControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$readStateControllerHash() =>
    r'7e600872e2089de2b7a4cc6be94f53a349d80335';

/// Client-side read/unread tracker, one instance per connected server (keyed by
/// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
/// servers don't clobber each other.
///
/// Three things feed it:
///  * the gateway READY handler [hydrate]s the server's authoritative unread
///    list on every (re)connect — this is what survives a cold start and what
///    lights up *background* servers;
///  * the gateway message handler [markUnread]s on incoming traffic for live
///    updates (every connection, not just the active one);
///  * the home screen / context menu / voice panel [markRead]s the channel the
///    user opens, which separately POSTs `channels.ack` to the server.

final class ReadStateControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ReadStateController,
          ReadStateSnapshot,
          ReadStateSnapshot,
          ReadStateSnapshot,
          String
        > {
  const ReadStateControllerFamily._()
    : super(
        retry: null,
        name: r'readStateControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Client-side read/unread tracker, one instance per connected server (keyed by
  /// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
  /// servers don't clobber each other.
  ///
  /// Three things feed it:
  ///  * the gateway READY handler [hydrate]s the server's authoritative unread
  ///    list on every (re)connect — this is what survives a cold start and what
  ///    lights up *background* servers;
  ///  * the gateway message handler [markUnread]s on incoming traffic for live
  ///    updates (every connection, not just the active one);
  ///  * the home screen / context menu / voice panel [markRead]s the channel the
  ///    user opens, which separately POSTs `channels.ack` to the server.

  ReadStateControllerProvider call(String serverKey) =>
      ReadStateControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'readStateControllerProvider';
}

/// Client-side read/unread tracker, one instance per connected server (keyed by
/// `serverKey`, i.e. `userId@baseUrl`) so snowflake IDs that collide across
/// servers don't clobber each other.
///
/// Three things feed it:
///  * the gateway READY handler [hydrate]s the server's authoritative unread
///    list on every (re)connect — this is what survives a cold start and what
///    lights up *background* servers;
///  * the gateway message handler [markUnread]s on incoming traffic for live
///    updates (every connection, not just the active one);
///  * the home screen / context menu / voice panel [markRead]s the channel the
///    user opens, which separately POSTs `channels.ack` to the server.

abstract class _$ReadStateController extends $Notifier<ReadStateSnapshot> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  ReadStateSnapshot build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
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
