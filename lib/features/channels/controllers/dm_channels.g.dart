// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dm_channels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Global cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).

@ProviderFor(DmChannelsController)
const dmChannelsControllerProvider = DmChannelsControllerProvider._();

/// Global cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).
final class DmChannelsControllerProvider
    extends $NotifierProvider<DmChannelsController, List<AccordChannel>?> {
  /// Global cache of the current user's direct-message and group-DM channels
  /// (the ones with no `spaceId`). The direct-messages dialog populates it from a
  /// one-shot `users.listChannels` fetch and then watches it, while
  /// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
  /// created remotely appear, renames / recipient changes (which arrive as
  /// `channel.update`) update in place, and leaves / deletions remove the entry.
  ///
  /// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
  /// that transitions it out of null, so gateway upserts that arrive before the
  /// dialog has ever opened are intentionally dropped (the next open refetches).
  const DmChannelsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dmChannelsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dmChannelsControllerHash();

  @$internal
  @override
  DmChannelsController create() => DmChannelsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<AccordChannel>? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<AccordChannel>?>(value),
    );
  }
}

String _$dmChannelsControllerHash() =>
    r'a23e172bac560a85818be5f89f881df08c9ea1ba';

/// Global cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).

abstract class _$DmChannelsController extends $Notifier<List<AccordChannel>?> {
  List<AccordChannel>? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
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
