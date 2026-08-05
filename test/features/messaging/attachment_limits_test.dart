import 'dart:typed_data';

import 'package:bonfire/features/messaging/utils/attachment_limits.dart';
import 'package:bonfire/features/messaging/utils/attachment_types.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

PendingAttachment _file(String name, {int? bytes}) => PendingAttachment(
  PlatformFile(
    name: name,
    size: bytes ?? 0,
    bytes: bytes == null ? null : Uint8List(bytes),
  ),
);

void main() {
  group('formatFileSize', () {
    test('scales to KB and MB', () {
      expect(formatFileSize(512), '512 bytes');
      expect(formatFileSize(2048), '2 KB');
      expect(formatFileSize(3 * 1024 * 1024), '3.0 MB');
    });

    test('drops the decimal at 10 MB and above', () {
      expect(formatFileSize(41 * 1024 * 1024), '41 MB');
    });
  });

  group('screenAttachments', () {
    test('accepts a file within the limit', () {
      final result = screenAttachments([_file('song.mp3', bytes: 4 * 1024)]);
      expect(result.accepted.single.name, 'song.mp3');
      expect(result.error, isNull);
    });

    test('rejects a file over the limit, naming it and both sizes', () {
      final result = screenAttachments(
        [_file('album.mp3', bytes: 2048)],
        maxBytes: 1024,
      );
      expect(result.accepted, isEmpty);
      expect(result.error, contains('album.mp3'));
      expect(result.error, contains('2 KB'));
      expect(result.error, contains('1 KB'));
    });

    test('rejects a file the picker could not read', () {
      final result = screenAttachments([_file('remote.mp3')]);
      expect(result.accepted, isEmpty);
      expect(result.error, contains('remote.mp3'));
      expect(result.error, contains("couldn't be read"));
    });

    test('keeps the good files and reports only the bad ones', () {
      final result = screenAttachments([
        _file('ok.mp3', bytes: 512),
        _file('huge.mp3', bytes: 4096),
        _file('unreadable.mp3'),
      ], maxBytes: 1024);
      expect(result.accepted.map((f) => f.name), ['ok.mp3']);
      expect(result.rejections, hasLength(2));
    });

    test('the documented limit is 25 MB', () {
      expect(kMaxAttachmentBytes, 25 * 1024 * 1024);
      expect(formatFileSize(kMaxAttachmentBytes), '25 MB');
    });

    test('the fallback per-message count matches the accordserver default', () {
      expect(kMaxAttachmentsPerMessage, 10);
    });
  });

  group('screenAttachments per-message count', () {
    test('rejects files past maxCount, keeping the first ones', () {
      final result = screenAttachments([
        _file('a.png', bytes: 8),
        _file('b.png', bytes: 8),
        _file('c.png', bytes: 8),
      ], maxCount: 2);
      expect(result.accepted.map((f) => f.name), ['a.png', 'b.png']);
      expect(result.rejections, hasLength(1));
      expect(result.error, contains('c.png'));
      expect(result.error, contains('at most 2 files per message'));
    });

    test('counts files already on the composer', () {
      final result = screenAttachments([
        _file('third.png', bytes: 8),
      ], maxCount: 2, alreadyAttached: 2);
      expect(result.accepted, isEmpty);
      expect(result.error, contains('third.png'));
    });

    test('singularises the message at a limit of one', () {
      final result = screenAttachments([
        _file('a.png', bytes: 8),
        _file('b.png', bytes: 8),
      ], maxCount: 1);
      expect(result.error, contains('at most 1 file per message'));
    });

    test('an oversize file does not consume a slot', () {
      final result = screenAttachments([
        _file('huge.mp3', bytes: 4096),
        _file('ok.png', bytes: 8),
      ], maxBytes: 1024, maxCount: 1);
      expect(result.accepted.map((f) => f.name), ['ok.png']);
    });

    test('defaults to the fallback count when none is given', () {
      final result = screenAttachments([
        for (var i = 0; i < kMaxAttachmentsPerMessage + 1; i++)
          _file('f$i.png', bytes: 8),
      ]);
      expect(result.accepted, hasLength(kMaxAttachmentsPerMessage));
      expect(result.rejections, hasLength(1));
    });
  });

  group('unreadableAttachmentMessage', () {
    test('names the file', () {
      expect(
        unreadableAttachmentMessage('video.mov'),
        "video.mov couldn't be read. Copy it to local storage and try again.",
      );
    });
  });

  group('oversizeAttachmentMessage', () {
    test('names the file and both sizes, using the default limit', () {
      final message = oversizeAttachmentMessage('movie.mp4', 30 * 1024 * 1024);
      expect(message, contains('movie.mp4'));
      expect(message, contains('30 MB'));
      expect(message, contains('25 MB'));
    });

    test('honors an explicit maxBytes, matching screenAttachments wording', () {
      final direct = oversizeAttachmentMessage(
        'album.mp3',
        2048,
        maxBytes: 1024,
      );
      final viaScreening = screenAttachments(
        [_file('album.mp3', bytes: 2048)],
        maxBytes: 1024,
      ).error;
      expect(direct, viaScreening);
    });
  });
}
