import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/models/pending_upload.dart';
import 'package:bonfire/features/messaging/utils/pending_upload_store.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'pending_uploads.g.dart';

/// The held/refused uploads of one connection, keyed by upload ID, with a
/// per-message index for the message rows.
class PendingUploadsSnapshot {
  PendingUploadsSnapshot([Map<String, PendingUpload>? uploads])
    : uploads = Map.unmodifiable(uploads ?? const <String, PendingUpload>{}) {
    final byMessage = <String, List<PendingUpload>>{};
    for (final upload in this.uploads.values) {
      (byMessage[upload.messageId] ??= []).add(upload);
    }
    _byMessage = {
      for (final e in byMessage.entries) e.key: List.unmodifiable(e.value),
    };
  }

  /// Uploads by upload ID (also the eventual attachment ID).
  final Map<String, PendingUpload> uploads;
  late final Map<String, List<PendingUpload>> _byMessage;

  /// The held/refused uploads belonging to [messageId], in tracking order.
  /// Returns the same `const []` for every message without any, so a
  /// `select` on it doesn't rebuild rows that have nothing to show.
  List<PendingUpload> forMessage(String messageId) =>
      _byMessage[messageId] ?? const [];

  /// Uploads the server may still publish or refuse.
  Iterable<PendingUpload> get outstanding =>
      uploads.values.where((u) => u.isOutstanding);

  bool get hasOutstanding => uploads.values.any((u) => u.isOutstanding);
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
@Riverpod(keepAlive: true)
class PendingUploadsController extends _$PendingUploadsController {
  /// Delay between fallback polls after [reconcile] finds uploads still
  /// pending. Overridable for tests.
  static Duration fallbackPollInterval = const Duration(seconds: 45);

  /// How many fallback polls a single [reconcile] may schedule.
  static int maxFallbackPolls = 4;

  /// Hard cap on tracked entries; the oldest refused ones go first.
  static const maxEntries = 200;

  /// Bound on buffered events for IDs the composer hasn't reported yet.
  static const maxEarlyEvents = 32;

  /// Status events that arrived before their upload was tracked, by upload ID.
  final Map<String, String> _early = {};

  /// Upload IDs whose decision details have already been requested.
  final Set<String> _reasonRequested = {};

  Timer? _pollTimer;
  int _pollsLeft = 0;

  @override
  PendingUploadsSnapshot build(String serverKey) {
    ref.onDispose(() => _pollTimer?.cancel());
    return PendingUploadsSnapshot({
      for (final upload in PendingUploadStore.load(serverKey))
        upload.id: upload,
    });
  }

  /// Records the [uploadIds] a `202 Accepted` listed for [message]. Any
  /// status event that already arrived for one of them is applied at once.
  void track(
    AccordMessage message,
    List<String> uploadIds, {
    AccordClient? client,
  }) {
    if (uploadIds.isEmpty) return;
    final next = {...state.uploads};
    final needReason = <String>[];
    for (final id in uploadIds) {
      if (id.isEmpty || next.containsKey(id)) continue;
      final earlyStatus = _early.remove(id);
      if (earlyStatus == AutomodUploadStatus.published) continue;
      final upload = PendingUpload(
        id: id,
        messageId: message.id,
        channelId: message.channelId,
        spaceId: message.spaceId,
        status: earlyStatus ?? AutomodUploadStatus.pending,
      );
      next[id] = upload;
      if (_wantsReason(upload)) needReason.add(id);
    }
    _set(next);
    if (client != null) {
      for (final id in needReason) {
        unawaited(_fetchDetails(client, id));
      }
    }
  }

  /// Applies an `automod.upload_status` / `automod.upload_update` event.
  ///
  /// [bufferUnknown] is true for the uploader stream, whose every event is
  /// about one of our uploads — an ID we don't know yet is one whose HTTP
  /// response hasn't landed. The moderator stream covers other people's
  /// uploads too, so its unknown IDs are ignored.
  void applyStatus(
    AccordAutomodUploadStatus status, {
    AccordClient? client,
    bool bufferUnknown = true,
  }) {
    final id = status.id;
    if (id.isEmpty) return;
    final existing = state.uploads[id];
    if (existing == null) {
      if (bufferUnknown) _rememberEarly(id, status.status);
      return;
    }
    _advance(existing, status.status, client: client);
  }

  /// A `message.update` that carries an attachment whose ID we're tracking
  /// means that upload was published — drop the placeholder even if the
  /// `published` status event is late or lost.
  void applyPublishedAttachments(AccordMessage message) {
    if (message.attachments.isEmpty || state.uploads.isEmpty) return;
    final published = [
      for (final a in message.attachments)
        if (state.uploads.containsKey(a.id)) a.id,
    ];
    if (published.isEmpty) return;
    final next = {...state.uploads}
      ..removeWhere((id, _) => published.contains(id));
    _reasonRequested.removeAll(published);
    _set(next);
  }

