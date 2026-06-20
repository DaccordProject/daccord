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
