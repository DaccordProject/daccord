/// Saving a message attachment to the user's device.
///
/// One entry point — [downloadAttachment] — with three platform behaviours,
/// resolved by conditional import so callers never branch:
///
/// * **Desktop** (Windows/macOS/Linux): streams the URL straight to the OS
///   Downloads directory (`path_provider`'s `getDownloadsDirectory()`), so a
///   large file never has to be held in memory. [revealDownloadedFile] can then
///   open the containing folder.
/// * **Mobile**: fetches the bytes and hands them to the platform save sheet
///   (`file_picker`'s `saveFile`), which is the only sanctioned way to write
///   outside the sandbox on Android/iOS.
/// * **Web**: hands the URL to the browser (`launchUrl`), which downloads it.
///
/// Built for the inline audio player (#197) but deliberately widget-agnostic:
/// the video player, the image lightbox and the generic `📎 filename` file row
/// are all meant to adopt this rather than grow their own copies.
///
/// ## Safety
///
/// Attachment filenames come from whoever uploaded the file, so they are
/// treated as hostile: [sanitizeAttachmentFilename] reduces one to a single
/// harmless path segment before it is ever joined onto a directory, and the
/// native implementation re-checks that the resolved target really is a direct
/// child of the download directory before opening a sink. Existing files are
/// never overwritten — `track.mp3` lands beside its predecessor as
/// `track (1).mp3`.
library;

import 'package:bonfire/shared/utils/download_attachment_web.dart'
    if (dart.library.io) 'package:bonfire/shared/utils/download_attachment_io.dart'
    as impl;
import 'package:path/path.dart' as p;

/// How a [downloadAttachment] call ended.
enum DownloadOutcome {
  /// The file was written; [DownloadResult.path] says where (desktop/mobile).
  saved,

  /// Handed off to the browser's own download machinery (web). There is no
  /// path to reveal and no way to observe completion.
  handedToBrowser,

  /// The user dismissed the platform save sheet. Not an error; say nothing.
  cancelled,

  /// Something went wrong; [DownloadResult.error] is safe to show the user.
  failed,
}

/// The outcome of a [downloadAttachment] call.
///
/// Failures are returned rather than thrown so a widget can render them inline
/// without wrapping every call in a try/catch (silently swallowing a failed
/// download is the one behaviour this must not allow).
class DownloadResult {
  const DownloadResult._(this.outcome, {this.path, this.error});

  const DownloadResult.saved(String path)
      : this._(DownloadOutcome.saved, path: path);

  const DownloadResult.handedToBrowser()
      : this._(DownloadOutcome.handedToBrowser);

  const DownloadResult.cancelled() : this._(DownloadOutcome.cancelled);

  const DownloadResult.failed(String error)
      : this._(DownloadOutcome.failed, error: error);

  final DownloadOutcome outcome;

  /// Where the file landed, when the platform reports one.
  final String? path;

  /// A user-facing explanation, set only when [outcome] is
  /// [DownloadOutcome.failed].
  final String? error;

  /// Whether the download finished successfully (on any platform).
  bool get ok =>
      outcome == DownloadOutcome.saved ||
      outcome == DownloadOutcome.handedToBrowser;

  /// Whether [revealDownloadedFile] can do anything useful with [path].
  bool get canReveal => outcome == DownloadOutcome.saved && path != null;
}

/// Reports download progress as a 0..1 fraction, or `null` when the server
/// sent no `Content-Length` and the total is therefore unknown.
typedef DownloadProgressCallback = void Function(double? progress);

/// Downloads [url] to the platform's standard location under [filename].
///
/// [filename] is sanitized before use, so it is safe to pass an attachment name
/// straight off the wire. [onProgress] fires as bytes arrive where the platform
/// can observe them (never on web).
///
/// Never throws for an expected failure — inspect [DownloadResult.outcome].
Future<DownloadResult> downloadAttachment(
  String url, {
  required String filename,
  DownloadProgressCallback? onProgress,
}) =>
    impl.downloadAttachment(url, filename: filename, onProgress: onProgress);

