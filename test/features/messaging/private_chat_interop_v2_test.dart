// Shared Dart/Rust vector for private chat encryption v2.
//
// Regenerate with:
//   E2EE_WRITE_FIXTURE=1 flutter test test/features/messaging/private_chat_interop_v2_test.dart
// The seeds below are PUBLIC TEST KEYS ONLY. The accordserver suite verifies
// the same file (certificates, sender-device signature, recipient set).
import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'e2ee_test_server.dart' show MemoryKeys, verifySignature;

const _fixturePath = 'test/fixtures/e2ee_v2.json';
const _expected = 'interoperable v2 secret 🔐';

/// Seed byte for each 32-byte private key, and the device id byte.
const _seeds = {
  'alice': {
    'account_exchange': 7,
    'account_signing': 7,
    'device_exchange': 33,
    'device_signing': 34,
    'device_id': 161,
  },
  'bob': {
    'account_exchange': 8,
    'account_signing': 8,
    'device_exchange': 49,
    'device_signing': 50,
    'device_id': 177,
  },
};

String _seed(int byte) => base64Encode(List.filled(32, byte));
String _deviceId(String user) => base64Url
    .encode(List.filled(16, _seeds[user]!['device_id']!))
    .replaceAll('=', '');
String _scope(String user) =>
    base64Url.encode(utf8.encode('https://chat.test/api/v1|$user'));

Future<String> _x(int byte) async => base64Encode(
  (await (await X25519().newKeyPairFromSeed(
    List.filled(32, byte),
  )).extractPublicKey()).bytes,
);
Future<String> _s(int byte) async => base64Encode(
  (await (await Ed25519().newKeyPairFromSeed(
    List.filled(32, byte),
  )).extractPublicKey()).bytes,
);

/// Public keys, device certificate and participant row of [user].
Future<Map<String, dynamic>> _participant(String user) async {
  final seeds = _seeds[user]!;
  final account = {
    'exchange_key': await _x(seeds['account_exchange']!),
    'signing_key': await _s(seeds['account_signing']!),
  };
  final device = {
    'device_id': _deviceId(user),
    'exchange_key': await _x(seeds['device_exchange']!),
    'signing_key': await _s(seeds['device_signing']!),
  };
  final certificate = await Ed25519().sign(
    utf8.encode(
      jsonEncode([
        'daccord-e2ee-device-v2',
        user,
        1,
        device['device_id'],
        device['exchange_key'],
        device['signing_key'],
      ]),
    ),
    keyPair: await Ed25519().newKeyPairFromSeed(
      List.filled(32, seeds['account_signing']!),
    ),
  );
  return {
    'user_context': user,
    'account': account,
    'devices': [
      {
        ...device,
        'certificate': base64Encode(certificate.bytes),
        'account_version': 1,
      },
    ],
  };
}

/// A vault holding [user]'s keyring and (optionally) its fixture device.
MemoryKeys _store(String user, {bool withDevice = true}) {
  final seeds = _seeds[user]!;
  final store = MemoryKeys();
  store.values['e2ee.v2.${_scope(user)}.keyring'] = jsonEncode({
    'accounts': [
      {
        'version': 1,
        'exchange_private': _seed(seeds['account_exchange']!),
        'signing_private': _seed(seeds['account_signing']!),
      },
    ],
  });
  if (withDevice) {
    store.values['e2ee.v2.${_scope(user)}.device'] = jsonEncode({
      'device_id': _deviceId(user),
      'exchange_private': _seed(seeds['device_exchange']!),
      'signing_private': _seed(seeds['device_signing']!),
    });
  }
  return store;
}

/// A client for [user] against a server described by [participants].
AccordClient _client(
  String user,
  List<Map<String, dynamic>> participants,
  MemoryKeys store,
) {
  final self = participants.firstWhere((p) => p['user_context'] == user);
  return AccordClient(
    token: user,
    tokenType: 'Bearer',
    baseUrl: 'https://chat.test',
    encryptionUserId: user,
    encryptionStore: store,
    httpClient: MockClient((r) async {
      final path = r.url.path;
      final Object? data;
      if (path.endsWith('/users/@me/encryption')) {
        data = {
          'user_context': user,
          'account': {'version': 1, ...self['account'] as Map},
          'successions': [
            {
              'version': 1,
              ...self['account'] as Map,
              'signature': null,
              'back_signature': null,
            },
          ],
          'devices': [],
        };
      } else if (path.contains('/users/@me/encryption/devices/')) {
        data = {...jsonDecode(r.body) as Map, 'status': 'active'};
      } else {
        data = {
          'channel_id': 'chat',
          'self_user_id': user,
          'participants': [
            for (final p in participants)
              {
                'user_id': p['user_context'],
                'wire_user_id': p['user_context'],
                'current': true,
                'identity': p['account'],
                'account_version': 1,
                'successions': [
                  {
                    'version': 1,
                    ...p['account'] as Map,
                    'signature': null,
                    'back_signature': null,
                  },
                ],
                'devices': [
                  for (final d in p['devices'] as List)
                    {...d as Map, 'revoked': false},
                ],
              },
          ],
        };
      }
      return http.Response(jsonEncode({'data': data}), 200);
    }),
  );
}

