import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('transport security', () {
    test('accepts secure remote HTTP and WebSocket endpoints', () {
      expect(
        validateHttpEndpoint('https://chat.example.test/api').host,
        'chat.example.test',
      );
      expect(
        validateWebSocketEndpoint('wss://chat.example.test/ws').host,
        'chat.example.test',
      );
    });

    test('accepts cleartext only for genuine loopback hosts', () {
      for (final host in [
        'localhost',
        '127.0.0.1',
        '127.25.50.75',
        '[::1]',
        '[0:0:0:0:0:0:0:1]',
      ]) {
        expect(
          () => validateHttpEndpoint('http://$host:3000'),
          returnsNormally,
        );
        expect(
          () => validateWebSocketEndpoint('ws://$host:3000/ws'),
          returnsNormally,
        );
      }
    });

    test(
      'rejects remote, wildcard, private, and link-local cleartext hosts',
      () {
        for (final host in [
          'chat.example.test',
          '0.0.0.0',
          '10.0.0.1',
          '192.168.1.2',
          '169.254.1.1',
        ]) {
          expect(
            () => validateHttpEndpoint('http://$host:3000'),
            throwsFormatException,
          );
          expect(
            () => validateWebSocketEndpoint('ws://$host:3000/ws'),
            throwsFormatException,
          );
        }
      },
    );

    test('rejects wrong schemes and malformed URLs', () {
      expect(
        () => validateHttpEndpoint('ftp://chat.example.test'),
        throwsFormatException,
      );
      expect(
        () => validateWebSocketEndpoint('https://chat.example.test/ws'),
        throwsFormatException,
      );
      expect(() => validateHttpEndpoint('not a URL'), throwsFormatException);
    });
  });
}
