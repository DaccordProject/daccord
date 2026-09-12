import 'package:accordkit/accordkit.dart';

/// Pure helpers for spotting attachments that a `message.update` (or an
/// AutoMod refusal) took away, so the caches, the image cache and any open
/// viewer can let go of them.

/// Identity of an attachment for withdrawal matching: its ID, falling back to
/// its URL for servers that omit IDs.
String attachmentKey(AccordAttachment attachment) =>
    attachment.id.isNotEmpty ? attachment.id : attachment.url;

/// The attachments present on [previous] that [next] no longer carries.
/// Empty when [previous] is unknown (nothing cached to compare against) or
/// when nothing was withdrawn — an edit that only adds or reorders attachments
/// withdraws none.
List<AccordAttachment> withdrawnAttachments(
  AccordMessage? previous,
  AccordMessage next,
) {
  if (previous == null || previous.attachments.isEmpty) return const [];
  final kept = {for (final a in next.attachments) attachmentKey(a)};
  return [
    for (final a in previous.attachments)
      if (!kept.contains(attachmentKey(a))) a,
  ];
}

/// Strips the attachment whose ID (or URL) is [attachmentId] from [message]
/// in place and returns it, or null when the message doesn't carry it. In
/// place — the cache controllers already mutate their held messages (pinned,
/// reactions) and re-emit the list to trigger a rebuild.
AccordAttachment? removeAttachmentInPlace(
  AccordMessage message,
  String attachmentId,
) {
  final index = message.attachments.indexWhere(
    (a) => attachmentKey(a) == attachmentId,
  );
  if (index < 0) return null;
  final attachments = [...message.attachments];
  final removed = attachments.removeAt(index);
  message.attachments = attachments;
  return removed;
}
