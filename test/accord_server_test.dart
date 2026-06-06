import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AccordServer.fromBaseUrl', () {
    test('derives wss gateway and cdn from an https base', () {
      final server = AccordServer.fromBaseUrl('https://chat.example.com');
      expect(server.baseUrl, 'https://chat.example.com');
      expect(server.gatewayUrl, 'wss://chat.example.com/ws');
      expect(server.cdnUrl, 'https://chat.example.com/cdn');
      expect(server.name, 'chat.example.com');
    });

    test('derives ws gateway from an http base and keeps the port', () {
      final server = AccordServer.fromBaseUrl('http://localhost:3000');
      expect(server.gatewayUrl, 'ws://localhost:3000/ws');
      expect(server.cdnUrl, 'http://localhost:3000/cdn');
    });

    test('assumes https and strips trailing slashes for a bare host', () {
      final server = AccordServer.fromBaseUrl('my.server/');
      expect(server.baseUrl, 'https://my.server');
      expect(server.gatewayUrl, 'wss://my.server/ws');
    });
  });

  group('AccordSession', () {
    test('round-trips through JSON', () {
      final session = AccordSession(
        server: AccordServer.fromBaseUrl('https://chat.example.com'),
        token: 'tok_abc',
        tokenType: 'User',
        userId: '42',
        username: 'ada',
        avatar: 'avatars/42.png',
      );

      final restored = AccordSession.fromJson(session.toJson());

      expect(restored.token, session.token);
      expect(restored.tokenType, 'User');
      expect(restored.userId, '42');
      expect(restored.username, 'ada');
      expect(restored.avatar, 'avatars/42.png');
      expect(restored.server, session.server);
    });

    test('defaults tokenType to Bearer when absent', () {
      // Older Hive blobs predate the Bearer migration and omit the field
      // entirely; we must restore them with the modern default so the gateway
      // IDENTIFY uses the right scheme.
      final json = {
        'server': AccordServer.fromBaseUrl('https://x.test').toJson(),
        'token': 't',
        'userId': '1',
        'username': 'u',
      };
      expect(AccordSession.fromJson(json).tokenType, 'Bearer');
    });
  });
}
