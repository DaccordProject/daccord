import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// How this client can render an attachment inline in the message list.
///
/// [none] is not a failure — it means "show a download chip", which is the
/// correct outcome for a `.zip`, a `.pdf`, or anything we don't recognise.
enum AttachmentPreview {
  /// Rendered by `CachedNetworkImage` (Flutter's own decoders).
  image,

  /// Rendered by `InlineVideoPlayer` (media_kit / libmpv; AVFoundation on iOS).
  video,

  /// Rendered by `InlineAudioPlayer` (audioplayers).
  audio,

  /// Offered as a filename chip to download.
  none,
}

/// One row of the attachment type table: the MIME type an extension maps to,
/// and whether this client can actually render that type inline.
///
/// The distinction matters: `image/svg+xml` and `image/tiff` are unambiguously
/// images, but Flutter's image decoders render neither, so previewing them
/// produces a broken-image box. They live here as `preview: none`.
class AttachmentType {
  const AttachmentType(this.mimeType, this.preview);

  final String mimeType;
  final AttachmentPreview preview;
}

const _image = AttachmentPreview.image;
const _video = AttachmentPreview.video;
const _audio = AttachmentPreview.audio;
const _none = AttachmentPreview.none;

/// **The** extension → MIME → preview-capability table for attachments.
///
/// Everything derives from this map — the MIME sent on upload, the inline
/// preview chosen on render, and the icon shown on the composer chip — so the
/// three cannot disagree.
///
/// Keys are lowercase, dot-less extensions. The Accord server does **not**
/// enforce a type allow-list on message attachments (only size and count, see
/// `AccordServerLimits`), so a missing entry is not an error: it means "upload
/// it as best we can type it, and don't try to preview it".
const Map<String, AttachmentType> kAttachmentTypes = {
  // ---- Images the client can render inline -------------------------------
  'png': AttachmentType('image/png', _image),
  'jpg': AttachmentType('image/jpeg', _image),
  'jpeg': AttachmentType('image/jpeg', _image),
  'jfif': AttachmentType('image/jpeg', _image),
  'gif': AttachmentType('image/gif', _image),
  'webp': AttachmentType('image/webp', _image),
  'bmp': AttachmentType('image/bmp', _image),
  'wbmp': AttachmentType('image/vnd.wap.wbmp', _image),
  // ---- Images the client can NOT render inline ---------------------------
  // Correct MIME so other clients and the CDN behave, but no inline preview:
  // Flutter has no decoder for these (SVG needs flutter_svg; TIFF/AVIF/HEIF
  // are platform-dependent at best), and attempting one shows a broken image.
  'svg': AttachmentType('image/svg+xml', _none),
  'tif': AttachmentType('image/tiff', _none),
  'tiff': AttachmentType('image/tiff', _none),
  'avif': AttachmentType('image/avif', _none),
  'heic': AttachmentType('image/heic', _none),
  'heif': AttachmentType('image/heif', _none),
  'ico': AttachmentType('image/x-icon', _none),
  'psd': AttachmentType('image/vnd.adobe.photoshop', _none),
  // ---- Video (media_kit / libmpv handles all of these; iOS plays the
  // AVFoundation-supported subset — see InlineVideoPlayer) ------------------
  'mp4': AttachmentType('video/mp4', _video),
  'm4v': AttachmentType('video/mp4', _video),
  'webm': AttachmentType('video/webm', _video),
  'mkv': AttachmentType('video/x-matroska', _video),
  'mov': AttachmentType('video/quicktime', _video),
  'avi': AttachmentType('video/x-msvideo', _video),
  'wmv': AttachmentType('video/x-ms-wmv', _video),
  'flv': AttachmentType('video/x-flv', _video),
  'mpg': AttachmentType('video/mpeg', _video),
  'mpeg': AttachmentType('video/mpeg', _video),
  'ogv': AttachmentType('video/ogg', _video),
  '3gp': AttachmentType('video/3gpp', _video),
  'ts': AttachmentType('video/mp2t', _video),
  // ---- Audio -------------------------------------------------------------
  'mp3': AttachmentType('audio/mpeg', _audio),
  'wav': AttachmentType('audio/wav', _audio),
  'ogg': AttachmentType('audio/ogg', _audio),
  'oga': AttachmentType('audio/ogg', _audio),
  'opus': AttachmentType('audio/opus', _audio),
  'm4a': AttachmentType('audio/mp4', _audio),
  'aac': AttachmentType('audio/aac', _audio),
  'flac': AttachmentType('audio/flac', _audio),
  'aiff': AttachmentType('audio/aiff', _audio),
  'weba': AttachmentType('audio/webm', _audio),
  // Audio the player can't be relied on for — typed, but not previewed.
  'wma': AttachmentType('audio/x-ms-wma', _none),
  'mid': AttachmentType('audio/midi', _none),
  'midi': AttachmentType('audio/midi', _none),
  'amr': AttachmentType('audio/amr', _none),
  // ---- Documents ---------------------------------------------------------
  'pdf': AttachmentType('application/pdf', _none),
  'txt': AttachmentType('text/plain', _none),
  'log': AttachmentType('text/plain', _none),
  'md': AttachmentType('text/markdown', _none),
  'csv': AttachmentType('text/csv', _none),
  'rtf': AttachmentType('application/rtf', _none),
  'epub': AttachmentType('application/epub+zip', _none),
  'doc': AttachmentType('application/msword', _none),
  'docx': AttachmentType(
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _none,
  ),
  'xls': AttachmentType('application/vnd.ms-excel', _none),
  'xlsx': AttachmentType(
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _none,
  ),
  'ppt': AttachmentType('application/vnd.ms-powerpoint', _none),
  'pptx': AttachmentType(
    'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    _none,
  ),
  'odt': AttachmentType('application/vnd.oasis.opendocument.text', _none),
  'ods': AttachmentType(
      'application/vnd.oasis.opendocument.spreadsheet', _none),
  'odp': AttachmentType(
      'application/vnd.oasis.opendocument.presentation', _none),
  // ---- Archives ----------------------------------------------------------
  'zip': AttachmentType('application/zip', _none),
  'rar': AttachmentType('application/vnd.rar', _none),
  '7z': AttachmentType('application/x-7z-compressed', _none),
  'tar': AttachmentType('application/x-tar', _none),
  'gz': AttachmentType('application/gzip', _none),
  'tgz': AttachmentType('application/gzip', _none),
  'bz2': AttachmentType('application/x-bzip2', _none),
  'xz': AttachmentType('application/x-xz', _none),
  'zst': AttachmentType('application/zstd', _none),
  // ---- Code / config / data ---------------------------------------------
  'json': AttachmentType('application/json', _none),
  'xml': AttachmentType('application/xml', _none),
  'yaml': AttachmentType('application/yaml', _none),
  'yml': AttachmentType('application/yaml', _none),
  'toml': AttachmentType('application/toml', _none),
  'ini': AttachmentType('text/plain', _none),
  'conf': AttachmentType('text/plain', _none),
  'html': AttachmentType('text/html', _none),
  'htm': AttachmentType('text/html', _none),
  'css': AttachmentType('text/css', _none),
  'js': AttachmentType('text/javascript', _none),
  'sql': AttachmentType('application/sql', _none),
  'sh': AttachmentType('application/x-sh', _none),
  'py': AttachmentType('text/x-python', _none),
  'dart': AttachmentType('text/x-dart', _none),
  'rs': AttachmentType('text/x-rust', _none),
  'go': AttachmentType('text/x-go', _none),
  'c': AttachmentType('text/x-c', _none),
  'h': AttachmentType('text/x-c', _none),
  'cpp': AttachmentType('text/x-c++', _none),
  'java': AttachmentType('text/x-java', _none),
  'gd': AttachmentType('text/plain', _none),
  // ---- Binaries / packages ----------------------------------------------
  'apk': AttachmentType('application/vnd.android.package-archive', _none),
  'exe': AttachmentType('application/vnd.microsoft.portable-executable', _none),
  'msi': AttachmentType('application/x-msi', _none),
  'dmg': AttachmentType('application/x-apple-diskimage', _none),
  'deb': AttachmentType('application/vnd.debian.binary-package', _none),
  'rpm': AttachmentType('application/x-rpm', _none),
  'iso': AttachmentType('application/x-iso9660-image', _none),
  'ttf': AttachmentType('font/ttf', _none),
  'otf': AttachmentType('font/otf', _none),
  'woff': AttachmentType('font/woff', _none),
  'woff2': AttachmentType('font/woff2', _none),
  'torrent': AttachmentType('application/x-bittorrent', _none),
};

