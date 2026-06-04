// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'space.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-space cache, keyed by space ID.

@ProviderFor(SpaceController)
const spaceControllerProvider = SpaceControllerFamily._();

/// Per-space cache, keyed by space ID.
final class SpaceControllerProvider
    extends $NotifierProvider<SpaceController, AccordSpace?> {
  /// Per-space cache, keyed by space ID.
  const SpaceControllerProvider._({
    required SpaceControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'spaceControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$spaceControllerHash();

  @override
  String toString() {
    return r'spaceControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  SpaceController create() => SpaceController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccordSpace? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccordSpace?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is SpaceControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$spaceControllerHash() => r'00000000000000000000000000000000spacesngl';

/// Per-space cache, keyed by space ID.

final class SpaceControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          SpaceController,
          AccordSpace?,
          AccordSpace?,
          AccordSpace?,
          String
        > {
  const SpaceControllerFamily._()
    : super(
        retry: null,
        name: r'spaceControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-space cache, keyed by space ID.

  SpaceControllerProvider call(String spaceId) =>
      SpaceControllerProvider._(argument: spaceId, from: this);

  @override
  String toString() => r'spaceControllerProvider';
}

/// Per-space cache, keyed by space ID.

abstract class _$SpaceController extends $Notifier<AccordSpace?> {
  late final _$args = ref.$arg as String;
  String get spaceId => _$args;

  AccordSpace? build(String spaceId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<AccordSpace?, AccordSpace?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AccordSpace?, AccordSpace?>,
              AccordSpace?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
