import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('AccordCDN', () {
    test('avatar url', () {
      expect(
        AccordCDN.avatar('1', 'hash', cdnUrl: 'https://cdn'),
        'https://cdn/avatars/1/hash.png',
      );
    });

    test('animated detection and auto format', () {
      expect(AccordCDN.isAnimated('a_123'), isTrue);
      expect(AccordCDN.autoFormat('a_123'), 'gif');
      expect(AccordCDN.autoFormat('123'), 'png');
    });

    test('resolvePath handles absolute, /cdn/, /, and bare', () {
      expect(AccordCDN.resolvePath('https://x/y'), 'https://x/y');
      expect(AccordCDN.resolvePath('/cdn/a.png', cdnUrl: 'https://cdn'),
          'https://cdn/a.png');
      expect(AccordCDN.resolvePath('/a.png', cdnUrl: 'https://cdn'),
          'https://cdn/a.png');
      expect(AccordCDN.resolvePath('a.png', cdnUrl: 'https://cdn'),
          'https://cdn/a.png');
    });

    test('buildDataUri infers mime from extension', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final uri = AccordCDN.buildDataUri(bytes, 'pic.jpeg');
      expect(uri.startsWith('data:image/jpeg;base64,'), isTrue);
      expect(uri.endsWith(base64Encode(bytes)), isTrue);
    });

    test('emoji', () {
      expect(AccordCDN.emoji('9', cdnUrl: 'https://cdn'),
          'https://cdn/emojis/9.png');
    });
  });

  group('GatewayIntents', () {
    test('defaults and guest sets', () {
      expect(GatewayIntents.defaults(), contains(GatewayIntents.messages));
      expect(GatewayIntents.guest(), contains(GatewayIntents.members));
    });
  });

  group('AccordPermission', () {
    test('has respects administrator', () {
      expect(AccordPermission.has(['administrator'], 'ban_members'), isTrue);
      expect(AccordPermission.has(['send_messages'], 'ban_members'), isFalse);
      expect(AccordPermission.has(['ban_members'], 'ban_members'), isTrue);
    });

    test('all contains 40 entries and descriptions exist', () {
      expect(AccordPermission.all(), hasLength(40));
      expect(AccordPermission.description('administrator'), isNotEmpty);
      expect(AccordPermission.description('not_a_perm'), isEmpty);
    });
  });
}
