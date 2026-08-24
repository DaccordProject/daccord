// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_members.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Whether the initial roster fetch for a space failed (a non-2xx response, a
/// network error, or a timeout). Lets the roster show a retry affordance instead
/// of spinning forever when `members.list` never yields a list. Cleared on a
/// successful load, and by the roster's Retry button before it re-triggers
/// `_load`; set true only after the retries are exhausted.

@ProviderFor(MembersLoadFailed)
const membersLoadFailedProvider = MembersLoadFailedFamily._();

/// Whether the initial roster fetch for a space failed (a non-2xx response, a
/// network error, or a timeout). Lets the roster show a retry affordance instead
/// of spinning forever when `members.list` never yields a list. Cleared on a
/// successful load, and by the roster's Retry button before it re-triggers
/// `_load`; set true only after the retries are exhausted.
final class MembersLoadFailedProvider
    extends $NotifierProvider<MembersLoadFailed, bool> {
  /// Whether the initial roster fetch for a space failed (a non-2xx response, a
  /// network error, or a timeout). Lets the roster show a retry affordance instead
  /// of spinning forever when `members.list` never yields a list. Cleared on a
  /// successful load, and by the roster's Retry button before it re-triggers
  /// `_load`; set true only after the retries are exhausted.
  const MembersLoadFailedProvider._({
    required MembersLoadFailedFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'membersLoadFailedProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$membersLoadFailedHash();

  @override
  String toString() {
    return r'membersLoadFailedProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MembersLoadFailed create() => MembersLoadFailed();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MembersLoadFailedProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$membersLoadFailedHash() => r'13daffe42918003e1b2b4dcdaf0e5120feadfc47';

/// Whether the initial roster fetch for a space failed (a non-2xx response, a
/// network error, or a timeout). Lets the roster show a retry affordance instead
/// of spinning forever when `members.list` never yields a list. Cleared on a
/// successful load, and by the roster's Retry button before it re-triggers
/// `_load`; set true only after the retries are exhausted.

final class MembersLoadFailedFamily extends $Family
    with $ClassFamilyOverride<MembersLoadFailed, bool, bool, bool, String> {
  const MembersLoadFailedFamily._()
    : super(
        retry: null,
        name: r'membersLoadFailedProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Whether the initial roster fetch for a space failed (a non-2xx response, a
  /// network error, or a timeout). Lets the roster show a retry affordance instead
  /// of spinning forever when `members.list` never yields a list. Cleared on a
  /// successful load, and by the roster's Retry button before it re-triggers
  /// `_load`; set true only after the retries are exhausted.

  MembersLoadFailedProvider call(String spaceId) =>
      MembersLoadFailedProvider._(argument: spaceId, from: this);

  @override
  String toString() => r'membersLoadFailedProvider';
}

/// Whether the initial roster fetch for a space failed (a non-2xx response, a
/// network error, or a timeout). Lets the roster show a retry affordance instead
/// of spinning forever when `members.list` never yields a list. Cleared on a
/// successful load, and by the roster's Retry button before it re-triggers
/// `_load`; set true only after the retries are exhausted.

abstract class _$MembersLoadFailed extends $Notifier<bool> {
  late final _$args = ref.$arg as String;
  String get spaceId => _$args;

  bool build(String spaceId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".

@ProviderFor(AccordMembersController)
const accordMembersControllerProvider = AccordMembersControllerFamily._();

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
  const AccordMembersControllerProvider._({
    required AccordMembersControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'accordMembersControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordMembersControllerHash();

  @override
  String toString() {
    return r'accordMembersControllerProvider'
        ''
        '($argument)';
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
    r'02fdb824d429b2d3bcbf1d7f128db3c762a918c6';

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
          String
        > {
  const AccordMembersControllerFamily._()
    : super(
        retry: null,
        name: r'accordMembersControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's members, keyed by space ID and indexed by user ID for O(1) author
  /// resolution. Self-loads via `members.list` the first time it's watched (once
  /// logged in) and is kept in sync by member join/update/leave gateway events.
  /// `null` means "not loaded yet".

  AccordMembersControllerProvider call(String spaceId) =>
      AccordMembersControllerProvider._(argument: spaceId, from: this);

  @override
  String toString() => r'accordMembersControllerProvider';
}

/// A space's members, keyed by space ID and indexed by user ID for O(1) author
/// resolution. Self-loads via `members.list` the first time it's watched (once
/// logged in) and is kept in sync by member join/update/leave gateway events.
/// `null` means "not loaded yet".

abstract class _$AccordMembersController
    extends $Notifier<Map<String, AccordMember>?> {
  late final _$args = ref.$arg as String;
  String get spaceId => _$args;

  Map<String, AccordMember>? build(String spaceId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
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
    element.handleValue(ref, created);
  }
}
