// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accord_channels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".

@ProviderFor(AccordChannelsController)
const accordChannelsControllerProvider = AccordChannelsControllerFamily._();

/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".
final class AccordChannelsControllerProvider
    extends $NotifierProvider<AccordChannelsController, List<AccordChannel>?> {
  /// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
  /// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
  /// first time it's watched (once logged in) and is kept in sync by
  /// channel create/update/delete gateway events. `null` means "not loaded yet".
  const AccordChannelsControllerProvider._({
    required AccordChannelsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'accordChannelsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accordChannelsControllerHash();

  @override
  String toString() {
    return r'accordChannelsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccordChannelsController create() => AccordChannelsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordChannel>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordChannel>?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AccordChannelsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accordChannelsControllerHash() =>
    r'04f1f28c62ce2cc3c51d37d36c30c0fa56829784';

/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".

final class AccordChannelsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          AccordChannelsController,
          List<AccordChannel>?,
          List<AccordChannel>?,
          List<AccordChannel>?,
          String
        > {
  const AccordChannelsControllerFamily._()
    : super(
        retry: null,
        name: r'accordChannelsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
  /// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
  /// first time it's watched (once logged in) and is kept in sync by
  /// channel create/update/delete gateway events. `null` means "not loaded yet".

  AccordChannelsControllerProvider call(String spaceId) =>
      AccordChannelsControllerProvider._(argument: spaceId, from: this);

  @override
  String toString() => r'accordChannelsControllerProvider';
}

/// A space's channel list, keyed by space ID. The Accord analogue of Bonfire's
/// firebridge-backed channel list. Self-loads via `spaces.listChannels` the
/// first time it's watched (once logged in) and is kept in sync by
/// channel create/update/delete gateway events. `null` means "not loaded yet".

abstract class _$AccordChannelsController
    extends $Notifier<List<AccordChannel>?> {
  late final _$args = ref.$arg as String;
  String get spaceId => _$args;

  List<AccordChannel>? build(String spaceId);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref = this.ref as $Ref<List<AccordChannel>?, List<AccordChannel>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordChannel>?, List<AccordChannel>?>,
              List<AccordChannel>?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