/// Whether this platform can show a saved file in its file manager.
bool get canRevealDownloads => impl.canRevealDownloads;

/// Opens the folder containing [path] in the OS file manager (desktop only).
///
/// Returns false if the platform can't do it or the attempt failed.
Future<bool> revealDownloadedFile(String path) =>
    impl.revealDownloadedFile(path);

/// Windows refuses these as filenames whatever the extension.
const _windowsReservedNames = {
  'con', 'prn', 'aux', 'nul', //
  'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
  'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
};

/// Longest name we will write. Comfortably inside the 255-byte limit that ext4,
/// APFS and NTFS all share, with room for a ` (12)` collision suffix.
const _maxFilenameLength = 120;

/// Reduces an attacker-controlled attachment name to a single, harmless path
/// segment.
///
/// Guarantees about the result: it is non-empty, contains no path separator of
/// either flavour, no control characters, and no character Windows rejects; it
/// is never `.` or `..`; it is never a Windows reserved device name; and it is
/// at most [_maxFilenameLength] characters. Joining it onto a directory can
/// therefore only ever name a direct child of that directory.
///
/// Traversal is stripped rather than escaped — `../../etc/passwd` becomes
/// `passwd`, not a literal `..` — because the segments before the last one
/// carry no information the user wants in their Downloads folder.
String sanitizeAttachmentFilename(String raw, {String fallback = 'download'}) {
  // Drop control characters (including NUL, which truncates paths in some
  // native APIs) before anything else looks at the string.
  var name = raw.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '');

  // Keep only the last segment: this discards every directory component and,
  // with it, every interior `..`. Both separators are honoured so a Windows
  // path can't survive on POSIX or vice versa.
  final segments = name.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty);
  name = segments.isEmpty ? '' : segments.last;

  // A trailing `..` or `.` has no last segment to fall back to.
  if (name == '.' || name == '..') name = '';

  // Characters NTFS rejects, plus `:` which is an alternate-data-stream marker
  // on Windows and a separator on classic macOS.
  name = name.replaceAll(RegExp(r'[<>:"|?*]'), '_');

  // Windows silently drops trailing dots and spaces, which would let
  // `evil.exe.` and `evil.exe` collide; normalise them away ourselves.
  name = name.replaceAll(RegExp(r'[ .]+$'), '').trim();

  if (name.isEmpty) return fallback;

  final stem = p.basenameWithoutExtension(name);
  if (_windowsReservedNames.contains(stem.toLowerCase())) name = '_$name';

  if (name.length > _maxFilenameLength) {
    // Truncate the stem, not the extension: the extension is what tells the OS
    // (and the user) what the file is.
    final ext = p.extension(name);
    final keep = _maxFilenameLength - ext.length;
    name = keep > 0
        ? '${name.substring(0, keep)}$ext'
        : name.substring(0, _maxFilenameLength);
  }

  return name.isEmpty ? fallback : name;
}

/// Picks a name in [directory] that no existing file uses, by appending
/// ` (1)`, ` (2)`, … to the stem: `track.mp3` → `track (1).mp3`.
///
/// [exists] is injected so the pure-Dart naming rule stays testable without a
/// filesystem; the native implementation passes `File(path).existsSync`.
/// Returns the full path.
///
/// Note this is advisory only — it narrows the window but can't close it, so
/// the actual write must still create the file exclusively.
String uniqueDownloadPath(
  String directory,
  String filename,
  bool Function(String path) exists, {
  int maxAttempts = 1000,
}) {
  final first = p.join(directory, filename);
  if (!exists(first)) return first;

  final stem = p.basenameWithoutExtension(filename);
  final ext = p.extension(filename);
  for (var n = 1; n <= maxAttempts; n++) {
    final candidate = p.join(directory, '$stem ($n)$ext');
    if (!exists(candidate)) return candidate;
  }
  // Pathological case (a thousand copies already sitting there): fall back to
  // something that is almost certainly free rather than overwriting.
  return p.join(
    directory,
    '$stem (${DateTime.now().millisecondsSinceEpoch})$ext',
  );
}
