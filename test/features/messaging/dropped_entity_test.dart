import 'dart:io';

import 'package:bonfire/features/messaging/utils/dropped_entity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dropped_entity'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('isDroppedDirectory', () {
    test('is true for a directory', () {
      expect(isDroppedDirectory(tmp.path), isTrue);
    });

    test('is false for a regular file', () {
      final file = File('${tmp.path}/note.txt')..writeAsStringSync('hi');
      expect(isDroppedDirectory(file.path), isFalse);
    });

    test('is false for a path that does not exist', () {
      // A vanished path is a read failure, not a folder — the caller should
      // report it as unreadable rather than tell the user to open it.
      expect(isDroppedDirectory('${tmp.path}/gone'), isFalse);
    });

    test('is false for an empty path', () {
      // Web drops and macOS file promises can carry no path at all.
      expect(isDroppedDirectory(''), isFalse);
    });
  });

  test('a dropped directory would otherwise read as an unreadable file', () {
    // Why the check exists. desktop_drop types directories as
    // DropItemDirectory only on macOS and web; Linux and Windows share a
    // handler that wraps every dropped path in a DropItemFile. The composer
    // then calls XFile.length() on it, which throws — and a caught throw is
    // reported as "couldn't be read. Copy it to local storage and try again",
    // advice that cannot help someone who dropped a folder. XFile.length()
    // delegates straight to File.length(), asserted on here to keep the test
    // off a transitive dependency.
    expect(
      () => File(tmp.path).length(),
      throwsA(isA<FileSystemException>()),
    );
  });
}
