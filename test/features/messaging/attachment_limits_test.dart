import 'dart:typed_data';

import 'package:bonfire/features/messaging/utils/attachment_limits.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';

PlatformFile _file(String name, {int? bytes}) => PlatformFile(
  name: name,
  size: bytes ?? 0,
  bytes: bytes == null ? null : Uint8List(bytes),
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
  });
}
