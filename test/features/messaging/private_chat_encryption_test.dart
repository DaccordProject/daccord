import 'dart:convert';
import 'dart:typed_data';
import 'package:accordkit/accordkit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemoryKeys implements EncryptionKeyStore {
  final Map<String, String> values = {};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('vault unavailable');
    values[key] = value;
  }
}

class Harness {
  final identities = <String, Map<String, dynamic>>{};
  final current = <String>['alice', 'bob'];
  final requests = <Map<String, dynamic>>[];
  final stores = <String, MemoryKeys>{};
  final clients = <String, AccordClient>{};
  String? wireContent;
  bool rejectDiscovery = false;
  final sealedFiles = <List<int>>[];
  AccordClient client(String id, {MemoryKeys? store}) => clients.putIfAbsent(
    id,
    () => AccordClient(
      token: id,
      tokenType: 'Bearer',
      baseUrl: 'https://chat.test',
      cdnUrl: 'https://chat.test/cdn',
      encryptionStore: store ?? stores.putIfAbsent(id, MemoryKeys.new),
      encryptionUserId: id,
      httpClient: MockClient((request) async {
        final path = request.url.path;
        final body = request.body.isEmpty
            ? null
            : request.headers['content-type']?.startsWith('multipart/') == true
            ? null
            : jsonDecode(request.body);
        if (path.endsWith('/users/@me/encryption')) {
          final existing = identities[id];
          if (existing != null && jsonEncode(existing) != jsonEncode(body))
            return http.Response(
              jsonEncode({
                'error': {'message': 'Import the existing identity backup.'},
              }),
              409,
            );
          identities[id] = (body as Map).cast<String, dynamic>();
          return _ok(body);
        }
        if (path.endsWith('/encryption')) {
          if (rejectDiscovery) return http.Response('{}', 503);
          return _ok({
            'channel_id': 'chat',
            'self_user_id': id,
            'participants': [
              for (final e in identities.entries)
                {
                  'user_id': e.key,
                  'wire_user_id': e.key,
                  'current': current.contains(e.key),
                  'identity': e.value,
                },
              for (final uid in current.where(
                (uid) => !identities.containsKey(uid),
              ))
                {
                  'user_id': uid,
                  'wire_user_id': uid,
                  'current': true,
                  'identity': null,
                },
            ],
          });
        }
        if (path.endsWith('/channels/chat'))
          return _ok({'id': 'chat', 'type': 'group_dm'});
        if (path.endsWith('/channels/public'))
          return _ok({'id': 'public', 'type': 'text', 'space_id': 'space'});
        if (path.contains('/cdn/'))
          return http.Response.bytes(sealedFiles.single, 200);
        if (path.contains('/messages')) {
          if (request.method == 'GET')
            return _ok({
              'id': 'message',
              'channel_id': 'chat',
              'author_id': 'alice',
              'content': wireContent,
            });
          if (body != null) {
            requests.add(Map<String, dynamic>.from(body as Map));
            wireContent = body['content'] as String;
            return _ok({
              'id': 'message',
              'channel_id': path.contains('public') ? 'public' : 'chat',
              'author_id': id,
              'content': wireContent,
              if (path.contains('public')) 'space_id': 'space',
            });
          }
        }
        throw StateError('Unexpected request: ${request.method} $path');
      }),
    ),
  );
  static http.Response _ok(Object? data) => http.Response(
    jsonEncode({'data': data}),
    200,
    headers: {'content-type': 'application/json'},
  );
  Future<void> setup() async {
    await client('alice').encryption!.initialize();
    await client('bob').encryption!.initialize();
  }

  AccordMessage wire(
    String content, {
    String author = 'alice',
    String channel = 'chat',
    String? reply,
    List<AccordAttachment>? attachments,
  }) => AccordMessage(
    id: 'message',
    channelId: channel,
    authorId: author,
    content: content,
    replyTo: reply,
    attachments: attachments,
  );
  Future<void> close() async {
    for (final c in clients.values) {
      await c.dispose();
    }
  }
}

