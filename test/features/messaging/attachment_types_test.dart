import 'dart:typed_data';

import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _bytes(List<int> head, {int pad = 0}) =>
    Uint8List.fromList([...head, ...List.filled(pad, 0)]);

/// A minimal but real PNG header.
final _png = _bytes(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
    pad: 8);
final _jpeg = _bytes(const [0xFF, 0xD8, 0xFF, 0xE0], pad: 12);
final _gif = _bytes('GIF89a'.codeUnits, pad: 10);
final _pdf = _bytes('%PDF-1.7'.codeUnits, pad: 8);
final _id3Mp3 = _bytes('ID3'.codeUnits, pad: 13);
final _rawMp3 = _bytes(const [0xFF, 0xFB, 0x90, 0x44], pad: 12);
final _ogg = _bytes('OggS'.codeUnits, pad: 12);
final _flac = _bytes('fLaC'.codeUnits, pad: 12);
final _wav = _bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WAVE'.codeUnits]);
final _webp = _bytes([...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits]);
final _mp4 = _bytes([0, 0, 0, 0x18, ...'ftypisom'.codeUnits], pad: 8);
final _m4a = _bytes([0, 0, 0, 0x18, ...'ftypM4A '.codeUnits], pad: 8);
final _mov = _bytes([0, 0, 0, 0x18, ...'ftypqt  '.codeUnits], pad: 8);
final _webm = _bytes([
  0x1A, 0x45, 0xDF, 0xA3,
  ...List.filled(20, 0x00),
  ...'webm'.codeUnits,
  ...List.filled(20, 0x00),
]);
final _mkv = _bytes([0x1A, 0x45, 0xDF, 0xA3, ...List.filled(40, 0x00)]);
final _zip = _bytes(const [0x50, 0x4B, 0x03, 0x04], pad: 12);
final _gzip = _bytes(const [0x1F, 0x8B, 0x08, 0x00], pad: 12);

