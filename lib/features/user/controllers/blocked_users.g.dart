// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'blocked_users.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The accounts this connection has blocked, by user id.
///
/// Blocking is what the report dialog offers where no moderator will see the
/// report, and it promises the blocked account's messages stop being shown.
/// Nothing enforced that client-side, so the message surfaces filter on this set
/// (App Review 1.2, #290).
///
/// The server's relationship list is the source of truth: [refresh] seeds the
/// set on gateway READY and the relationship events re-run it. The local
/// [block]/[unblock] mutators exist so the block a user just performed takes
/// effect in the panes immediately rather than on the next fetch.

@ProviderFor(BlockedUsersController)
const blockedUsersControllerProvider = BlockedUsersControllerFamily._();

/// The accounts this connection has blocked, by user id.
///
/// Blocking is what the report dialog offers where no moderator will see the
/// report, and it promises the blocked account's messages stop being shown.
/// Nothing enforced that client-side, so the message surfaces filter on this set
/// (App Review 1.2, #290).
///
/// The server's relationship list is the source of truth: [refresh] seeds the
/// set on gateway READY and the relationship events re-run it. The local
/// [block]/[unblock] mutators exist so the block a user just performed takes
/// effect in the panes immediately rather than on the next fetch.
final class BlockedUsersControllerProvider
    extends $NotifierProvider<BlockedUsersController, Set<String>> {
  /// The accounts this connection has blocked, by user id.
  ///
  /// Blocking is what the report dialog offers where no moderator will see the
  /// report, and it promises the blocked account's messages stop being shown.
  /// Nothing enforced that client-side, so the message surfaces filter on this set
  /// (App Review 1.2, #290).
  ///
  /// The server's relationship list is the source of truth: [refresh] seeds the
  /// set on gateway READY and the relationship events re-run it. The local
  /// [block]/[unblock] mutators exist so the block a user just performed takes
  /// effect in the panes immediately rather than on the next fetch.
  const BlockedUsersControllerProvider._({
    required BlockedUsersControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'blockedUsersControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$blockedUsersControllerHash();

  @override
  String toString() {
    return r'blockedUsersControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  BlockedUsersController create() => BlockedUsersController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BlockedUsersControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$blockedUsersControllerHash() =>
    r'50c80e7dedcf6ee243e873bd58c6fbcb8f3cbbaf';

/// The accounts this connection has blocked, by user id.
///
/// Blocking is what the report dialog offers where no moderator will see the
/// report, and it promises the blocked account's messages stop being shown.
/// Nothing enforced that client-side, so the message surfaces filter on this set
/// (App Review 1.2, #290).
///
/// The server's relationship list is the source of truth: [refresh] seeds the
/// set on gateway READY and the relationship events re-run it. The local
/// [block]/[unblock] mutators exist so the block a user just performed takes
/// effect in the panes immediately rather than on the next fetch.

final class BlockedUsersControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          BlockedUsersController,
          Set<String>,
          Set<String>,
          Set<String>,
          String
        > {
  const BlockedUsersControllerFamily._()
    : super(
        retry: null,
        name: r'blockedUsersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// The accounts this connection has blocked, by user id.
  ///
  /// Blocking is what the report dialog offers where no moderator will see the
  /// report, and it promises the blocked account's messages stop being shown.
  /// Nothing enforced that client-side, so the message surfaces filter on this set
  /// (App Review 1.2, #290).
  ///
  /// The server's relationship list is the source of truth: [refresh] seeds the
  /// set on gateway READY and the relationship events re-run it. The local
  /// [block]/[unblock] mutators exist so the block a user just performed takes
  /// effect in the panes immediately rather than on the next fetch.

  BlockedUsersControllerProvider call(String serverKey) =>
      BlockedUsersControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'blockedUsersControllerProvider';
}

/// The accounts this connection has blocked, by user id.
///
/// Blocking is what the report dialog offers where no moderator will see the
/// report, and it promises the blocked account's messages stop being shown.
/// Nothing enforced that client-side, so the message surfaces filter on this set
/// (App Review 1.2, #290).
///
/// The server's relationship list is the source of truth: [refresh] seeds the
/// set on gateway READY and the relationship events re-run it. The local
/// [block]/[unblock] mutators exist so the block a user just performed takes
/// effect in the panes immediately rather than on the next fetch.

abstract class _$BlockedUsersController extends $Notifier<Set<String>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  Set<String> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