void main() {
  late Harness h;
  setUp(() async {
    h = Harness();
    await h.setup();
  });
  tearDown(() async => h.close());
  test(
    'DM send, offline history, sender echo and edit decrypt; server sees ciphertext',
    () async {
      final sent = await h.client('alice').messages.create('chat', {
        'content': 'secret 🔐\nhttps://private.example',
      });
      expect(sent.ok, true);
      expect(
        (sent.data as AccordMessage).content,
        'secret 🔐\nhttps://private.example',
      );
      final stored = h.requests.single['content'] as String;
      expect(stored, startsWith(PrivateChatEncryption.prefix));
      expect(stored, isNot(contains('secret')));
      expect(stored, isNot(contains('private.example')));
      final bob = await h.client('bob').encryption!.decrypt(h.wire(stored));
      expect(bob.content, 'secret 🔐\nhttps://private.example');
      expect(bob.encryptionError, isNull);
      expect(bob.toJson()['content'], stored); // Never serialize cleartext.
      final edited = await h.client('alice').messages.edit('chat', 'message', {
        'content': 'edited secret',
      });
      expect(edited.ok, true);
      expect((edited.data as AccordMessage).content, 'edited secret');
      final after = await h
          .client('bob')
          .encryption!
          .decrypt(h.wire(h.wireContent!));
      expect(after.content, 'edited secret');
    },
  );
  test('channel messages remain unchanged', () async {
    final sent = await h.client('alice').messages.create('public', {
      'content': 'public text',
    });
    expect(sent.ok, true);
    expect(h.requests.single['content'], 'public text');
    expect((sent.data as AccordMessage).isEncrypted, false);
  });
  test(
    'new member can decrypt new messages, removed member cannot; old history stays readable',
    () async {
      final first = await h.client('alice').encryption!.encrypt('chat', {
        'content': 'before join',
      });
      await h.client('charlie').encryption!.initialize();
      h.current.add('charlie');
      final second = await h.client('alice').encryption!.encrypt('chat', {
        'content': 'after join',
      });
      final old = await h
          .client('charlie')
          .encryption!
          .decrypt(h.wire(first.data['content'] as String));
      expect(old.encryptionError, isNotNull);
      final joined = await h
          .client('charlie')
          .encryption!
          .decrypt(h.wire(second.data['content'] as String));
      expect(joined.content, 'after join');
      h.current.remove('bob');
      final third = await h.client('alice').encryption!.encrypt('chat', {
        'content': 'after removal',
      });
      final payload =
          (jsonDecode(
                    (third.data['content'] as String).substring(
                      PrivateChatEncryption.prefix.length,
                    ),
                  )
                  as Map)['payload']
              as List;
      expect((payload[8] as List).map((r) => (r as List)[0]), [
        'alice',
        'charlie',
      ]);
      final excluded = await h
          .client('bob')
          .encryption!
          .decrypt(h.wire(third.data['content'] as String));
      expect(excluded.encryptionError, isNotNull);
      final history = await h
          .client('charlie')
          .encryption!
          .decrypt(h.wire(second.data['content'] as String));
      expect(history.content, 'after join');
    },
  );
  test(
    'tampered ciphertext, forged sender and moved chat fail authentication',
    () async {
      final sent = await h.client('alice').encryption!.encrypt('chat', {
        'content': 'private',
      });
      final stored = sent.data['content'] as String;
      final envelope =
          jsonDecode(stored.substring(PrivateChatEncryption.prefix.length))
              as Map;
      (envelope['payload'] as List)[7] = base64Encode(List.filled(40, 42));
      final tampered = await h
          .client('bob')
          .encryption!
          .decrypt(
            h.wire('${PrivateChatEncryption.prefix}${jsonEncode(envelope)}'),
          );
      expect(tampered.encryptionError, isNotNull);
      expect(tampered.content, isNot('private'));
      expect(
        (await h
                .client('bob')
                .encryption!
                .decrypt(h.wire(stored, author: 'bob')))
            .encryptionError,
        isNotNull,
      );
      expect(
        (await h
                .client('bob')
                .encryption!
                .decrypt(h.wire(stored, channel: 'other')))
            .encryptionError,
        isNotNull,
      );
    },
  );
  test(
    'unavailable keys and key substitutions never transmit plaintext',
    () async {
      h.current.add('not-upgraded');
      final missing = await h.client('alice').messages.create('chat', {
        'content': 'must not leak',
      });
      expect(missing.ok, false);
      expect(h.requests, isEmpty);
      h.current.remove('not-upgraded');
      await h.client('alice').encryption!.participants('chat');
      h.identities['bob'] = h.identities['alice']!;
      final changed = await h.client('alice').messages.create('chat', {
        'content': 'must not leak',
      });
      expect(changed.ok, false);
      expect(changed.error!.message, contains('changed'));
      expect(h.requests, isEmpty);
      h.rejectDiscovery = true;
      expect(
        (await h.client('alice').messages.create('chat', {
          'content': 'must not leak',
        })).ok,
        false,
      );
      expect(h.requests, isEmpty);
    },
  );
  test(
    'encrypted files hide names and bytes, authenticate on download, and survive edits',
    () async {
      final plain = Uint8List.fromList(utf8.encode('confidential file bytes'));
      final encrypted = await h
          .client('alice')
          .encryption!
          .encrypt(
            'chat',
            {'content': 'file'},
            files: [
              {
                'filename': 'private-name.txt',
                'content_type': 'text/plain',
                'content': plain,
              },
            ],
          );
      expect(encrypted.files.single['filename'], 'attachment-0.bin');
      expect(
        encrypted.files.single['content_type'],
        'application/octet-stream',
      );
      final bytes = encrypted.files.single['content'] as Uint8List;
      h.sealedFiles.add(bytes);
      expect(bytes, isNot(equals(plain)));
      final content = encrypted.data['content'] as String;
      expect(content, isNot(contains('private-name')));
      final message = await h
          .client('bob')
          .encryption!
          .decrypt(
            h.wire(
              content,
              attachments: [
                AccordAttachment(
                  id: 'file',
                  filename: 'attachment-0.bin',
                  url: '/cdn/attachments/file.bin',
                  size: bytes.length,
                ),
              ],
            ),
          );
      expect(message.encryptionError, isNull);
      final file = message.attachments.single;
      expect(file.filename, 'private-name.txt');
      expect(
        await h
            .client('bob')
            .encryption!
            .downloadAttachment(file, cdnUrl: 'https://chat.test/cdn'),
        plain,
      );
      final tampered = Uint8List.fromList(bytes)..[12] ^= 1;
      await expectLater(
        h.client('bob').encryption!.decryptAttachment(file, tampered),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final edited = await h
          .client('alice')
          .encryption!
          .encrypt(
            'chat',
            {'content': 'edit file'},
            editId: 'message',
            previousPayload: message.privatePayload,
          );
      final next = await h
          .client('bob')
          .encryption!
          .decrypt(
            h.wire(
              edited.data['content'] as String,
              attachments: [
                AccordAttachment(
                  id: 'file',
                  url: '/cdn/attachments/file.bin',
                  size: bytes.length,
                ),
              ],
            ),
          );
      expect(next.attachments.single.filename, 'private-name.txt');
      expect(
        await h
            .client('bob')
            .encryption!
            .decryptAttachment(next.attachments.single, bytes),
        plain,
      );
    },
  );
  test('vault failure prevents public key registration', () async {
    final store = MemoryKeys()..failWrites = true;
    final client = h.client('unpersisted', store: store);
    await expectLater(client.encryption!.initialize(), throwsStateError);
    expect(h.identities.containsKey('unpersisted'), false);
  });
  test(
    'concurrent gateway consumers receive independent decrypted models',
    () async {
      final encrypted = await h.client('alice').encryption!.encrypt('chat', {
        'content': 'broadcast secret',
      });
      final raw = h.wire(encrypted.data['content'] as String);
      final models = await Future.wait([
        h.client('alice').encryption!.decrypt(raw),
        h.client('bob').encryption!.decrypt(raw),
      ]);
      expect(models.map((m) => m.content), [
        'broadcast secret',
        'broadcast secret',
      ]);
      expect(raw.content, startsWith(PrivateChatEncryption.prefix));
      expect(identical(models.first, models.last), false);
    },
  );
  test(
    'identity backup restores another device and rejects a wrong password/account',
    () async {
      const password = 'test backup passphrase';
      final backup = await h.client('alice').encryption!.exportBackup(password);
      expect(backup, isNot(contains('exchange_private')));
      final second = AccordClient(
        token: 'alice',
        tokenType: 'Bearer',
        baseUrl: 'https://chat.test',
        encryptionUserId: 'alice',
        encryptionStore: MemoryKeys(),
        httpClient: MockClient((r) async {
          if (r.url.path.endsWith('/users/@me/encryption')) {
            final key = jsonDecode(r.body);
            return jsonEncode(key) == jsonEncode(h.identities['alice'])
                ? Harness._ok(key)
                : http.Response('{}', 409);
          }
          return Harness._ok({
            'channel_id': 'chat',
            'self_user_id': 'alice',
            'participants': [
              for (final e in h.identities.entries)
                {
                  'user_id': e.key,
                  'wire_user_id': e.key,
                  'current': true,
                  'identity': e.value,
                },
            ],
          });
        }),
      );
      try {
        await expectLater(
          second.encryption!.initialize(),
          throwsA(isA<EncryptionException>()),
        );
        await expectLater(
          second.encryption!.importBackup(backup, 'wrong passphrase'),
          throwsA(anything),
        );
        await second.encryption!.importBackup(backup, password);
        final before = await h.client('bob').encryption!.encrypt('chat', {
          'content': 'history on new device',
        });
        expect(
          (await second.encryption!.decrypt(
            h.wire(before.data['content'] as String, author: 'bob'),
          )).content,
          'history on new device',
        );
        await expectLater(
          h.client('bob').encryption!.importBackup(backup, password),
          throwsA(isA<EncryptionException>()),
        );
      } finally {
        await second.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
