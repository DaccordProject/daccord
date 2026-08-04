import 'package:file_picker/file_picker.dart';

/// Maximum size of a single attachment, mirroring the limit documented in
/// `docs/messaging/file-sharing.md`.
///
/// Enforced client-side so an oversize file is rejected at pick time with a
/// clear message, rather than being read into memory, assembled into a
/// multipart body and uploaded in full only to come back as an opaque server
/// error.
const int kMaxAttachmentBytes = 25 * 1024 * 1024;

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

/// The outcome of screening picked files: the ones that can be attached, plus a
/// line per file that can't be, naming it and why.
class AttachmentScreening {
  const AttachmentScreening({required this.accepted, required this.rejections});

  final List<PlatformFile> accepted;

  /// One human-readable line per rejected file.
  final List<String> rejections;

  /// The rejections as a single message, or null when nothing was rejected.
  String? get error => rejections.isEmpty ? null : rejections.join('\n');
}

/// Screens [files] for attachability.
///
/// Two things disqualify a file, and both used to be dropped silently — the
/// composer kept any file with bytes and said nothing about the rest:
///
/// - the picker returned no bytes (a cloud- or provider-backed file the
///   platform couldn't read into memory);
/// - the file exceeds [maxBytes], which music and video routinely do where the
///   images this flow was built around never did.
AttachmentScreening screenAttachments(
  Iterable<PlatformFile> files, {
  int maxBytes = kMaxAttachmentBytes,
}) {
  final accepted = <PlatformFile>[];
  final rejections = <String>[];
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
    accepted.add(file);
  }
  return AttachmentScreening(accepted: accepted, rejections: rejections);
}