void main() {
  group('kAttachmentTypes is the single source of truth', () {
    test('every entry has a plausible MIME type and a lowercase key', () {
      for (final entry in kAttachmentTypes.entries) {
        expect(entry.key, entry.key.toLowerCase(),
            reason: '${entry.key} must be lowercase');
        expect(entry.key, isNot(startsWith('.')),
            reason: '${entry.key} must not include the dot');
        expect(entry.value.mimeType, contains('/'),
            reason: '${entry.key} has a malformed MIME type');
        expect(entry.value.mimeType, entry.value.mimeType.toLowerCase());
      }
    });

    test('never maps anything to the octet-stream fallback', () {
      for (final entry in kAttachmentTypes.entries) {
        expect(entry.value.mimeType, isNot(kFallbackMimeType),
            reason: '${entry.key} should be removed rather than mapped to the '
                'fallback');
      }
    });

    test('a MIME type always means the same preview capability', () {
      final seen = <String, AttachmentPreview>{};
      for (final entry in kAttachmentTypes.entries) {
        final existing = seen[entry.value.mimeType];
        if (existing != null) {
          expect(entry.value.preview, existing,
              reason: '${entry.value.mimeType} previews inconsistently');
        }
        seen[entry.value.mimeType] = entry.value.preview;
      }
    });

    test('covers everything the old _mimeType() switch did', () {
      const legacy = {
        'png': 'image/png',
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'svg': 'image/svg+xml',
        'mp4': 'video/mp4',
        'webm': 'video/webm',
        'mp3': 'audio/mpeg',
        'ogg': 'audio/ogg',
        'wav': 'audio/wav',
        'pdf': 'application/pdf',
        'txt': 'text/plain',
        'json': 'application/json',
        'zip': 'application/zip',
      };
      legacy.forEach((extension, mime) {
        expect(kAttachmentTypes[extension]?.mimeType, mime,
            reason: '$extension regressed');
      });
    });

    test('covers everything the old preview lists claimed, and types it', () {
      // These previewed inline but had no MIME mapping, so they uploaded as
      // application/octet-stream — exactly the drift the audit is about.
      const previouslyUntyped = {
        'mov': AttachmentPreview.video,
        'mkv': AttachmentPreview.video,
        'm4a': AttachmentPreview.audio,
        'flac': AttachmentPreview.audio,
      };
      previouslyUntyped.forEach((extension, preview) {
        final type = kAttachmentTypes[extension];
        expect(type, isNotNull, reason: '$extension is missing');
        expect(type!.mimeType, isNot(kFallbackMimeType));
        expect(type.preview, preview);
      });
    });

    test('does not claim to preview formats it cannot decode', () {
      for (final extension in ['svg', 'tif', 'tiff', 'avif', 'heic', 'ico']) {
        expect(kAttachmentTypes[extension]!.preview, AttachmentPreview.none,
            reason: '$extension has no Flutter decoder');
      }
    });
  });

  group('attachmentExtension', () {
    test('lowercases an UPPERCASE extension', () {
      expect(attachmentExtension('HOLIDAY.JPG'), 'jpg');
      expect(attachmentExtension('Mixed.PnG'), 'png');
    });

    test('takes the last segment of a double extension', () {
      expect(attachmentExtension('archive.tar.gz'), 'gz');
      expect(attachmentExtension('notes.png.txt'), 'txt');
    });

    test('returns null for an extensionless file', () {
      expect(attachmentExtension('Makefile'), isNull);
      expect(attachmentExtension('README'), isNull);
    });

    test('treats a dotfile as extensionless', () {
      expect(attachmentExtension('.gitignore'), isNull);
      expect(attachmentExtension('.env'), isNull);
    });

    test('returns null for a trailing dot', () {
      expect(attachmentExtension('report.'), isNull);
    });

    test('ignores directories in the path', () {
      expect(attachmentExtension('/home/a.b/song.mp3'), 'mp3');
      expect(attachmentExtension(r'C:\Users\me.dir\song.MP3'), 'mp3');
      expect(attachmentExtension('/home/a.b/Makefile'), isNull);
    });
  });

  group('sniffMimeType', () {
    test('identifies images', () {
      expect(sniffMimeType(_png), 'image/png');
      expect(sniffMimeType(_jpeg), 'image/jpeg');
      expect(sniffMimeType(_gif), 'image/gif');
      expect(sniffMimeType(_webp), 'image/webp');
    });

    test('identifies audio, including both MP3 forms', () {
      expect(sniffMimeType(_id3Mp3), 'audio/mpeg');
      expect(sniffMimeType(_rawMp3), 'audio/mpeg');
      expect(sniffMimeType(_ogg), 'audio/ogg');
      expect(sniffMimeType(_flac), 'audio/flac');
      expect(sniffMimeType(_wav), 'audio/wav');
    });

    test('separates the ISO base media brands', () {
      expect(sniffMimeType(_mp4), 'video/mp4');
      expect(sniffMimeType(_m4a), 'audio/mp4');
      expect(sniffMimeType(_mov), 'video/quicktime');
    });

    test('separates WebM from Matroska by DocType', () {
      expect(sniffMimeType(_webm), 'video/webm');
      expect(sniffMimeType(_mkv), 'video/x-matroska');
    });

    test('identifies documents and archives', () {
      expect(sniffMimeType(_pdf), 'application/pdf');
      expect(sniffMimeType(_zip), 'application/zip');
      expect(sniffMimeType(_gzip), 'application/gzip');
    });

    test('returns null for text and for too-short input', () {
      expect(sniffMimeType('hello world'.codeUnits), isNull);
      expect(sniffMimeType(Uint8List.fromList([1, 2])), isNull);
      expect(sniffMimeType(null), isNull);
    });

    test('does not mistake text beginning "BM" for a bitmap', () {
      // The BMP signature is only two bytes, so the header's declared file
      // size has to agree with the buffer before it counts.
      expect(sniffMimeType('BMW parts list, 2026'.codeUnits), isNull);
      final bmp = Uint8List.fromList([
        ...'BM'.codeUnits,
        10, 0, 0, 0, // declared size == 10 bytes
        0, 0, 0, 0,
      ]);
      expect(sniffMimeType(bmp), 'image/bmp');
    });
  });

  group('resolveAttachmentMimeType', () {
    test('uses the extension table when there are no bytes', () {
      expect(resolveAttachmentMimeType('song.mp3'), 'audio/mpeg');
      expect(resolveAttachmentMimeType('doc.pdf'), 'application/pdf');
    });

    test('is case-insensitive', () {
      expect(resolveAttachmentMimeType('SONG.MP3'), 'audio/mpeg');
      expect(resolveAttachmentMimeType('Holiday.JPEG'), 'image/jpeg');
    });

    test('resolves a double extension by its last segment', () {
      expect(resolveAttachmentMimeType('logs.tar.gz'), 'application/gzip');
    });

    test('falls back to octet-stream for an extensionless unknown file', () {
      expect(resolveAttachmentMimeType('Makefile'), kFallbackMimeType);
      expect(resolveAttachmentMimeType('mystery.qqq'), kFallbackMimeType);
    });

    test('identifies an extensionless file by its content', () {
      expect(resolveAttachmentMimeType('recording', bytes: _id3Mp3),
          'audio/mpeg');
      expect(resolveAttachmentMimeType('screenshot', bytes: _png), 'image/png');
    });

    test('content beats a mismatched extension', () {
      // The audit's "mismatched extension vs. content" case: a PNG saved as
      // .txt uploads as an image, not as text.
      expect(resolveAttachmentMimeType('notes.txt', bytes: _png), 'image/png');
      expect(resolveAttachmentMimeType('song.png', bytes: _id3Mp3),
          'audio/mpeg');
    });

    test('content beats a platform MIME type', () {
      expect(
        resolveAttachmentMimeType('a.bin',
            bytes: _png, platformMimeType: 'application/x-thing'),
        'image/png',
      );
    });

    test('a specific extension refines a generic zip signature', () {
      // .docx/.apk/.epub are all zips on the wire; the extension is the more
      // useful answer there.
      expect(
        resolveAttachmentMimeType('app.apk', bytes: _zip),
        'application/vnd.android.package-archive',
      );
      expect(resolveAttachmentMimeType('bundle.zip', bytes: _zip),
          'application/zip');
      expect(resolveAttachmentMimeType('mystery', bytes: _zip),
          'application/zip');
    });

    test('the platform MIME beats the extension when bytes say nothing', () {
      expect(
        resolveAttachmentMimeType('data.qqq',
            platformMimeType: 'application/x-custom'),
        'application/x-custom',
      );
    });

    test('ignores a useless platform MIME type', () {
      for (final useless in [
        'application/octet-stream',
        'binary/octet-stream',
        '',
        '   ',
        'nonsense',
      ]) {
        expect(
          resolveAttachmentMimeType('song.mp3', platformMimeType: useless),
          'audio/mpeg',
          reason: '"$useless" should not win over the table',
        );
      }
    });

    test('normalises the platform MIME case', () {
      expect(
        resolveAttachmentMimeType('x.qqq', platformMimeType: 'Audio/MPEG'),
        'audio/mpeg',
      );
    });
  });

  group('attachmentPreviewFor', () {
    test('uses the content type when it is known', () {
      expect(attachmentPreviewFor(contentType: 'image/png'),
          AttachmentPreview.image);
      expect(attachmentPreviewFor(contentType: 'audio/mpeg'),
          AttachmentPreview.audio);
      expect(attachmentPreviewFor(contentType: 'video/mp4'),
          AttachmentPreview.video);
      expect(attachmentPreviewFor(contentType: 'application/pdf'),
          AttachmentPreview.none);
    });

    test('tolerates parameters and casing on the content type', () {
      expect(
        attachmentPreviewFor(contentType: 'IMAGE/PNG; charset=binary'),
        AttachmentPreview.image,
      );
    });

    test('previews an unknown image/video/audio subtype', () {
      expect(attachmentPreviewFor(contentType: 'image/x-future'),
          AttachmentPreview.image);
      expect(attachmentPreviewFor(contentType: 'video/x-future'),
          AttachmentPreview.video);
      expect(attachmentPreviewFor(contentType: 'audio/x-future'),
          AttachmentPreview.audio);
    });

    test('does not preview image types Flutter cannot decode', () {
      for (final mime in ['image/svg+xml', 'image/tiff', 'image/heic']) {
        expect(attachmentPreviewFor(contentType: mime), AttachmentPreview.none,
            reason: mime);
      }
    });

    test('falls back to the filename when the content type is missing', () {
      expect(
        attachmentPreviewFor(contentType: null, filename: 'clip.MP4'),
        AttachmentPreview.video,
      );
      expect(
        attachmentPreviewFor(
            contentType: 'application/octet-stream', filename: 'song.mp3'),
        AttachmentPreview.audio,
      );
    });

    test('is none for an extensionless, untyped attachment', () {
      expect(attachmentPreviewFor(contentType: null, filename: 'blob'),
          AttachmentPreview.none);
      expect(attachmentPreviewFor(), AttachmentPreview.none);
    });
  });

  group('PendingAttachment', () {
    test('resolves and caches its content type', () {
      final file = PendingAttachment.fromBytes(name: 'a.txt', bytes: _png);
      expect(file.contentType, 'image/png');
      expect(file.preview, AttachmentPreview.image);
      expect(file.isUnrecognised, isFalse);
      expect(file.size, _png.length);
    });

    test('flags an unrecognisable file rather than hiding it', () {
      final file = PendingAttachment.fromBytes(
        name: 'mystery',
        bytes: Uint8List.fromList(const [0x11, 0x22, 0x33, 0x44]),
      );
      expect(file.contentType, kFallbackMimeType);
      expect(file.isUnrecognised, isTrue);
      expect(file.preview, AttachmentPreview.none);
    });

    test('builds an upload part carrying the resolved type', () {
      final file = PendingAttachment.fromBytes(name: 'song.mp3', bytes: _rawMp3);
      expect(file.toUploadPart(), {
        'filename': 'song.mp3',
        'content': _rawMp3,
        'content_type': 'audio/mpeg',
      });
    });
  });

  group('pastedImageFilename', () {
    final at = DateTime.fromMillisecondsSinceEpoch(1700000000000);

    test('names a pasted PNG .png', () {
      expect(pastedImageFilename(_png, now: at), 'pasted-1700000000000.png');
    });

    test('names a pasted JPEG .jpg rather than assuming PNG', () {
      expect(pastedImageFilename(_jpeg, now: at), 'pasted-1700000000000.jpg');
    });

    test('falls back to .png for unrecognisable clipboard bytes', () {
      expect(
        pastedImageFilename(Uint8List.fromList(const [1, 2, 3, 4]), now: at),
        'pasted-1700000000000.png',
      );
    });
  });
}
