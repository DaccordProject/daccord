// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dm_channels.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Per-server cache of the current user's direct-message and group-DM channels
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
const dmChannelsControllerProvider = DmChannelsControllerFamily._();

/// Per-server cache of the current user's direct-message and group-DM channels
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
  /// Per-server cache of the current user's direct-message and group-DM channels
  /// (the ones with no `spaceId`). The direct-messages dialog populates it from a
  /// one-shot `users.listChannels` fetch and then watches it, while
  /// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
  /// created remotely appear, renames / recipient changes (which arrive as
  /// `channel.update`) update in place, and leaves / deletions remove the entry.
  ///
  /// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
  /// that transitions it out of null, so gateway upserts that arrive before the
  /// dialog has ever opened are intentionally dropped (the next open refetches).
  const DmChannelsControllerProvider._({
    required DmChannelsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'dmChannelsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$dmChannelsControllerHash();

  @override
  String toString() {
    return r'dmChannelsControllerProvider'
        ''
        '($argument)';
  }

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

  @override
  bool operator ==(Object other) {
    return other is DmChannelsControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$dmChannelsControllerHash() =>
    r'da7c5e45e5953677fc5a74eba49e18cddddf663e';

/// Per-server cache of the current user's direct-message and group-DM channels
/// (the ones with no `spaceId`). The direct-messages dialog populates it from a
/// one-shot `users.listChannels` fetch and then watches it, while
/// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
/// created remotely appear, renames / recipient changes (which arrive as
/// `channel.update`) update in place, and leaves / deletions remove the entry.
///
/// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
/// that transitions it out of null, so gateway upserts that arrive before the
/// dialog has ever opened are intentionally dropped (the next open refetches).

final class DmChannelsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          DmChannelsController,
          List<AccordChannel>?,
          List<AccordChannel>?,
          List<AccordChannel>?,
          String
        > {
  const DmChannelsControllerFamily._()
    : super(
        retry: null,
        name: r'dmChannelsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Per-server cache of the current user's direct-message and group-DM channels
  /// (the ones with no `spaceId`). The direct-messages dialog populates it from a
  /// one-shot `users.listChannels` fetch and then watches it, while
  /// `accord_event_handler.dart` keeps it in sync from the gateway: group DMs
  /// created remotely appear, renames / recipient changes (which arrive as
  /// `channel.update`) update in place, and leaves / deletions remove the entry.
  ///
  /// A `null` state means "not loaded yet" — the dialog's fetch is the only thing
  /// that transitions it out of null, so gateway upserts that arrive before the
  /// dialog has ever opened are intentionally dropped (the next open refetches).

  DmChannelsControllerProvider call(String serverKey) =>
      DmChannelsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'dmChannelsControllerProvider';
}

/// Per-server cache of the current user's direct-message and group-DM channels
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
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  List<AccordChannel>? build(String serverKey);
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