void main() {
  test(
    'generates the shared v2 fixture',
    () async {
      final participants = [
        await _participant('alice'),
        await _participant('bob'),
      ];
      final alice = _client('alice', participants, _store('alice'));
      try {
        final sent = await alice.encryption!.encrypt('chat', {
          'content': _expected,
        });
        final fixture = {
          'note':
              'PUBLIC TEST KEYS ONLY. Never use these seeds in an account. '
              'Each private key is 32 copies of its seed byte; device ids are '
              '16 copies of device_id, base64url without padding. Generated by '
              'test/features/messaging/private_chat_interop_v2_test.dart.',
          'private_seeds': _seeds,
          'user_context': 'alice',
          'channel_context': 'chat',
          'account': participants.first['account'],
          'devices': participants.first['devices'],
          'participants': participants,
          'content': sent.data['content'],
          'expected_content': _expected,
        };
        await File(_fixturePath).writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(fixture)}\n',
        );
      } finally {
        await alice.dispose();
      }
    },
    skip: Platform.environment['E2EE_WRITE_FIXTURE'] == null
        ? 'Set E2EE_WRITE_FIXTURE=1 to regenerate $_fixturePath'
        : false,
  );

  test(
    'shared v2 fixture verifies and decrypts by device and by account key',
    () async {
      final fixture =
          jsonDecode(await File(_fixturePath).readAsString())
              as Map<String, dynamic>;
      final participants = [
        for (final p in fixture['participants'] as List)
          (p as Map).cast<String, dynamic>(),
      ];
      // The fixture's keys are the ones its seeds produce.
      for (final user in ['alice', 'bob']) {
        expect(
          jsonEncode(participants.firstWhere((p) => p['user_context'] == user)),
          jsonEncode(await _participant(user)),
        );
      }
      final content = fixture['content'] as String;
      expect(content, startsWith(PrivateChatEncryption.prefixV2));
      final envelope =
          jsonDecode(content.substring(PrivateChatEncryption.prefixV2.length))
              as Map;
      expect(envelope.keys, ['payload', 'signature']);
      final p = envelope['payload'] as List;
      expect(p, hasLength(11));
      expect(p.sublist(0, 4), [2, 'chat', 'alice', _deviceId('alice')]);
      expect(p[10], 1); // R5: the sender's signed account version.
      final device = (fixture['devices'] as List).single as Map;
      expect(
        await verifySignature(
          utf8.encode(jsonEncode(p)),
          envelope['signature'],
          device['signing_key'],
        ),
        true,
      );
      expect(
        await verifySignature(
          utf8.encode(
            jsonEncode([
              'daccord-e2ee-device-v2',
              'alice',
              device['account_version'],
              device['device_id'],
              device['exchange_key'],
              device['signing_key'],
            ]),
          ),
          device['certificate'],
          (fixture['account'] as Map)['signing_key'],
        ),
        true,
      );
      // Recipients: account + each active device per participant, sorted.
      final expected = <List<String>>[];
      for (final participant in participants) {
        final user = participant['user_context'] as String;
        expected.add([
          user,
          'account',
          (participant['account'] as Map)['exchange_key'] as String,
        ]);
        for (final d in participant['devices'] as List) {
          expected.add([
            user,
            (d as Map)['device_id'] as String,
            d['exchange_key'] as String,
          ]);
        }
      }
      expected.sort((a, b) {
        final c = a[0].compareTo(b[0]);
        return c != 0 ? c : a[1].compareTo(b[1]);
      });
      expect([
        for (final r in p[9] as List) (r as List).sublist(0, 3),
      ], expected);

      // Bob's fixture device unwraps its own entry; a second device that
      // holds only bob's keyring unwraps the account entry.
      for (final store in [_store('bob'), _store('bob', withDevice: false)]) {
        final bob = _client('bob', participants, store);
        try {
          final message = await bob.encryption!.decrypt(
            AccordMessage(
              id: 'fixture',
              channelId: 'chat',
              authorId: 'alice',
              content: content,
            ),
          );
          expect(message.encryptionError, isNull);
          expect(message.content, fixture['expected_content']);
        } finally {
          await bob.dispose();
        }
      }
    },
  );
}
