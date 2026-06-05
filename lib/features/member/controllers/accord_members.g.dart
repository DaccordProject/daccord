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
    r'd790bb0fa1dbe69d520740eec8e664e6396b5f08';

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
