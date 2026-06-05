// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'spaces.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Holds the current user's space list — the left rail. Populated on gateway
/// ready (via `users.listSpaces()`) and kept in sync by space
/// create/update/delete gateway events. The Accord analogue of Bonfire's
/// `GuildsController`.

@ProviderFor(SpacesController)
const spacesControllerProvider = SpacesControllerProvider._();

/// Holds the current user's space list — the left rail. Populated on gateway
/// ready (via `users.listSpaces()`) and kept in sync by space
/// create/update/delete gateway events. The Accord analogue of Bonfire's
/// `GuildsController`.
final class SpacesControllerProvider
    extends $NotifierProvider<SpacesController, List<AccordSpace>?> {
  /// Holds the current user's space list — the left rail. Populated on gateway
  /// ready (via `users.listSpaces()`) and kept in sync by space
  /// create/update/delete gateway events. The Accord analogue of Bonfire's
  /// `GuildsController`.
  const SpacesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'spacesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$spacesControllerHash();

  @$internal
  @override
  SpacesController create() => SpacesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordSpace>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordSpace>?>(value),
    );
  }
}

String _$spacesControllerHash() => r'8919ce457730fd3af21890ce8db2cf3aa6f1e495';

/// Holds the current user's space list — the left rail. Populated on gateway
/// ready (via `users.listSpaces()`) and kept in sync by space
/// create/update/delete gateway events. The Accord analogue of Bonfire's
/// `GuildsController`.

abstract class _$SpacesController extends $Notifier<List<AccordSpace>?> {
  List<AccordSpace>? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<AccordSpace>?, List<AccordSpace>?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<AccordSpace>?, List<AccordSpace>?>,
              List<AccordSpace>?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
