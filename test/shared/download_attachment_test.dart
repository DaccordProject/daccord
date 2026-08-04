import 'package:bonfire/shared/utils/download_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('sanitizeAttachmentFilename', () {
    test('leaves an ordinary name alone', () {
      expect(sanitizeAttachmentFilename('track.mp3'), 'track.mp3');
      expect(
        sanitizeAttachmentFilename('My Voice Memo (final).m4a'),
        'My Voice Memo (final).m4a',
      );
    });

    test('strips directory components, keeping only the last segment', () {
      expect(sanitizeAttachmentFilename('sounds/track.mp3'), 'track.mp3');
      expect(sanitizeAttachmentFilename(r'sounds\track.mp3'), 'track.mp3');
    });

    test('defeats traversal', () {
      for (final hostile in [
        '../../../etc/passwd',
        r'..\..\Windows\System32\evil.dll',
        '/etc/passwd',
        r'C:\Windows\evil.dll',
        'a/../../../b.txt',
      ]) {
        final safe = sanitizeAttachmentFilename(hostile);
        expect(safe, isNot(contains('/')), reason: hostile);
        expect(safe, isNot(contains(r'\')), reason: hostile);
        expect(safe, isNot('..'), reason: hostile);
        // The whole point: joining can only ever name a direct child.
        expect(p.dirname(p.join('/downloads', safe)), '/downloads');
      }
    });

    test('falls back when nothing usable survives', () {
      expect(sanitizeAttachmentFilename(''), 'download');
      expect(sanitizeAttachmentFilename('..'), 'download');
      expect(sanitizeAttachmentFilename('.'), 'download');
      expect(sanitizeAttachmentFilename('///'), 'download');
      expect(sanitizeAttachmentFilename('   '), 'download');
      expect(sanitizeAttachmentFilename('x', fallback: 'y'), 'x');
      expect(sanitizeAttachmentFilename('', fallback: 'y'), 'y');
    });

    test('removes control characters, including NUL', () {
      expect(sanitizeAttachmentFilename('tr\u0000ack.mp3'), 'track.mp3');
      expect(sanitizeAttachmentFilename('tr\nack\t.mp3'), 'track.mp3');
    });

    test('replaces characters Windows rejects', () {
      expect(sanitizeAttachmentFilename('a<b>c:d"e|f?g*h.mp3'),
          'a_b_c_d_e_f_g_h.mp3');
    });

    test('drops trailing dots and spaces Windows would eat', () {
      expect(sanitizeAttachmentFilename('evil.exe.'), 'evil.exe');
      expect(sanitizeAttachmentFilename('evil.exe   '), 'evil.exe');
    });

    test('escapes Windows reserved device names', () {
      expect(sanitizeAttachmentFilename('CON.mp3'), '_CON.mp3');
      expect(sanitizeAttachmentFilename('nul'), '_nul');
      expect(sanitizeAttachmentFilename('com9.txt'), '_com9.txt');
      // Not reserved — only the exact stems are.
      expect(sanitizeAttachmentFilename('console.txt'), 'console.txt');
    });

    test('truncates a long name but keeps the extension', () {
      final long = '${'a' * 400}.mp3';
      final safe = sanitizeAttachmentFilename(long);
      expect(safe.length, lessThanOrEqualTo(120));
      expect(p.extension(safe), '.mp3');
    });
  });

  group('uniqueDownloadPath', () {
    test('uses the plain name when it is free', () {
      expect(
        uniqueDownloadPath('/dl', 'track.mp3', (_) => false),
        p.join('/dl', 'track.mp3'),
      );
    });

    test('appends an incrementing counter rather than overwriting', () {
      final taken = {p.join('/dl', 'track.mp3')};
      expect(
        uniqueDownloadPath('/dl', 'track.mp3', taken.contains),
        p.join('/dl', 'track (1).mp3'),
      );

      taken.add(p.join('/dl', 'track (1).mp3'));
      taken.add(p.join('/dl', 'track (2).mp3'));
      expect(
        uniqueDownloadPath('/dl', 'track.mp3', taken.contains),
        p.join('/dl', 'track (3).mp3'),
      );
    });

    test('handles an extensionless name', () {
      expect(
        uniqueDownloadPath('/dl', 'README', (_) => true, maxAttempts: 2),
        isNot(p.join('/dl', 'README')),
      );
      expect(
        uniqueDownloadPath('/dl', 'README', (path) => !path.contains('(1)')),
        p.join('/dl', 'README (1)'),
      );
    });

    test('gives up on a unique suffix rather than returning a taken path', () {
      final path =
          uniqueDownloadPath('/dl', 'track.mp3', (_) => true, maxAttempts: 3);
      expect(path, startsWith(p.join('/dl', 'track (')));
      expect(path, endsWith('.mp3'));
      expect(path, isNot(p.join('/dl', 'track.mp3')));
    });
  });
}