/// The type every unrecognised, unsniffable file falls back to.
const String kFallbackMimeType = 'application/octet-stream';

/// MIME → preview, derived from [kAttachmentTypes] so it can never drift from
/// it. Built once, lazily.
final Map<String, AttachmentPreview> _previewByMime = {
  for (final type in kAttachmentTypes.values) type.mimeType: type.preview,
};

/// MIME → canonical extension, derived from [kAttachmentTypes]. The first
/// extension listed for a MIME wins, which is why `jpg` precedes `jpeg` and
/// `mp4` precedes `m4v` in the table above.
final Map<String, String> _extensionByMime = _buildExtensionByMime();

Map<String, String> _buildExtensionByMime() {
  final out = <String, String>{};
  for (final entry in kAttachmentTypes.entries) {
    out.putIfAbsent(entry.value.mimeType, () => entry.key);
  }
  return out;
}

/// The lowercase extension of [filename] without its dot, or null when there
/// isn't one.
///
/// Deliberately takes the **last** dot segment, so `archive.tar.gz` is a gzip
/// and `photo.png.txt` is text — the outermost wrapper is what the file
/// actually is. A dotfile (`.gitignore`), a trailing dot (`report.`) and a bare
/// name (`Makefile`) all return null rather than inventing an extension.
String? attachmentExtension(String filename) {
  final name = filename.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return null;
  final ext = name.substring(dot + 1).toLowerCase();
  // Guard against "file.tar .gz"-style junk and absurd suffixes.
  if (ext.isEmpty || ext.length > 12 || ext.contains(' ')) return null;
  return ext;
}