  /// Drops every entry for [messageId] (the message was deleted).
  void clearForMessage(String messageId) {
    if (state.forMessage(messageId).isEmpty) return;
    final next = {...state.uploads}
      ..removeWhere((_, u) => u.messageId == messageId);
    _set(next);
  }

  /// Drops one entry (e.g. the user dismissed a refusal placeholder).
  void dismiss(String uploadId) {
    if (!state.uploads.containsKey(uploadId)) return;
    _reasonRequested.remove(uploadId);
    _set({...state.uploads}..remove(uploadId));
  }

  /// After READY: asks the server about every outstanding upload once, then
  /// — only while some remain pending — polls up to [maxFallbackPolls] more
  /// times, [fallbackPollInterval] apart. Never touches the moderator queue.
  Future<void> reconcile(AccordClient client) async {
    _pollTimer?.cancel();
    await _refreshOutstanding(client);
    if (!ref.mounted || !state.hasOutstanding) return;
    _pollsLeft = maxFallbackPolls;
    _scheduleFallbackPoll(client);
  }

  void _scheduleFallbackPoll(AccordClient client) {
    _pollTimer?.cancel();
    if (_pollsLeft <= 0 || !state.hasOutstanding) return;
    _pollTimer = Timer(fallbackPollInterval, () async {
      _pollsLeft -= 1;
      if (!ref.mounted || !state.hasOutstanding) return;
      await _refreshOutstanding(client);
      if (!ref.mounted) return;
      _scheduleFallbackPoll(client);
    });
  }

  Future<void> _refreshOutstanding(AccordClient client) async {
    for (final upload in state.outstanding.toList()) {
      await _fetchDetails(client, upload.id, missingMeansRemoved: true);
      if (!ref.mounted) return;
    }
  }

  /// Fetches the authorized status/reason for [id] and folds it in.
  ///
  /// A 404 on a post-READY lookup ([missingMeansRemoved]) means the server no
  /// longer holds an upload we last saw outstanding — the retention window
  /// lapsed — which is a removal. A 404 on a reason lookup for a status the
  /// gateway just reported changes nothing: the status stands, we simply
  /// have no reason to show. Other failures leave the entry untouched for
  /// the next event or poll.
  Future<void> _fetchDetails(
    AccordClient client,
    String id, {
    bool missingMeansRemoved = false,
  }) async {
    _reasonRequested.add(id);
    final result = await client.automod.getUpload(id);
    if (!ref.mounted) return;
    final existing = state.uploads[id];
    if (existing == null) return;
    final details = result.data;
    if (result.ok && details is AccordAutomodUpload) {
      _advance(existing, details.status, reason: details.reason);
      return;
    }
    if (result.statusCode == 404) {
      if (missingMeansRemoved) _advance(existing, AutomodUploadStatus.removed);
      return;
    }
    debugPrint('Failed to fetch AutoMod upload $id: ${result.error}');
    // Allow a later event to retry the reason lookup.
    _reasonRequested.remove(id);
  }

  void _advance(
    PendingUpload existing,
    String status, {
    String? reason,
    AccordClient? client,
  }) {
    if (status == AutomodUploadStatus.published) {
      _reasonRequested.remove(existing.id);
      _set({...state.uploads}..remove(existing.id));
      return;
    }
    final updated = existing.copyWith(status: status, reason: reason);
    if (updated != existing) {
      _set({...state.uploads, existing.id: updated});
    }
    if (client != null &&
        _wantsReason(updated) &&
        !_reasonRequested.contains(updated.id)) {
      unawaited(_fetchDetails(client, updated.id));
    }
  }

  /// Whether a decision worth explaining has been made and not yet explained.
  static bool _wantsReason(PendingUpload upload) =>
      upload.reason == null &&
      (upload.isRefused || upload.status == AutomodUploadStatus.quarantined);

  void _rememberEarly(String id, String status) {
    _early[id] = status;
    while (_early.length > maxEarlyEvents) {
      _early.remove(_early.keys.first);
    }
  }

  void _set(Map<String, PendingUpload> next) {
    if (next.length > maxEntries) {
      final ordered = next.keys.toList();
      // Oldest refused entries first — they're only placeholders — then the
      // oldest of whatever's left.
      final refused = ordered.where((id) => next[id]!.isRefused).toList();
      for (final id in [...refused, ...ordered]) {
        if (next.length <= maxEntries) break;
        next.remove(id);
      }
    }
    state = PendingUploadsSnapshot(next);
    unawaited(PendingUploadStore.save(serverKey, next.values));
  }
}
