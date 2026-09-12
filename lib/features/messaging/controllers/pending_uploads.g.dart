// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_uploads.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks this account's AutoMod-held uploads on one connection so the sender
/// sees *where* an attachment is rather than a message that silently lost it.
///
/// Fed by three sources, reconciled by upload ID:
///  * the composer's `202 Accepted` response — [track] records the IDs;
///  * `automod.upload_status` gateway events — [applyStatus] advances them
///    (`published` drops the entry: the accompanying `message.update` carries
///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
///    that status for the placeholder);
///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
///    outstanding ID once, then polls a bounded number of times while any
///    stay pending, since a fresh session replays nothing.
///
/// An event can beat the HTTP response it belongs to; unknown IDs from the
/// uploader stream are buffered and folded in when [track] names them. Every
/// mutation is idempotent, so a repeated event is a no-op. Persisted per
/// connection via [PendingUploadStore] so a restart doesn't orphan a
/// placeholder.
///
/// Reasons are fetched only here — for this account's own uploads, which are
/// the only ones the uploader stream ever names. The moderator queue routes
/// are never called.

@ProviderFor(PendingUploadsController)
const pendingUploadsControllerProvider = PendingUploadsControllerFamily._();

/// Tracks this account's AutoMod-held uploads on one connection so the sender
/// sees *where* an attachment is rather than a message that silently lost it.
///
/// Fed by three sources, reconciled by upload ID:
///  * the composer's `202 Accepted` response — [track] records the IDs;
///  * `automod.upload_status` gateway events — [applyStatus] advances them
///    (`published` drops the entry: the accompanying `message.update` carries
///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
///    that status for the placeholder);
///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
///    outstanding ID once, then polls a bounded number of times while any
///    stay pending, since a fresh session replays nothing.
///
/// An event can beat the HTTP response it belongs to; unknown IDs from the
/// uploader stream are buffered and folded in when [track] names them. Every
/// mutation is idempotent, so a repeated event is a no-op. Persisted per
/// connection via [PendingUploadStore] so a restart doesn't orphan a
/// placeholder.
///
/// Reasons are fetched only here — for this account's own uploads, which are
/// the only ones the uploader stream ever names. The moderator queue routes
/// are never called.
final class PendingUploadsControllerProvider
    extends
        $NotifierProvider<PendingUploadsController, PendingUploadsSnapshot> {
  /// Tracks this account's AutoMod-held uploads on one connection so the sender
  /// sees *where* an attachment is rather than a message that silently lost it.
  ///
  /// Fed by three sources, reconciled by upload ID:
  ///  * the composer's `202 Accepted` response — [track] records the IDs;
  ///  * `automod.upload_status` gateway events — [applyStatus] advances them
  ///    (`published` drops the entry: the accompanying `message.update` carries
  ///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
  ///    that status for the placeholder);
  ///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
  ///    outstanding ID once, then polls a bounded number of times while any
  ///    stay pending, since a fresh session replays nothing.
  ///
  /// An event can beat the HTTP response it belongs to; unknown IDs from the
  /// uploader stream are buffered and folded in when [track] names them. Every
  /// mutation is idempotent, so a repeated event is a no-op. Persisted per
  /// connection via [PendingUploadStore] so a restart doesn't orphan a
  /// placeholder.
  ///
  /// Reasons are fetched only here — for this account's own uploads, which are
  /// the only ones the uploader stream ever names. The moderator queue routes
  /// are never called.
  const PendingUploadsControllerProvider._({
    required PendingUploadsControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'pendingUploadsControllerProvider',
         isAutoDispose: false,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pendingUploadsControllerHash();

  @override
  String toString() {
    return r'pendingUploadsControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PendingUploadsController create() => PendingUploadsController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PendingUploadsSnapshot value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PendingUploadsSnapshot>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PendingUploadsControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pendingUploadsControllerHash() =>
    r'ea5b5b3b0a1630e323cfe770c1754e1ce740de0b';

/// Tracks this account's AutoMod-held uploads on one connection so the sender
/// sees *where* an attachment is rather than a message that silently lost it.
///
/// Fed by three sources, reconciled by upload ID:
///  * the composer's `202 Accepted` response — [track] records the IDs;
///  * `automod.upload_status` gateway events — [applyStatus] advances them
///    (`published` drops the entry: the accompanying `message.update` carries
///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
///    that status for the placeholder);
///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
///    outstanding ID once, then polls a bounded number of times while any
///    stay pending, since a fresh session replays nothing.
///
/// An event can beat the HTTP response it belongs to; unknown IDs from the
/// uploader stream are buffered and folded in when [track] names them. Every
/// mutation is idempotent, so a repeated event is a no-op. Persisted per
/// connection via [PendingUploadStore] so a restart doesn't orphan a
/// placeholder.
///
/// Reasons are fetched only here — for this account's own uploads, which are
/// the only ones the uploader stream ever names. The moderator queue routes
/// are never called.

final class PendingUploadsControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          PendingUploadsController,
          PendingUploadsSnapshot,
          PendingUploadsSnapshot,
          PendingUploadsSnapshot,
          String
        > {
  const PendingUploadsControllerFamily._()
    : super(
        retry: null,
        name: r'pendingUploadsControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: false,
      );

  /// Tracks this account's AutoMod-held uploads on one connection so the sender
  /// sees *where* an attachment is rather than a message that silently lost it.
  ///
  /// Fed by three sources, reconciled by upload ID:
  ///  * the composer's `202 Accepted` response — [track] records the IDs;
  ///  * `automod.upload_status` gateway events — [applyStatus] advances them
  ///    (`published` drops the entry: the accompanying `message.update` carries
  ///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
  ///    that status for the placeholder);
  ///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
  ///    outstanding ID once, then polls a bounded number of times while any
  ///    stay pending, since a fresh session replays nothing.
  ///
  /// An event can beat the HTTP response it belongs to; unknown IDs from the
  /// uploader stream are buffered and folded in when [track] names them. Every
  /// mutation is idempotent, so a repeated event is a no-op. Persisted per
  /// connection via [PendingUploadStore] so a restart doesn't orphan a
  /// placeholder.
  ///
  /// Reasons are fetched only here — for this account's own uploads, which are
  /// the only ones the uploader stream ever names. The moderator queue routes
  /// are never called.

  PendingUploadsControllerProvider call(String serverKey) =>
      PendingUploadsControllerProvider._(argument: serverKey, from: this);

  @override
  String toString() => r'pendingUploadsControllerProvider';
}

/// Tracks this account's AutoMod-held uploads on one connection so the sender
/// sees *where* an attachment is rather than a message that silently lost it.
///
/// Fed by three sources, reconciled by upload ID:
///  * the composer's `202 Accepted` response — [track] records the IDs;
///  * `automod.upload_status` gateway events — [applyStatus] advances them
///    (`published` drops the entry: the accompanying `message.update` carries
///    the real attachment; `rejected`/`removed`/`quarantined` keep it with
///    that status for the placeholder);
///  * READY — [reconcile] asks `GET /automod/uploads/{id}` about every
///    outstanding ID once, then polls a bounded number of times while any
///    stay pending, since a fresh session replays nothing.
///
/// An event can beat the HTTP response it belongs to; unknown IDs from the
/// uploader stream are buffered and folded in when [track] names them. Every
/// mutation is idempotent, so a repeated event is a no-op. Persisted per
/// connection via [PendingUploadStore] so a restart doesn't orphan a
/// placeholder.
///
/// Reasons are fetched only here — for this account's own uploads, which are
/// the only ones the uploader stream ever names. The moderator queue routes
/// are never called.

abstract class _$PendingUploadsController
    extends $Notifier<PendingUploadsSnapshot> {
  late final _$args = ref.$arg as String;
  String get serverKey => _$args;

  PendingUploadsSnapshot build(String serverKey);
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build(_$args);
    final ref =
        this.ref as $Ref<PendingUploadsSnapshot, PendingUploadsSnapshot>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<PendingUploadsSnapshot, PendingUploadsSnapshot>,
              PendingUploadsSnapshot,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