/// The table row for [filename]'s extension, or null when unrecognised.
AttachmentType? attachmentTypeFor(String filename) {
  final ext = attachmentExtension(filename);
  if (ext == null) return null;
  return kAttachmentTypes[ext];
}

/// The canonical extension (no dot) for [mimeType], or null when unknown.
String? extensionForMimeType(String mimeType) =>
    _extensionByMime[mimeType.toLowerCase().split(';').first.trim()];

/// Identifies [bytes] by its magic number, or returns null when the leading
/// bytes match no known signature.
///
/// This is the authoritative answer where it fires: content beats both the
/// filename and whatever the OS guessed, which is what makes a `.txt`-suffixed
/// PNG upload as `image/png`.
String? sniffMimeType(List<int>? bytes) {
  if (bytes == null || bytes.length < 4) return null;
  bool at(int offset, List<int> signature) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  bool ascii(int offset, String text) =>
      at(offset, text.codeUnits);

  // Images.
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (ascii(0, 'GIF87a') || ascii(0, 'GIF89a')) return 'image/gif';
  // "BM" alone is two bytes and would claim any text starting "BMW…", so the
  // header's own little-endian file-size field has to agree with the buffer.
  if (ascii(0, 'BM') && bytes.length >= 6) {
    final declared = bytes[2] |
        (bytes[3] << 8) |
        (bytes[4] << 16) |
        (bytes[5] << 24);
    if (declared == bytes.length) return 'image/bmp';
  }
  if (at(0, const [0x49, 0x49, 0x2A, 0x00]) ||
      at(0, const [0x4D, 0x4D, 0x00, 0x2A])) {
    return 'image/tiff';
  }
  if (at(0, const [0x00, 0x00, 0x01, 0x00])) return 'image/x-icon';
  if (ascii(0, '8BPS')) return 'image/vnd.adobe.photoshop';

  // RIFF containers: WEBP / WAVE / AVI share a header.
  if (ascii(0, 'RIFF')) {
    if (ascii(8, 'WEBP')) return 'image/webp';
    if (ascii(8, 'WAVE')) return 'audio/wav';
    if (ascii(8, 'AVI ')) return 'video/x-msvideo';
  }

  // ISO base media (MP4 / M4A / MOV / 3GP / HEIC): "ftyp" at offset 4.
  if (ascii(4, 'ftyp')) {
    final brand = String.fromCharCodes(
      bytes.sublist(8, bytes.length < 12 ? bytes.length : 12),
    ).toLowerCase();
    if (brand.startsWith('m4a')) return 'audio/mp4';
    if (brand.startsWith('qt')) return 'video/quicktime';
    if (brand.startsWith('3g')) return 'video/3gpp';
    if (brand.startsWith('heic') || brand.startsWith('heix')) return 'image/heic';
    if (brand.startsWith('mif1') || brand.startsWith('msf1')) return 'image/heif';
    if (brand.startsWith('avif')) return 'image/avif';
    return 'video/mp4';
  }

  // Matroska / WebM share an EBML header; the DocType string separates them.
  if (at(0, const [0x1A, 0x45, 0xDF, 0xA3])) {
    final head = String.fromCharCodes(
      bytes.sublist(0, bytes.length < 64 ? bytes.length : 64),
    );
    return head.contains('webm') ? 'video/webm' : 'video/x-matroska';
  }

  // Audio.
  if (ascii(0, 'ID3')) return 'audio/mpeg';
  // MPEG audio frame sync: 11 set bits, and not a valid-looking MPEG-1 video
  // start code (those begin 00 00 01).
  if (bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0) return 'audio/mpeg';
  if (ascii(0, 'fLaC')) return 'audio/flac';
  if (ascii(0, 'OggS')) return 'audio/ogg';
  if (ascii(0, 'FORM') && ascii(8, 'AIFF')) return 'audio/aiff';

  // Documents and archives.
  if (ascii(0, '%PDF-')) return 'application/pdf';
  if (at(0, const [0x50, 0x4B, 0x03, 0x04]) ||
      at(0, const [0x50, 0x4B, 0x05, 0x06])) {
    // Could be any OOXML/ODF/epub/apk; those are better identified by their
    // extension, so only claim plain zip when there's nothing better.
    return 'application/zip';
  }
  if (at(0, const [0x1F, 0x8B])) return 'application/gzip';
  if (at(0, const [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C])) {
    return 'application/x-7z-compressed';
  }
  if (ascii(0, 'Rar!')) return 'application/vnd.rar';
  if (ascii(0, 'BZh')) return 'application/x-bzip2';
  if (at(0, const [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
    return 'application/x-xz';
  }
  if (at(0, const [0x28, 0xB5, 0x2F, 0xFD])) return 'application/zstd';
  return null;
}

/// A MIME type the platform handed us that is too vague to be worth keeping.
bool _isUselessMime(String? mime) {
  if (mime == null) return true;
  final value = mime.trim().toLowerCase();
  return value.isEmpty ||
      value == kFallbackMimeType ||
      value == 'application/unknown' ||
      value == 'binary/octet-stream' ||
      !value.contains('/');
}

/// Resolves the MIME type to upload [filename] with.
///
/// Resolution order, most trustworthy first:
///
/// 1. **Magic bytes** — the file's own content. Wins outright, so a PNG named
///    `notes.txt` still uploads as `image/png`.
/// 2. **The platform's own MIME** — drag-and-drop hands us `XFile.mimeType`,
///    which on Linux/web comes from the OS/browser rather than a guess of ours.
/// 3. **The extension table** ([kAttachmentTypes]).
/// 4. [kFallbackMimeType].
///
/// Case is irrelevant throughout: `PHOTO.JPG` resolves exactly like `photo.jpg`.
String resolveAttachmentMimeType(
  String filename, {
  List<int>? bytes,
  String? platformMimeType,
}) {
  final sniffed = sniffMimeType(bytes);
  final byExtension = attachmentTypeFor(filename)?.mimeType;
  if (sniffed != null) {
    // A generic zip signature is weaker than a specific extension (.docx,
    // .apk and .epub are all zips), so let the table refine that one case.
    if (sniffed != 'application/zip') return sniffed;
    return byExtension ?? sniffed;
  }
  if (!_isUselessMime(platformMimeType)) {
    return platformMimeType!.trim().toLowerCase();
  }
  return byExtension ?? kFallbackMimeType;
}

/// Image MIME types that are real images but that this client has no decoder
/// for. Kept explicit so the `image/*` catch-all below stays forward-compatible
/// without re-introducing the broken-image box for these.
const Set<String> _unrenderableImageMimes = {
  'image/svg+xml',
  'image/tiff',
  'image/avif',
  'image/heic',
  'image/heif',
  'image/x-icon',
  'image/vnd.adobe.photoshop',
};

/// How to render an attachment inline, given whatever the server told us.
///
/// [contentType] leads because it survives the filename being sanitised or
/// mismatched; the extension table is the fallback when the server stored no
/// content type (or an uninformative one). An unknown `image/…`, `video/…` or
/// `audio/…` still previews, so a type added server-side later doesn't need a
/// client release — bar the ones we know we can't decode.
AttachmentPreview attachmentPreviewFor({
  String? contentType,
  String filename = '',
}) {
  if (!_isUselessMime(contentType)) {
    final mime = contentType!.trim().toLowerCase().split(';').first.trim();
    final known = _previewByMime[mime];
    if (known != null) return known;
    if (mime.startsWith('image/')) {
      return _unrenderableImageMimes.contains(mime)
          ? AttachmentPreview.none
          : AttachmentPreview.image;
    }
    if (mime.startsWith('video/')) return AttachmentPreview.video;
    if (mime.startsWith('audio/')) return AttachmentPreview.audio;
  }
  return attachmentTypeFor(filename)?.preview ?? AttachmentPreview.none;
}

/// A file the user has attached but not yet sent.
///
/// Wraps [PlatformFile] purely to carry the two things it can't: the MIME type
/// the platform reported (drag-and-drop only) and the resolved content type,
/// computed once via [resolveAttachmentMimeType] rather than re-guessed at send
/// time from the extension alone.
class PendingAttachment {
  PendingAttachment(this.file, {this.platformMimeType});

  /// Builds one from raw bytes (clipboard paste, large-text capture).
  factory PendingAttachment.fromBytes({
    required String name,
    required Uint8List bytes,
    String? path,
    String? platformMimeType,
  }) =>
      PendingAttachment(
        PlatformFile(
          name: name,
          size: bytes.length,
          bytes: bytes,
          path: path,
        ),
        platformMimeType: platformMimeType,
      );

  final PlatformFile file;

  /// What the OS/browser said this is, when it said anything (`XFile.mimeType`).
  final String? platformMimeType;

  String get name => file.name;
  Uint8List? get bytes => file.bytes;
  int get size => file.bytes?.length ?? file.size;

  /// The MIME type this file uploads as. Computed once — sniffing runs over
  /// the leading bytes, and the chip, the send payload and any preview all read
  /// the same answer.
  late final String contentType = resolveAttachmentMimeType(
    name,
    bytes: bytes,
    platformMimeType: platformMimeType,
  );

  /// Whether this file would preview inline once sent. Used to give the chip a
  /// meaningful icon instead of letting an unrecognised type look identical to
  /// a recognised one.
  AttachmentPreview get preview =>
      attachmentPreviewFor(contentType: contentType, filename: name);

  /// True when neither the content, the platform nor the extension identified
  /// the file, i.e. it uploads as [kFallbackMimeType]. Surfaced on the chip so
  /// the fallback isn't silent, per the file-type audit.
  bool get isUnrecognised => contentType == kFallbackMimeType;

  /// The multipart part for `messages.createWithAttachments`.
  Map<String, dynamic> toUploadPart() => {
        'filename': name,
        'content': bytes!,
        'content_type': contentType,
      };
}

/// Names a pasted image after sniffing it, instead of assuming PNG.
///
/// `Pasteboard.image` returns PNG on most platforms but not all — macOS in
/// particular hands back whatever the source app put on the pasteboard — and a
/// JPEG called `.png` is a mislabelled file on every client that receives it.
String pastedImageFilename(List<int> bytes, {DateTime? now}) {
  final mime = sniffMimeType(bytes);
  final extension =
      mime == null ? 'png' : (extensionForMimeType(mime) ?? 'png');
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  return 'pasted-$stamp.$extension';
}
