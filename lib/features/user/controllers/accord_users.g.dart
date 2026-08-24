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
const accordUsersControllerProvider = AccordUsersControllerProvider._();

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
  const AccordUsersControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accordUsersControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accordUsersControllerHash();

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
}

String _$accordUsersControllerHash() =>
    r'aa9cce7016e5476a9018ea735c1a856cf0f6beb4';

/// Per-server user cache for users not covered by a space's loaded member page.
///
/// The member cache (`AccordMembersController`) only holds the first 100 members
/// of a space, so message authors and typers outside that page resolve to a raw
/// ID. This controller backfills them: [ensure] lazily fetches a user via
/// `users.fetch` (deduped against in-flight and already-cached IDs) and stores
/// the result, after which watchers rebuild with the resolved name/avatar.

abstract class _$AccordUsersController
    extends $Notifier<Map<String, AccordUser>> {
  Map<String, AccordUser> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
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
