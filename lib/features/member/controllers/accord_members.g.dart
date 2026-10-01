// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_members.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".

@ProviderFor(AccordMembersController)
final accordMembersControllerProvider = AccordMembersControllerFamily._();

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".
final class AccordMembersControllerProvider
    extends
        $NotifierProvider<AccordMembersController, Map<String, AccordMember>?> {
  /// A space's members, keyed by space ID and indexed by user ID for O(1) author
  /// resolution. Self-loads via `members.list` the first time it's watched (once
  /// logged in) and is kept in sync by member join/update/leave gateway events.
  /// `null` means "not loaded yet".
  AccordMembersControllerProvider._({
    required AccordMembersControllerFamily super.from,
    required (String, String) super.argument,
  }) : super(
         retry: null,
         name: r'accordMembersControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordMembersControllerHash();

  @override
  String toString() {
    return r'accordMembersControllerProvider'
        ''
        '$argument';
  }

  @$internal
  @override
  AccordMembersController create() => AccordMembersController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Map<String, AccordMember>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Map<String, AccordMember>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccordMembersControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accordMembersControllerHash() =>
    r'2a6f519f443b742b352befb1b1d8ffb9ad48862f';

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".

final class AccordMembersControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordMembersController,
          Map<String, AccordMember>?,
          Map<String, AccordMember>?,
          Map<String, AccordMember>?,
          (String, String)
        > {
  AccordMembersControllerFamily._()
    : super(
        retry: null,
        name: r'accordMembersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A space's members, keyed by space ID and indexed by user ID for O(1) author
  /// resolution. Self-loads via `members.list` the first time it's watched (once
  /// logged in) and is kept in sync by member join/update/leave gateway events.
  /// `null` means "not loaded yet".

  AccordMembersControllerProvider call(String serverKey, String spaceId) =>
      AccordMembersControllerProvider._(
        argument: (serverKey, spaceId),
        from: this,
      );

  @override
  String toString() => r'accordMembersControllerProvider';
}

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".

abstract class _$AccordMembersController
    extends $Notifier<Map<String, AccordMember>?> {
  late final _$args = ref.$arg as (String, String);
  String get serverKey => _$args.$1;
  String get spaceId => _$args.$2;

  Map<String, AccordMember>? build(String serverKey, String spaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<Map<String, AccordMember>?, Map<String, AccordMember>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                Map<String, AccordMember>?,
                Map<String, AccordMember>?
              >,
              Map<String, AccordMember>?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args.$1, _$args.$2));
  }
}
