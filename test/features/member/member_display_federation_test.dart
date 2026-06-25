import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/member/utils/member_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('federation origin helpers', () {
    test('local user has no origin and is not remote', () {
      final user = AccordUser(id: '123', username: 'alice');
      expect(accordUserOrigin(user), isNull);
      expect(accordIsRemoteUser(user), isFalse);
    });

    test('remote user origin comes from the field or a qualified id', () {
      final byField =
          AccordUser(id: '123@b.example', username: 'a', origin: 'b.example');
      expect(accordUserOrigin(byField), 'b.example');
      expect(accordIsRemoteUser(byField), isTrue);

      final byId = AccordUser(id: '123@c.example', username: 'a');
      expect(accordUserOrigin(byId), 'c.example');
    });

    test('member origin/isRemote derive from the user id', () {
      final member = AccordMember.fromJson({
        'space_id': '7@b.example',
        'user': {'id': '123@b.example', 'username': 'alice@b.example'},
      });
      expect(accordIsRemoteMember(member), isTrue);
      expect(accordMemberOrigin(member), 'b.example');
    });
  });

  group('remote avatar resolution', () {
    test('local bare hash resolves against the connected CDN', () {
      final user = AccordUser(id: '123', username: 'a', avatar: 'abc');
      final url = accordAvatarUrl(user, 'https://home.example/cdn');
      expect(url, 'https://home.example/cdn/avatars/123/abc.png');
    });

    test('remote bare hash resolves against the home server CDN', () {
      final user = AccordUser(
        id: '123@b.example',
        username: 'a',
        avatar: 'abc',
        origin: 'b.example',
      );
      // Connected server is a.example, but the asset lives on b.example; the id
      // is qualified so the path uses the bare snowflake.
      final url = accordAvatarUrl(user, 'https://a.example/cdn');
      expect(url, 'https://b.example/cdn/avatars/123/abc.png');
    });

    test('absolute remote avatar URL passes through unchanged', () {
      final user = AccordUser(
        id: '123@b.example',
        username: 'a',
        avatar: 'https://b.example/cdn/avatars/123/abc.png',
        origin: 'b.example',
      );
      expect(
        accordAvatarUrl(user, 'https://a.example/cdn'),
        'https://b.example/cdn/avatars/123/abc.png',
      );
    });

    test('cdnBaseForDomain mirrors per-server CDN derivation', () {
      expect(cdnBaseForDomain('b.example'), 'https://b.example/cdn');
      expect(cdnBaseForDomain('b.example:8443'), 'https://b.example:8443/cdn');
    });

    test('cdnBaseForDomain rejects unsafe home domains', () {
      // Loopback / link-local would turn an avatar fetch into an SSRF probe.
      expect(cdnBaseForDomain('localhost'), isNull);
      expect(cdnBaseForDomain('127.0.0.1'), isNull);
      expect(cdnBaseForDomain('169.254.169.254'), isNull);
      // Smuggled userinfo / path must not pass as a host.
      expect(cdnBaseForDomain('b.example@evil.com'), isNull);
      expect(cdnBaseForDomain('b.example/evil'), isNull);
    });

    test('an off-home absolute remote avatar URL is rejected (no fetch)', () {
      final user = AccordUser(
        id: '123@b.example',
        username: 'a',
        avatar: 'https://tracker.evil/pixel.png',
        origin: 'b.example',
      );
      // Avatar points off the home server: render an initial rather than leak
      // the viewer's IP to an attacker-controlled host.
      expect(accordAvatarUrl(user, 'https://a.example/cdn'), isNull);
    });

    test('a remote user homed on a loopback origin is not fetched', () {
      final user = AccordUser(
        id: '123@localhost',
        username: 'a',
        avatar: 'abc',
        origin: 'localhost',
      );
      expect(accordAvatarUrl(user, 'https://a.example/cdn'), isNull);
    });

    test('a remote member off-home avatar override falls back, not off-home',
        () {
      final member = AccordMember.fromJson({
        'space_id': '7@b.example',
        'user': {'id': '123@b.example', 'username': 'a', 'avatar': 'abc'},
        'avatar': 'https://tracker.evil/x.png',
      });
      // The override is off-home, so we fall back to the user's home-CDN avatar.
      expect(
        accordMemberAvatarUrl(member, 'https://a.example/cdn'),
        'https://b.example/cdn/avatars/123/abc.png',
      );
    });

    test('a remote emoji resolves against its home CDN; off-home is rejected',
        () {
      final home = AccordEmoji.fromJson({
        'id': '55@b.example',
        'name': 'party',
        'origin': 'b.example',
        'image_url': 'https://b.example/cdn/emojis/55.png',
      });
      expect(
        accordEmojiUrl(home, 'https://a.example/cdn'),
        'https://b.example/cdn/emojis/55.png',
      );

      final offHome = AccordEmoji.fromJson({
        'id': '55@b.example',
        'name': 'party',
        'origin': 'b.example',
        'image_url': 'https://tracker.evil/e.png',
      });
      expect(accordEmojiUrl(offHome, 'https://a.example/cdn'), isNull);

      // A remote emoji with no explicit imageUrl resolves by bare id on home.
      final byId = AccordEmoji.fromJson({
        'id': '55@b.example',
        'name': 'party',
        'origin': 'b.example',
      });
      expect(
        accordEmojiUrl(byId, 'https://a.example/cdn'),
        'https://b.example/cdn/emojis/55.png',
      );
    });

    test('remote server-relative avatar path resolves against the home CDN', () {
      final user = AccordUser(
        id: '123@b.example',
        username: 'a',
        avatar: '/cdn/avatars/custom/avatar.png',
        origin: 'b.example',
      );
      // A server-relative path is rewritten with the home CDN prefix.
      expect(
        accordAvatarUrl(user, 'https://a.example/cdn'),
        'https://b.example/cdn/avatars/custom/avatar.png',
      );
    });

    test('remote member bare-hash override resolves against the home CDN', () {
      final member = AccordMember.fromJson({
        'space_id': '7@b.example',
        'user': {'id': '123@b.example', 'username': 'alice'},
        'avatar': 'spaceavatar',
      });
      // The space-scoped avatar override should also resolve to the home CDN.
      final url = accordMemberAvatarUrl(member, 'https://a.example/cdn');
      expect(url, 'https://b.example/cdn/avatars/spaceavatar');
    });
  });
}
