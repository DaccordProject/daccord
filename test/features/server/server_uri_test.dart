import 'package:bonfire/features/server/utils/server_uri.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServerUri.parseServerUrl', () {
    test('bare host assumes https://', () {
      final parsed = ServerUri.parseServerUrl('chat.example.com');
      expect(parsed, isNotNull);
      expect(parsed!.route, 'connect');
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
      expect(parsed.server?.gatewayUrl, 'wss://chat.example.com/ws');
      expect(parsed.token, isNull);
      expect(parsed.invite, isNull);
      expect(parsed.spaceName, isNull);
    });

    test('explicit http://host:port keeps scheme and port', () {
      final parsed = ServerUri.parseServerUrl('http://localhost:3000');
      expect(parsed, isNotNull);
      expect(parsed!.server?.baseUrl, 'http://localhost:3000');
      expect(parsed.server?.gatewayUrl, 'ws://localhost:3000/ws');
    });

    test('rejects an explicit cleartext remote server URL', () {
      expect(ServerUri.parseServerUrl('http://chat.example.com'), isNull);
    });

    test('#space-name fragment becomes spaceName', () {
      final parsed = ServerUri.parseServerUrl('chat.example.com#my-space');
      expect(parsed, isNotNull);
      expect(parsed!.spaceName, 'my-space');
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('an empty fragment is ignored', () {
      final parsed = ServerUri.parseServerUrl('chat.example.com#');
      expect(parsed, isNotNull);
      expect(parsed!.spaceName, isNull);
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('?token=&invite= query populates token and invite', () {
      final parsed =
          ServerUri.parseServerUrl('chat.example.com?token=abc&invite=xyz');
      expect(parsed, isNotNull);
      expect(parsed!.token, 'abc');
      expect(parsed.invite, 'xyz');
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('query placed after the fragment is still parsed (godot ordering)', () {
      final parsed =
          ServerUri.parseServerUrl('chat.example.com#my-space?token=abc');
      expect(parsed, isNotNull);
      expect(parsed!.spaceName, 'my-space');
      expect(parsed.token, 'abc');
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('blank token/invite values normalise to null', () {
      final parsed =
          ServerUri.parseServerUrl('chat.example.com?token=&invite=');
      expect(parsed, isNotNull);
      expect(parsed!.token, isNull);
      expect(parsed.invite, isNull);
    });

    test('empty input returns null', () {
      expect(ServerUri.parseServerUrl(''), isNull);
    });

    test('whitespace-only input returns null', () {
      expect(ServerUri.parseServerUrl('   '), isNull);
    });

    test('input that is only a fragment/query returns null', () {
      expect(ServerUri.parseServerUrl('#space'), isNull);
      expect(ServerUri.parseServerUrl('?token=abc'), isNull);
    });

    test('a daccord:// string delegates to parseDeepLink', () {
      final parsed =
          ServerUri.parseServerUrl('daccord://connect/chat.example.com');
      expect(parsed, isNotNull);
      expect(parsed!.route, 'connect');
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });
  });

  group('ServerUri.parseDeepLink — connect', () {
    test('full connect link with host:port, slug, token and invite', () {
      final parsed = ServerUri.parseDeepLink(
          'daccord://connect/localhost:3000/my-space?token=t1&invite=i1');
      expect(parsed, isNotNull);
      expect(parsed!.route, 'connect');
      expect(parsed.server?.baseUrl, 'https://localhost:3000');
      expect(parsed.spaceName, 'my-space');
      expect(parsed.token, 't1');
      expect(parsed.invite, 'i1');
    });

    test('connect link without a slug leaves spaceName null', () {
      final parsed =
          ServerUri.parseDeepLink('daccord://connect/chat.example.com');
      expect(parsed, isNotNull);
      expect(parsed!.spaceName, isNull);
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('connect link with a numeric port keeps the port in the base url',
        () {
      final parsed =
          ServerUri.parseDeepLink('daccord://connect/localhost:8080');
      expect(parsed, isNotNull);
      expect(parsed!.server?.baseUrl, 'https://localhost:8080');
    });

    test('connect link with blank token/invite normalises to null', () {
      final parsed = ServerUri.parseDeepLink(
          'daccord://connect/chat.example.com?token=&invite=');
      expect(parsed, isNotNull);
      expect(parsed!.token, isNull);
      expect(parsed.invite, isNull);
    });
  });

  group('ServerUri.parseDeepLink — invite', () {
    test('invite/<code>@<host> preserves the code and sets route=invite', () {
      final parsed =
          ServerUri.parseDeepLink('daccord://invite/ABC123@chat.example.com');
      expect(parsed, isNotNull);
      expect(parsed!.route, 'invite');
      expect(parsed.invite, 'ABC123');
      expect(parsed.hasInvite, isTrue);
      expect(parsed.server?.baseUrl, 'https://chat.example.com');
    });

    test('a non-alphanumeric invite code returns null', () {
      expect(
        ServerUri.parseDeepLink('daccord://invite/AB-12@chat.example.com'),
        isNull,
      );
    });

    test('an invite link missing the @host returns null', () {
      expect(ServerUri.parseDeepLink('daccord://invite/ABC123'), isNull);
    });

    test('an invite link with an empty code returns null', () {
      expect(
        ServerUri.parseDeepLink('daccord://invite/@chat.example.com'),
        isNull,
      );
    });
  });

  group('ServerUri.parseDeepLink — navigate', () {
    test('navigate/<space>/<channel>?msg=<id> splits all three ids', () {
      final parsed = ServerUri.parseDeepLink(
          'daccord://navigate/space1/chan1?msg=msg1');
      expect(parsed, isNotNull);
      expect(parsed!.route, 'navigate');
      expect(parsed.server, isNull);
      expect(parsed.spaceId, 'space1');
      expect(parsed.channelId, 'chan1');
      expect(parsed.messageId, 'msg1');
    });

    test('bare navigate/<space> leaves channel and message null', () {
      final parsed = ServerUri.parseDeepLink('daccord://navigate/space1');
      expect(parsed, isNotNull);
      expect(parsed!.spaceId, 'space1');
      expect(parsed.channelId, isNull);
      expect(parsed.messageId, isNull);
    });

    test('navigate with a trailing empty channel segment stays null', () {
      final parsed = ServerUri.parseDeepLink('daccord://navigate/space1/');
      expect(parsed, isNotNull);
      expect(parsed!.spaceId, 'space1');
      expect(parsed.channelId, isNull);
    });
  });

  group('ServerUri.parseDeepLink — malformed', () {
    test('a non-daccord scheme returns null', () {
      expect(ServerUri.parseDeepLink('https://chat.example.com'), isNull);
    });

    test('an unknown route returns null', () {
      expect(ServerUri.parseDeepLink('daccord://teleport/space1'), isNull);
    });

    test('an empty payload returns null', () {
      expect(ServerUri.parseDeepLink('daccord://connect/'), isNull);
    });

    test('a missing slash (route only) returns null', () {
      expect(ServerUri.parseDeepLink('daccord://connect'), isNull);
    });

    test('the scheme with no body returns null', () {
      expect(ServerUri.parseDeepLink('daccord://'), isNull);
    });
  });

  group('ServerUri host validation', () {
    test('a host containing a space is rejected', () {
      expect(ServerUri.parseDeepLink('daccord://connect/bad host'), isNull);
    });

    test('hosts containing < > ; \' or " are rejected', () {
      for (final bad in ['ho<st', 'ho>st', 'ho;st', "ho'st", 'ho"st']) {
        expect(
          ServerUri.parseDeepLink('daccord://connect/$bad'),
          isNull,
          reason: 'expected "$bad" to be rejected',
        );
      }
    });

    test('an invite link with an invalid host is rejected', () {
      expect(
        ServerUri.parseDeepLink('daccord://invite/ABC123@bad host'),
        isNull,
      );
    });

    test('a clean host:port authority validates and is accepted', () {
      final parsed =
          ServerUri.parseDeepLink('daccord://connect/good.host:443');
      expect(parsed, isNotNull);
      expect(parsed!.server?.baseUrl, 'https://good.host:443');
    });

    test('a host smuggling userinfo or a path is rejected', () {
      // `trusted.example@evil.com` would authenticate against evil.com while
      // appearing to target trusted.example; the strict allowlist rejects it.
      for (final bad in [
        'trusted.example@evil.com',
        r'trusted.example\evil.com',
      ]) {
        expect(
          ServerUri.parseDeepLink('daccord://connect/$bad'),
          isNull,
          reason: 'expected "$bad" to be rejected',
        );
      }
    });
  });
}
