// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'onboarding_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the first-launch walkthrough's persistence and gating (#175).
///
/// **Persistence.** The seen-marker lives in the existing `accord-settings` Hive
/// box under its own [seenKey] (no new box), exactly as the release-notes
/// marker does. It is deliberately *not* a field on `AccordSettings`: settings
/// are exportable/importable between devices, and a "seen" marker that travels
/// with them would suppress the tour on a machine the user has never used.
///
/// The value stored is the app version that showed the tour, which costs
/// nothing and leaves the door open for a "this release changed the layout,
/// re-introduce it" decision later. Any non-empty value counts as seen.

@ProviderFor(OnboardingController)
const onboardingControllerProvider = OnboardingControllerProvider._();

/// Owns the first-launch walkthrough's persistence and gating (#175).
///
/// **Persistence.** The seen-marker lives in the existing `accord-settings` Hive
/// box under its own [seenKey] (no new box), exactly as the release-notes
/// marker does. It is deliberately *not* a field on `AccordSettings`: settings
/// are exportable/importable between devices, and a "seen" marker that travels
/// with them would suppress the tour on a machine the user has never used.
///
/// The value stored is the app version that showed the tour, which costs
/// nothing and leaves the door open for a "this release changed the layout,
/// re-introduce it" decision later. Any non-empty value counts as seen.
final class OnboardingControllerProvider
    extends $NotifierProvider<OnboardingController, OnboardingState> {
  /// Owns the first-launch walkthrough's persistence and gating (#175).
  ///
  /// **Persistence.** The seen-marker lives in the existing `accord-settings` Hive
  /// box under its own [seenKey] (no new box), exactly as the release-notes
  /// marker does. It is deliberately *not* a field on `AccordSettings`: settings
  /// are exportable/importable between devices, and a "seen" marker that travels
  /// with them would suppress the tour on a machine the user has never used.
  ///
  /// The value stored is the app version that showed the tour, which costs
  /// nothing and leaves the door open for a "this release changed the layout,
  /// re-introduce it" decision later. Any non-empty value counts as seen.
  const OnboardingControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onboardingControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onboardingControllerHash();

  @$internal
  @override
  OnboardingController create() => OnboardingController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(OnboardingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<OnboardingState>(value),
    );
  }
}

String _$onboardingControllerHash() =>
    r'231c2945552b06b8c3bb87774a9fa59a67ed574f';

/// Owns the first-launch walkthrough's persistence and gating (#175).
///
/// **Persistence.** The seen-marker lives in the existing `accord-settings` Hive
/// box under its own [seenKey] (no new box), exactly as the release-notes
/// marker does. It is deliberately *not* a field on `AccordSettings`: settings
/// are exportable/importable between devices, and a "seen" marker that travels
/// with them would suppress the tour on a machine the user has never used.
///
/// The value stored is the app version that showed the tour, which costs
/// nothing and leaves the door open for a "this release changed the layout,
/// re-introduce it" decision later. Any non-empty value counts as seen.

abstract class _$OnboardingController extends $Notifier<OnboardingState> {
  OnboardingState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<OnboardingState, OnboardingState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<OnboardingState, OnboardingState>,
              OnboardingState,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
