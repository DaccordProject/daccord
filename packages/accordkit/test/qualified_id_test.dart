import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('qualified ID helpers', () {
    test('localPart drops the @domain suffix', () {
      expect(localPart('123@b.example'), '123');
      expect(localPart('123'), '123');
      expect(localPart('alice@b.example'), 'alice');
    });

    test('domainOf returns the home domain, or null for bare ids', () {
      expect(domainOf('123@b.example'), 'b.example');
      expect(domainOf('123'), isNull);
      // A trailing '@' with no domain is treated as not-qualified.
      expect(domainOf('123@'), isNull);
    });

    test('isRemoteId detects qualified ids', () {
      expect(isRemoteId('123@b.example'), isTrue);
      expect(isRemoteId('123'), isFalse);
    });

    test('qualify is idempotent', () {
      expect(qualify('123', 'a.example'), '123@a.example');
      expect(qualify('123@b.example', 'a.example'), '123@b.example');
    });

    test('a remote 123@b.example never collides with a local 123', () {
      expect('123' == '123@b.example', isFalse);
      expect(localPart('123@b.example') == '123', isTrue);
    });
  });
}
