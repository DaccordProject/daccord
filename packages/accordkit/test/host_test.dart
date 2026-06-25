import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('isValidHost', () {
    test('accepts plain hostnames and IPv4 literals', () {
      expect(isValidHost('b.example'), isTrue);
      expect(isValidHost('chat.example.com'), isTrue);
      expect(isValidHost('localhost'), isTrue);
      expect(isValidHost('good-host.example'), isTrue);
      expect(isValidHost('203.0.113.10'), isTrue);
    });

    test('rejects userinfo, path separators and URL metacharacters', () {
      for (final bad in [
        'a.example@evil.com', // smuggled userinfo
        'a.example/path',
        r'a.example\evil.com',
        'a.example?x=1',
        'host with space',
        'ho<st',
        'ho"st',
      ]) {
        expect(isValidHost(bad), isFalse, reason: '"$bad" should be rejected');
      }
    });

    test('rejects empty and edge-label hosts', () {
      expect(isValidHost(''), isFalse);
      expect(isValidHost('.example'), isFalse);
      expect(isValidHost('example.'), isFalse);
      expect(isValidHost('-example'), isFalse);
      expect(isValidHost('a..b'), isFalse);
    });

    test('does not accept a port (split it off first)', () {
      expect(isValidHost('b.example:443'), isFalse);
    });
  });

  group('isLoopbackOrLinkLocalHost', () {
    test('flags loopback and link-local hosts', () {
      for (final host in [
        'localhost',
        'app.localhost',
        '127.0.0.1',
        '127.13.2.9',
        '0.0.0.0',
        '::1',
        '169.254.0.1',
        '169.254.169.254', // cloud metadata
      ]) {
        expect(isLoopbackOrLinkLocalHost(host), isTrue, reason: host);
      }
    });

    test('does not flag routable hosts', () {
      for (final host in [
        'b.example',
        '203.0.113.10',
        '8.8.8.8',
        '169.1.1.1',
      ]) {
        expect(isLoopbackOrLinkLocalHost(host), isFalse, reason: host);
      }
    });
  });
}
