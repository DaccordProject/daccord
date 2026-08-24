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
    extends $NotifierProvider<OnboardingController, bool> {
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
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$onboardingControllerHash() =>
    r'd188e332a41df02ffd82b279c744793761d884ed';

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

abstract class _$OnboardingController extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
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
