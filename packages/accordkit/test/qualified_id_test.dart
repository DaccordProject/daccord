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

  group('isSameUser', () {
    test('matches a bare local id', () {
      expect(isSameUser('123', '123'), isTrue);
      expect(isSameUser('456', '123'), isFalse);
    });

    test('matches our own action echoed back qualified to our home domain', () {
      // We react/type/post on a remote-homed surface; the home re-qualifies our
      // id to our domain before fanning it back to us.
      expect(isSameUser('123@a.example', '123', localDomain: 'a.example'),
          isTrue);
    });

    test('does not match a remote actor that shares our bare snowflake', () {
      // Snowflakes are only unique per home server, so a remote 123@b.example
      // must not be mistaken for our local 123 — that is the whole point of
      // qualifying.
      expect(isSameUser('123@b.example', '123', localDomain: 'a.example'),
          isFalse);
    });

    test('a qualified actor is never self without a known home domain', () {
      expect(isSameUser('123@a.example', '123'), isFalse);
      expect(isSameUser('123@a.example', '123', localDomain: ''), isFalse);
    });

    test('a different local id is not self even when qualified to our domain',
        () {
      expect(isSameUser('999@a.example', '123', localDomain: 'a.example'),
          isFalse);
    });
  });
}
