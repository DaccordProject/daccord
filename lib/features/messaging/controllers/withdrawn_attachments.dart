import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/messaging/utils/attachment_withdrawal.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'withdrawn_attachments.g.dart';

/// Evicts one image URL from the app-controlled image caches (memory +
/// `cached_network_image`'s disk store). Swappable so tests can record the
/// URLs instead of touching the platform cache manager.
///
/// Only the *app's own* cache is touched. A copy the user already downloaded
/// or a byte range another program holds is theirs; nothing here claims to
/// revoke it.
@visibleForTesting
Future<void> Function(String url) evictCachedImage = _evictFromImageCaches;

Future<void> _evictFromImageCaches(String url) async {
  try {
    await CachedNetworkImage.evictFromCache(url);
  } catch (e) {
    debugPrint('Failed to evict withdrawn image $url: $e');
  }
}

/// Attachments the server has withdrawn from messages on one connection —
/// an AutoMod rejection/removal after publication, or any `message.update`
/// that shrank an attachment list. Keyed by [attachmentKey] (ID, else URL).
///
/// Two consumers: open viewers (the image lightbox) watch it and close when
/// the attachment they're showing disappears, and [withdraw] evicts the
/// withdrawn URLs from the image cache so a rebuild can't repaint them from
/// disk. Bounded — the last [maxRemembered] withdrawals.
@Riverpod(keepAlive: true)
class WithdrawnAttachmentsController extends _$WithdrawnAttachmentsController {
  static const maxRemembered = 200;

  @override
  Set<String> build(String serverKey) => const {};

  bool contains(String attachmentKey) => state.contains(attachmentKey);

  /// Records [attachments] as withdrawn and evicts their resolved URLs from
  /// the image cache. [cdnUrl] resolves the server's relative `/cdn/...`
  /// paths to the absolute URL the widgets loaded them under. Idempotent.
  void withdraw(Iterable<AccordAttachment> attachments, {String? cdnUrl}) {
    if (attachments.isEmpty) return;
    final next = <String>[...state];
    var changed = false;
    for (final attachment in attachments) {
      final key = attachmentKey(attachment);
      if (key.isEmpty) continue;
      if (!next.contains(key)) {
        next.add(key);
        changed = true;
      }
      if (attachment.url.isNotEmpty) {
        final resolved = AccordCDN.resolvePath(
          attachment.url,
          cdnUrl: cdnUrl ?? '',
        );
        evictCachedImage(resolved);
        if (resolved != attachment.url) evictCachedImage(attachment.url);
      }
    }
    if (!changed) return;
    if (next.length > maxRemembered) {
      next.removeRange(0, next.length - maxRemembered);
    }
    state = Set.unmodifiable(next);
  }
}
