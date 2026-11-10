import 'dart:convert';
import 'dart:typed_data';
import 'package:accordkit/accordkit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_test_server.dart';

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
      // v2: an account entry plus one per active device, for every current
      // participant, sorted by user then key id.
      final recipients = [
        for (final r in payload[9] as List) [(r as List)[0], r[1]],
      ];
      expect(recipients.map((r) => r[0]), [
        'alice',
        'alice',
        'charlie',
        'charlie',
      ]);
      expect(recipients, [
        for (final r in h.server.expectedRecipients()) [r[0], r[1]],
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
      (envelope['payload'] as List)[8] = base64Encode(List.filled(40, 42));
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
      final alice = h.server.users['alice']!.account!;
      h.server.users['bob']!.account!
        ..exchangeKey = alice.exchangeKey
        ..signingKey = alice.signingKey;
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
  test(
    'a second device registers once as pending and reports it per message',
    () async {
      // v2: a device without the keyring waits for approval instead of being
      // refused (v1 answered 409 and the device showed the conflict text).
      final sent = await h.e('alice').encrypt('chat', {
        'content': 'phone cannot read this',
      });
      final stored = sent.data['content'] as String;
      h.server.history.addAll([
        for (var i = 0; i < 3; i++)
          {
            'id': 'm$i',
            'channel_id': 'chat',
            'author_id': 'alice',
            'content': stored,
          },
      ]);
      final phone = h.client('bob-phone', user: 'bob');
      // History pages, previews and gateway decrypts must not re-register.
      for (var page = 0; page < 3; page++) {
        final result = await phone.messages.list('chat');
        expect(result.ok, true);
        final messages = (result.data as List).cast<AccordMessage>();
        expect(
          messages.map((m) => m.encryptionError),
          everyElement(PrivateChatEncryption.pendingMessage),
        );
      }
      await phone.encryption!.decrypt(h.wire(stored));
      expect(phone.encryption!.setup, PrivateChatSetup.pending);
      expect(
        h.server.paths.where(
          (p) => p.startsWith('PUT /users/@me/encryption/devices/'),
        ),
        hasLength(3), // alice, bob, bob-phone: once each
      );
    },
  );
  test('a transient registration failure is retried', () async {
    h.server.failures = 1;
    final client = h.client('flaky');
    await expectLater(
      client.encryption!.initialize(),
      throwsA(isA<EncryptionException>()),
    );
    expect(client.encryption!.setup, PrivateChatSetup.unknown);
    await client.encryption!.initialize();
    expect(client.encryption!.setup, PrivateChatSetup.active);
    expect(h.server.users['flaky']!.account, isNotNull);
  });
  test('vault failure prevents public key registration', () async {
    final store = MemoryKeys()..failWrites = true;
    final client = h.client('unpersisted', store: store);
    await expectLater(client.encryption!.initialize(), throwsStateError);
    expect(h.server.users['unpersisted']?.account, isNull);
    expect(h.server.users['unpersisted']?.devices ?? const {}, isEmpty);
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
      final second = h.client('alice-2', user: 'alice');
      // v2: the second device waits for approval instead of failing.
      await second.encryption!.initialize();
      expect(second.encryption!.setup, PrivateChatSetup.pending);
      await expectLater(
        second.encryption!.importBackup(backup, 'wrong passphrase'),
        throwsA(anything),
      );
      await second.encryption!.importBackup(backup, password);
      expect(second.encryption!.setup, PrivateChatSetup.active);
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
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
