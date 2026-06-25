import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:test/test.dart';

void main() {
  group('AccordSnowflake', () {
    test('decodeTimestampMs of zero-low-bits id', () {
      final sf =
          AccordSnowflake.fromTimestampMs(AccordSnowflake.epochMs + 1000);
      expect(AccordSnowflake.decodeTimestampMs(sf),
          AccordSnowflake.epochMs + 1000);
    });

    test('decodeTimestamp returns seconds', () {
      final sf =
          AccordSnowflake.fromTimestampMs(AccordSnowflake.epochMs + 2000);
      expect(AccordSnowflake.decodeTimestamp(sf),
          (AccordSnowflake.epochMs + 2000) / 1000.0);
    });

    test('empty snowflake decodes to 0', () {
      expect(AccordSnowflake.decodeTimestampMs(''), 0);
    });

    test('decodeToDateTime is UTC', () {
      final sf = AccordSnowflake.fromTimestampMs(AccordSnowflake.epochMs);
      final dt = AccordSnowflake.decodeToDateTime(sf);
      expect(dt.isUtc, isTrue);
      expect(dt.millisecondsSinceEpoch, AccordSnowflake.epochMs);
    });

    test('generateNonce is numeric and unique-ish', () {
      final a = AccordSnowflake.generateNonce();
      expect(int.tryParse(a), isNotNull);
    });

    test('decodeTimestampMs tolerates qualified federation ids', () {
      final sf =
          AccordSnowflake.fromTimestampMs(AccordSnowflake.epochMs + 3000);
      // A qualified `<snowflake>@<domain>` decodes the same as the bare id.
      expect(AccordSnowflake.decodeTimestampMs('$sf@b.example'),
          AccordSnowflake.decodeTimestampMs(sf));
    });
  });

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

    test('default avatar and emoji', () {
      expect(AccordCDN.defaultAvatar(3, cdnUrl: 'https://cdn'),
          'https://cdn/embed/avatars/3.png');
      expect(AccordCDN.emoji('9', cdnUrl: 'https://cdn'),
          'https://cdn/emojis/9.png');
    });
  });

  group('GatewayIntents', () {
    test('all is union of privileged and unprivileged', () {
      expect(GatewayIntents.all().toSet(),
          {...GatewayIntents.unprivileged(), ...GatewayIntents.privileged()});
    });

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
