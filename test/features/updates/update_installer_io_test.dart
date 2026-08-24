import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:bonfire/features/updates/services/update_installer_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('update-installer-archive-test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  File zipFixture(String name, Iterable<ArchiveFile> files) {
    final archive = Archive();
    for (final entry in files) {
      archive.addFile(entry);
    }
    final file = File(p.join(temp.path, name));
    file.writeAsBytesSync(ZipEncoder().encode(archive)!);
    return file;
  }

  File tarGzFixture(String name, Iterable<ArchiveFile> files) {
    final archive = Archive();
    for (final entry in files) {
      archive.addFile(entry);
    }
    final tar = TarEncoder().encode(archive);
    final file = File(p.join(temp.path, name));
    file.writeAsBytesSync(GZipEncoder().encode(tar)!);
    return file;
  }

  int findSignature(List<int> bytes, List<int> signature) {
    for (var i = 0; i <= bytes.length - signature.length; i++) {
      var matches = true;
      for (var j = 0; j < signature.length; j++) {
        if (bytes[i + j] != signature[j]) {
          matches = false;
          break;
        }
      }
      if (matches) return i;
    }
    return -1;
  }

  void writeUint32(List<int> bytes, int offset, int value) {
    for (var i = 0; i < 4; i++) {
      bytes[offset + i] = (value >> (8 * i)) & 0xff;
    }
  }

  File zipWithFalseExpandedSize(String name, List<int> content) {
    final archive = Archive()
      ..addFile(ArchiveFile('app', content.length, content));
    final bytes = ZipEncoder().encode(archive)!;
    final centralHeader = findSignature(bytes, const [0x50, 0x4b, 0x01, 0x02]);
    expect(centralHeader, isNonNegative);
    writeUint32(bytes, 22, 1); // local header uncompressed size
    writeUint32(bytes, centralHeader + 24, 1);
    return File(p.join(temp.path, name))..writeAsBytesSync(bytes);
  }

  Future<void> expectRejected(UpdateInstaller installer, File archive) async {
    final destination = Directory(p.join(temp.path, 'staged'));
    await expectLater(
      installer.extractArchiveForTesting(archive, destination),
      throwsA(isA<UpdateInstallException>()),
    );
    expect(destination.existsSync(), isFalse);
  }

  group('secure updater extraction', () {
    test('preserves nested files for zip and tar.gz bundles', () async {
      final installer = UpdateInstaller();
      final fixtures = [
        zipFixture('bundle.zip', [
          ArchiveFile('bundle/data/app.txt', 4, utf8.encode('zip!')),
        ]),
        tarGzFixture('bundle.tgz', [
          ArchiveFile('bundle/data/app.txt', 4, utf8.encode('tar!')),
        ]),
      ];

      for (final fixture in fixtures) {
        final destination = Directory(
          p.join(temp.path, 'staged-${p.extension(fixture.path)}'),
        );
        await installer.extractArchiveForTesting(fixture, destination);
        expect(
          File(
            p.join(destination.path, 'bundle', 'data', 'app.txt'),
          ).readAsStringSync(),
          fixture.path.endsWith('.zip') ? 'zip!' : 'tar!',
        );
      }
    });

    test('rejects parent traversal and absolute archive paths', () async {
      final installer = UpdateInstaller();
      final fixtures = [
        zipFixture('parent-traversal.zip', [
          ArchiveFile('../escaped.txt', 3, utf8.encode('bad')),
        ]),
        zipFixture('absolute-path.zip', [
          ArchiveFile('/tmp/daccord-escaped.txt', 3, utf8.encode('bad')),
        ]),
        zipFixture('windows-absolute-path.zip', [
          ArchiveFile(r'C:\escaped.txt', 3, utf8.encode('bad')),
        ]),
      ];

      for (final fixture in fixtures) {
        await expectRejected(installer, fixture);
      }
      expect(File(p.join(temp.path, 'escaped.txt')).existsSync(), isFalse);
    });

    test('rejects a symlink whose target escapes the staging root', () async {
      final link = ArchiveFile('bundle/link', 0, const <int>[])
        ..isSymbolicLink = true
        ..nameOfLinkedFile = '../../escaped';
      await expectRejected(
        UpdateInstaller(),
        tarGzFixture('unsafe-link.tar.gz', [link]),
      );
    });

    test('creates an in-root symlink only after regular files', () async {
      if (Platform.isWindows) return;
      final link = ArchiveFile('bundle/app-link', 0, const <int>[])
        ..isSymbolicLink = true
        ..nameOfLinkedFile = 'app';
      final archive = tarGzFixture('safe-link.tar.gz', [
        link,
        ArchiveFile('bundle/app', 2, utf8.encode('ok')),
      ]);
      final destination = Directory(p.join(temp.path, 'safe-link-staged'));

      await UpdateInstaller().extractArchiveForTesting(archive, destination);

      final extractedLink = Link(
        p.join(destination.path, 'bundle', 'app-link'),
      );
      expect(extractedLink.existsSync(), isTrue);
      expect(
        File(extractedLink.resolveSymbolicLinksSync()).readAsStringSync(),
        'ok',
      );
    });

    test('caps compressed archive input', () async {
      final archive = zipFixture('compressed-limit.zip', [
        ArchiveFile('app', 32, List<int>.filled(32, 1)),
      ]);
      await expectRejected(
        UpdateInstaller(
          archiveLimits: const UpdateArchiveLimits(
            maxCompressedBytes: 16,
            maxExpandedBytes: 1024,
            maxEntries: 10,
          ),
        ),
        archive,
      );
    });

    test('caps declared expanded bytes', () async {
      final archive = zipFixture('expanded-limit.zip', [
        ArchiveFile('app', 6, List<int>.filled(6, 1)),
      ]);
      await expectRejected(
        UpdateInstaller(
          archiveLimits: const UpdateArchiveLimits(
            maxCompressedBytes: 1024,
            maxExpandedBytes: 5,
            maxEntries: 10,
          ),
        ),
        archive,
      );
    });

    test('caps actual expanded output when zip metadata lies', () async {
      final archive = zipWithFalseExpandedSize(
        'false-expanded-size.zip',
        List<int>.filled(6, 1),
      );
      await expectRejected(
        UpdateInstaller(
          archiveLimits: const UpdateArchiveLimits(
            maxCompressedBytes: 1024,
            maxExpandedBytes: 5,
            maxEntries: 10,
          ),
        ),
        archive,
      );
    });

    test('caps archive entry count', () async {
      final archive = zipFixture('entry-limit.zip', [
        ArchiveFile('one', 0, const <int>[]),
        ArchiveFile('two', 0, const <int>[]),
        ArchiveFile('three', 0, const <int>[]),
      ]);
      await expectRejected(
        UpdateInstaller(
          archiveLimits: const UpdateArchiveLimits(
            maxCompressedBytes: 1024,
            maxExpandedBytes: 1024,
            maxEntries: 2,
          ),
        ),
        archive,
      );
    });

    test('caps gzip output before decoding the tar container', () async {
      final archive = tarGzFixture('gzip-limit.tgz', [
        ArchiveFile('app', 1, const [1]),
      ]);
      await expectRejected(
        UpdateInstaller(
          archiveLimits: const UpdateArchiveLimits(
            maxCompressedBytes: 1024,
            maxExpandedBytes: 128,
            maxEntries: 10,
          ),
        ),
        archive,
      );
    });
  });

  test('download stream is deleted when it exceeds the byte cap', () async {
    final client = MockClient.streaming((request, body) async {
      return http.StreamedResponse(
        http.ByteStream(
          Stream<List<int>>.fromIterable([
            const [1, 2, 3, 4],
            const [5, 6, 7, 8],
          ]),
        ),
        200,
      );
    });
    final installer = UpdateInstaller(
      client: client,
      archiveLimits: const UpdateArchiveLimits(
        maxCompressedBytes: 6,
        maxExpandedBytes: 1024,
        maxEntries: 10,
      ),
      temporaryDirectory: () async => temp,
    );

    await expectLater(
      installer.download('https://example.test/bundle.zip'),
      throwsA(isA<UpdateInstallException>()),
    );
    expect(
      File(p.join(temp.path, 'daccord-update', 'bundle.zip')).existsSync(),
      isFalse,
    );
  });
}
