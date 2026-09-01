// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'hidden_messages.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Messages the user has reported and therefore no longer wants to see.
///
/// Reporting content in a space hands it to that space's moderators, but
/// nothing about their decision is instant — and a direct message has no
/// moderator at all. Either way the reporter should stop seeing what they just
/// flagged, so the pane filters these out locally, on this device, for good
/// (App Review 1.2, #290).

@ProviderFor(HiddenMessagesController)
const hiddenMessagesControllerProvider = HiddenMessagesControllerProvider._();

/// Messages the user has reported and therefore no longer wants to see.
///
/// Reporting content in a space hands it to that space's moderators, but
/// nothing about their decision is instant — and a direct message has no
/// moderator at all. Either way the reporter should stop seeing what they just
/// flagged, so the pane filters these out locally, on this device, for good
/// (App Review 1.2, #290).
final class HiddenMessagesControllerProvider
    extends $NotifierProvider<HiddenMessagesController, Set<String>> {
  /// Messages the user has reported and therefore no longer wants to see.
  ///
  /// Reporting content in a space hands it to that space's moderators, but
  /// nothing about their decision is instant — and a direct message has no
  /// moderator at all. Either way the reporter should stop seeing what they just
  /// flagged, so the pane filters these out locally, on this device, for good
  /// (App Review 1.2, #290).
  const HiddenMessagesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'hiddenMessagesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$hiddenMessagesControllerHash();

  @$internal
  @override
  HiddenMessagesController create() => HiddenMessagesController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Set<String> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Set<String>>(value),
    );
  }
}

String _$hiddenMessagesControllerHash() =>
    r'5677ed030d1d42ca7e891d72706e7c0989d3873b';

/// Messages the user has reported and therefore no longer wants to see.
///
/// Reporting content in a space hands it to that space's moderators, but
/// nothing about their decision is instant — and a direct message has no
/// moderator at all. Either way the reporter should stop seeing what they just
/// flagged, so the pane filters these out locally, on this device, for good
/// (App Review 1.2, #290).

abstract class _$HiddenMessagesController extends $Notifier<Set<String>> {
  Set<String> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<Set<String>, Set<String>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<Set<String>, Set<String>>,
              Set<String>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
