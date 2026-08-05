import 'package:bonfire/features/messaging/utils/attachment_types.dart';

/// Fallback maximum size of a single attachment, mirroring the limit documented
/// in `docs/messaging/file-sharing.md` and the accordserver default
/// (`max_attachment_size`, 26214400).
///
/// This is only the fallback: the live limit comes from the server's
/// `GET /settings` via `AccordServerLimits`, because it is per-deployment
/// configuration. Enforced client-side so an oversize file is rejected at pick
/// time with a clear message, rather than being read into memory, assembled
/// into a multipart body and uploaded in full only to come back as an opaque
/// server error.
const int kMaxAttachmentBytes = 25 * 1024 * 1024;

/// Fallback maximum number of files on one message, matching the accordserver
/// default (`max_attachments_per_message`, 10). As with [kMaxAttachmentBytes]
/// the live value comes from `GET /settings`.
const int kMaxAttachmentsPerMessage = 10;

/// Renders a byte count for user-facing messages ("41.2 MB", "812 KB").
String formatFileSize(int bytes) {
  const kb = 1024;
  const mb = kb * 1024;
  if (bytes >= mb) {
    final value = bytes / mb;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)} MB';
  }
  if (bytes >= kb) return '${(bytes / kb).round()} KB';
  return '$bytes bytes';
}

/// Message for a file that couldn't be read into memory (a cloud- or
/// provider-backed file the platform declined to hand over bytes for).
/// Shared by the picker and drag-and-drop paths so the wording never drifts
/// between the two.
String unreadableAttachmentMessage(String name) =>
    "$name couldn't be read. Copy it to local storage and try again.";

/// Message for a file that exceeds [maxBytes]. Shared by the picker and
/// drag-and-drop paths so the wording never drifts between the two.
String oversizeAttachmentMessage(
  String name,
  int size, {
  int maxBytes = kMaxAttachmentBytes,
}) =>
    '$name is ${formatFileSize(size)} — the limit is '
    '${formatFileSize(maxBytes)}.';

/// Message for a file dropped past the server's per-message file count.
String tooManyAttachmentsMessage(String name, int maxCount) =>
    "$name wasn't attached — you can send at most $maxCount "
    '${maxCount == 1 ? 'file' : 'files'} per message.';

/// The outcome of screening picked files: the ones that can be attached, plus a
/// line per file that can't be, naming it and why.
class AttachmentScreening {
  const AttachmentScreening({required this.accepted, required this.rejections});

  final List<PendingAttachment> accepted;

  /// One human-readable line per rejected file.
  final List<String> rejections;

  /// The rejections as a single message, or null when nothing was rejected.
  String? get error => rejections.isEmpty ? null : rejections.join('\n');
}

/// Screens [files] for attachability.
///
/// Three things disqualify a file, and the first two used to be dropped
/// silently — the composer kept any file with bytes and said nothing about the
/// rest:
///
/// - the picker returned no bytes (a cloud- or provider-backed file the
///   platform couldn't read into memory);
/// - the file exceeds [maxBytes], which music and video routinely do where the
///   images this flow was built around never did;
/// - it would push the message past [maxCount] files, counting the
///   [alreadyAttached] ones already on the composer. The server rejects the
///   whole upload in that case, so catching it here saves losing the rest of
///   the batch too.
///
/// Both limits default to the compiled-in fallbacks; callers pass the connected
/// server's own values (see `AccordServerLimits`).
AttachmentScreening screenAttachments(
  Iterable<PendingAttachment> files, {
  int maxBytes = kMaxAttachmentBytes,
  int maxCount = kMaxAttachmentsPerMessage,
  int alreadyAttached = 0,
}) {
  final accepted = <PendingAttachment>[];
  final rejections = <String>[];
  var count = alreadyAttached;
  for (final file in files) {
    final bytes = file.bytes;
    if (bytes == null) {
      rejections.add(unreadableAttachmentMessage(file.name));
      continue;
    }
    if (bytes.length > maxBytes) {
      rejections.add(
        oversizeAttachmentMessage(file.name, bytes.length, maxBytes: maxBytes),
      );
      continue;
    }
    if (count >= maxCount) {
      rejections.add(tooManyAttachmentsMessage(file.name, maxCount));
      continue;
    }
    count += 1;
    accepted.add(file);
  }
  return AttachmentScreening(accepted: accepted, rejections: rejections);
}
