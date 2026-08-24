// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_users.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.

@ProviderFor(AccordUsersController)
const accordUsersControllerProvider = AccordUsersControllerFamily._();

/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.
final class AccordUsersControllerProvider
    extends $NotifierProvider<AccordUsersController, Map<String, AccordUser>> {
  /// Per-server user cache for users not covered by a space's loaded member page.
  ///
  /// The member cache (`AccordMembersController`) only holds the first 100 members
  /// of a space, so message authors and typers outside that page resolve to a raw
  /// ID. This controller backfills them: [ensure] lazily fetches a user via
  /// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
  /// the result, after which watchers rebuild with the resolved name/avatar.
  const AccordUsersControllerProvider._({
    required AccordUsersControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'accordUsersControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordUsersControllerHash();

  @override
  String toString() {
    return r'accordUsersControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccordUsersController create() => AccordUsersController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AccordUser> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AccordUser>>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccordUsersControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accordUsersControllerHash() =>
    r'f0d4af2c12c3fff142806c1d1ed24720ea730db0';

/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.

final class AccordUsersControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordUsersController,
          Map<String, AccordUser>,
          Map<String, AccordUser>,
          Map<String, AccordUser>,
          String
        > {
  const AccordUsersControllerFamily._()
    : super(
        retry: null,
        name: r'accordUsersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-server user cache for users not covered by a space's loaded member page.
  ///
  /// The member cache (`AccordMembersController`) only holds the first 100 members
  /// of a space, so message authors and typers outside that page resolve to a raw
  /// ID. This controller backfills them: [ensure] lazily fetches a user via
  /// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
  /// the result, after which watchers rebuild with the resolved name/avatar.

  AccordUsersControllerProvider call(String serverKey) =>
      AccordUsersControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'accordUsersControllerProvider';
}

/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.

abstract class _$AccordUsersController
    extends $Notifier<Map<String, AccordUser>> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  Map<String, AccordUser> build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref =
        this.ref as $Ref<Map<String, AccordUser>, Map<String, AccordUser>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Map<String, AccordUser>, Map<String, AccordUser>>,
              Map<String, AccordUser>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
