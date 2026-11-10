import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_test_server.dart';

/// Version-1 account secrets of [name]'s keyring, as a v1 client stored them.
Map<String, String> v1Secret(Harness h, String name, {String? user}) {
  final ring =
      jsonDecode(
            h.stores[name]!.values['e2ee.v2.${scopeOf(user ?? name)}.keyring']!,
          )
          as Map;
  final v1 = (ring['accounts'] as List).first as Map;
  return {
    'exchange_private': v1['exchange_private'] as String,
    'signing_private': v1['signing_private'] as String,
  };
}

Future<String> deviceIdOf(PrivateChatEncryption e) async =>
    (await e.listDevices()).firstWhere((d) => d.current).deviceId;

Future<String> send(PrivateChatEncryption e, String text) async =>
    (await e.encrypt('chat', {'content': text})).data['content'] as String;

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() async => h.close());

  test(
    'a v1 vault identity becomes account version 1 with the same fingerprint',
    () async {
      final x = await X25519().newKeyPairFromSeed(List.filled(32, 3));
      final s = await Ed25519().newKeyPairFromSeed(List.filled(32, 4));
      final identity = {
        'exchange_key': base64Encode((await x.extractPublicKey()).bytes),
        'signing_key': base64Encode((await s.extractPublicKey()).bytes),
      };
      final secret = jsonEncode({
        'exchange_private': base64Encode(List.filled(32, 3)),
        'signing_private': base64Encode(List.filled(32, 4)),
      });
      final store = MemoryKeys()
        ..values['e2ee.v1.${scopeOf('alice')}.identity'] = secret;
      h.server
          .user('alice')
          .accounts
          .add(
            FakeAccount(1, identity['exchange_key']!, identity['signing_key']!),
          );
      final alice = h.client('alice', store: store).encryption!;
      await h.e('bob').initialize();
      final before = await encryptV1(
        author: 'bob',
        authorSecret: v1Secret(h, 'bob'),
        recipients: {
          'alice': identity['exchange_key']!,
          'bob': h.server.users['bob']!.account!.exchangeKey,
        },
        content: 'sent by a v1 client',
      );

      await alice.initialize();
      expect(alice.setup, PrivateChatSetup.active);
      // The v1 entry stays; the keyring holds the same seeds as version 1.
      expect(store.values['e2ee.v1.${scopeOf('alice')}.identity'], secret);
      final ring =
          jsonDecode(store.values['e2ee.v2.${scopeOf('alice')}.keyring']!)
              as Map;
      expect(ring['accounts'], [
        {'version': 1, ...jsonDecode(secret) as Map},
      ]);
      expect(h.server.users['alice']!.accounts, hasLength(1));
      final device = h.server.users['alice']!.devices.values.single;
      expect(device['status'], 'active');
      expect(device['account_version'], 1);

      final keys = await alice.participants('chat');
      expect(
        await alice.fingerprint(keys['alice']!),
        await alice.fingerprint(identity),
      );
      final history = await alice.decrypt(h.wire(before, author: 'bob'));
      expect(history.encryptionError, isNull);
      expect(history.content, 'sent by a v1 client');
      // New messages are v2 and readable by the v1-migrated contact.
      final next = await send(alice, 'now v2');
      expect(next, startsWith(PrivateChatEncryption.prefixV2));
      expect((await h.e('bob').decrypt(h.wire(next))).content, 'now v2');
    },
  );

  test(
    'a second device is pending until approved by link code, then reads v1 and v2 history',
    () async {
      await h.setup();
      final alice = h.e('alice');
      expect(alice.setup, PrivateChatSetup.active);
      expect(
        h.server.users['alice']!.devices.values.single['status'],
        'active',
      );
      final v1 = await encryptV1(
        author: 'bob',
        authorSecret: v1Secret(h, 'bob'),
        recipients: {
          'alice': h.server.users['alice']!.account!.exchangeKey,
          'bob': h.server.users['bob']!.account!.exchangeKey,
        },
        content: 'v1 history',
      );
      final v2 = await send(alice, 'v2 history');

      final phone = h.client('alice-phone', user: 'alice').encryption!;
      final setups = <PrivateChatSetup>[];
      phone.setupChanges.listen(setups.add);
      await phone.initialize();
      expect(phone.setup, PrivateChatSetup.pending);
      final locked = await phone.decrypt(h.wire(v2));
      expect(locked.encryptionError, PrivateChatEncryption.pendingMessage);
      final blocked = await h.client('alice-phone').messages.create('chat', {
        'content': 'not yet',
      });
      expect(blocked.ok, false);
      expect(blocked.error!.message, PrivateChatEncryption.pendingMessage);

      // The other device hears about it from the gateway.
      final event = h.server.events.last;
      expect(event.type, 'encryption.device_pending');
      final prompted = alice.onDevicePending.first;
      alice.handleGatewayEvent(event.type, event.data);
      final request = await prompted;
      expect(request.name, 'Device alice-phone');
      expect(request.status, EncryptionDeviceStatus.pending);
      final listed = await alice.listDevices();
      expect(listed, hasLength(2));
      expect(listed.where((d) => d.current), hasLength(1));
      expect(listed.firstWhere((d) => d.current).name, 'Device alice');

      await expectLater(
        alice.approveDevice(request.deviceId),
        throwsA(isA<EncryptionException>()),
      );
      final code = await phone.linkCode();
      expect(code, matches(RegExp(r'^\d{4} \d{4} \d{4} \d{4}$')));
      expect(await alice.linkCodeFor(request), code);
      await alice.approveDevice(request.deviceId);
      expect(h.server.users['alice']!.packages.keys, [request.deviceId]);

      final update = h.server.events.last;
      expect(update.type, 'encryption.devices_update');
      final updated = phone.onDevicesUpdate.first;
      final active = phone.setupChanges.firstWhere(
        (s) => s == PrivateChatSetup.active,
      );
      phone.handleGatewayEvent(update.type, update.data);
      await updated;
      await active;
      expect(setups, [PrivateChatSetup.pending, PrivateChatSetup.active]);
      expect(h.server.users['alice']!.packages, isEmpty); // acknowledged
      expect(await phone.checkApproval(), true);

      expect(
        (await phone.decrypt(h.wire(v1, author: 'bob'))).content,
        'v1 history',
      );
      expect((await phone.decrypt(h.wire(v2))).content, 'v2 history');
      final fromBob = await send(h.e('bob'), 'to every device');
      expect(
        payloadOf(fromBob)[9].map((r) => (r as List)[1]),
        contains(request.deviceId),
      );
      expect(
        (await phone.decrypt(h.wire(fromBob, author: 'bob'))).content,
        'to every device',
      );
      final sent = await h.client('alice-phone').messages.create('chat', {
        'content': 'from my phone',
      });
      expect(sent.ok, true);
      expect(payloadOf(h.wireContent!)[3], request.deviceId);
      expect(
        (await h.e('bob').decrypt(h.wire(h.wireContent!))).content,
        'from my phone',
      );
    },
  );

  test('a key package for a substituted account key is rejected', () async {
    await h.setup();
    final alice = h.e('alice');
    // The server shows the phone a different account key: the codes differ.
    final fake = FakeAccount(
      1,
      base64Encode(List.filled(32, 9)),
      base64Encode(List.filled(32, 10)),
    );
    final real = h.server.users['alice']!.accounts.single;
    h.server.users['alice']!.accounts[0] = fake;
    final phone = h.client('alice-phone', user: 'alice').encryption!;
    await phone.initialize();
    final phoneCode = await phone.linkCode();
    h.server.users['alice']!.accounts[0] = real;
    final request = (await alice.listDevices()).firstWhere((d) => !d.current);
    expect(await alice.linkCodeFor(request), isNot(phoneCode));
    // Even if the user approves anyway, the phone refuses the package.
    await alice.approveDevice(request.deviceId);
    await expectLater(
      phone.checkApproval(),
      throwsA(isA<EncryptionException>()),
    );
    expect(phone.setup, PrivateChatSetup.pending);

    // A package forged with another keyring is refused as well.
    final attacker = jsonEncode({
      'accounts': [
        {
          'version': 1,
          'exchange_private': base64Encode(List.filled(32, 11)),
          'signing_private': base64Encode(List.filled(32, 12)),
        },
      ],
    });
    final tablet = h.client('alice-tablet', user: 'alice').encryption!;
    await tablet.initialize();
    final row = h.server.users['alice']!.devices.values.firstWhere(
      (d) => d['session'] == 'alice-tablet',
    );
    row['status'] = 'active';
    h.server.users['alice']!.packages[row['device_id']
        as String] = await sealPackage(
      user: 'alice',
      deviceId: row['device_id'] as String,
      deviceExchangeKey: row['exchange_key'] as String,
      keyringJson: attacker,
    );
    await expectLater(
      tablet.checkApproval(),
      throwsA(isA<EncryptionException>()),
    );
    expect(tablet.setup, PrivateChatSetup.pending);
  });

  test(
    'a declined device can ask again; active devices need rotation',
    () async {
      await h.setup();
      final alice = h.e('alice');
      final phone = h.client('alice-phone', user: 'alice').encryption!;
      await phone.initialize();
      final id = await deviceIdOf(phone);
      await alice.declineDevice(id);
      expect(h.server.users['alice']!.devices.containsKey(id), false);
      final asked = phone.setupChanges.first;
      expect(await phone.checkApproval(), false);
      expect(await asked, PrivateChatSetup.pending);
      expect(h.server.users['alice']!.devices[id]!['status'], 'pending');
      await expectLater(
        alice.declineDevice(await deviceIdOf(alice)),
        throwsA(isA<EncryptionException>()),
      );
    },
  );

  test(
    'v2 messages, files and edits reach every active device and account',
    () async {
      await h.setup();
      final phone = h.client('alice-phone', user: 'alice').encryption!;
      await phone.initialize();
      await h.approve('alice', 'alice-phone');
      h.client('bob-tablet', user: 'bob');
      await h.e('bob-tablet').initialize();
      await h.approve('bob', 'bob-tablet');

      final sent = await h.client('alice').messages.create('chat', {
        'content': 'everyone',
      });
      expect(sent.ok, true); // The server checked the exact recipient set.
      final recipients = [
        for (final r in payloadOf(h.wireContent!)[9] as List)
          [(r as List)[0], r[1]],
      ];
      final expected = [
        for (final r in h.server.expectedRecipients()) [r[0], r[1]],
      ];
      expect(recipients, expected);
      expect(recipients, hasLength(6));
      for (final user in ['alice', 'bob']) {
        expect(
          recipients.where((r) => r[0] == user).map((r) => r[1]),
          containsAll(['account']),
        );
        expect(recipients.where((r) => r[0] == user), hasLength(3));
      }
      for (final name in ['bob', 'bob-tablet', 'alice-phone']) {
        expect(
          (await h.e(name).decrypt(h.wire(h.wireContent!))).content,
          'everyone',
        );
      }

      final file = bytesOf('phone photo');
      final upload = await h
          .client('alice-phone')
          .messages
          .createWithAttachments(
            'chat',
            {'content': 'file'},
            [
              {
                'filename': 'photo.jpg',
                'content_type': 'image/jpeg',
                'content': file,
              },
            ],
          );
      expect(upload.ok, true);
      final attachment = AccordAttachment(
        id: 'file',
        filename: 'attachment-0.bin',
        url: '/cdn/attachments/file.bin',
        size: file.length + 28,
      );
      final received = await h
          .e('bob-tablet')
          .decrypt(h.wire(h.wireContent!, attachments: [attachment]));
      expect(received.encryptionError, isNull);
      expect(received.attachments.single.filename, 'photo.jpg');

      final edited = await h.client('alice-phone').messages.edit(
        'chat',
        'message',
        {'content': 'edited on phone'},
      );
      expect(edited.ok, true);
      expect(payloadOf(h.wireContent!)[6], 'message');
      final revised = await h
          .e('bob')
          .decrypt(h.wire(h.wireContent!, attachments: [attachment]));
      expect(revised.content, 'edited on phone');
      expect(revised.attachments.single.filename, 'photo.jpg'); // Kept.
      expect(
        revised.attachments.single.encryption!['key'],
        received.attachments.single.encryption!['key'],
      );
    },
  );

  test(
    'removing a device rotates the account key; contacts follow the succession',
    () async {
      await h.setup();
      for (final name in ['alice-phone', 'alice-tablet']) {
        await h.client(name, user: 'alice').encryption!.initialize();
        await h.approve('alice', name);
      }
      final laptop = h.e('alice');
      final phone = h.e('alice-phone');
      final tablet = h.e('alice-tablet');
      final bob = h.e('bob');
      final phoneId = await deviceIdOf(phone);
      final fromPhone = await send(phone, 'sent before removal');
      final phoneKeys = await phone.participants('chat');
      await bob.participants('chat'); // Pins alice at version 1.

      await laptop.removeDevices([phoneId]);
      final alice = h.server.users['alice']!;
      expect(alice.account!.version, 2);
      expect(alice.devices[phoneId]!['status'], 'revoked');
      expect(h.server.deletedSessions, contains('alice-phone'));
      expect(alice.packages.keys, [await deviceIdOf(tablet)]);
      expect(
        alice.devices.values
            .where((d) => d['status'] == 'active')
            .map((d) => d['account_version']),
        everyElement(2),
      );

      final after = await send(laptop, 'after removal');
      final ids = [for (final r in payloadOf(after)[9] as List) (r as List)[1]];
      expect(ids, isNot(contains(phoneId)));
      expect(
        (payloadOf(after)[9] as List).firstWhere(
          (r) => r[0] == 'alice' && r[1] == 'account',
        )[2],
        alice.account!.exchangeKey,
      );
      // The removed device has no key for it, even with its old discovery.
      final denied = await phone.decrypt(
        h.wire(after),
        participantKeys: phoneKeys,
      );
      expect(denied.encryptionError, isNotNull);
      expect(denied.content, isNot('after removal'));

      // The remaining device fetches the rotated keyring on demand.
      expect((await tablet.decrypt(h.wire(after))).content, 'after removal');
      expect(await tablet.checkApproval(), true);
      expect(alice.packages, isEmpty);

      // The contact accepts version 2 through the signed succession.
      expect((await bob.decrypt(h.wire(after))).content, 'after removal');
      final trust =
          jsonDecode(
                h.stores['bob']!.values['e2ee.v1.${scopeOf('bob')}.trust']!,
              )
              as Map;
      expect((trust['alice'] as Map)['version'], 2);
      expect((trust['alice'] as Map)['accounts'], hasLength(2));
      // The revoked device's history still verifies.
      expect(
        (await bob.decrypt(h.wire(fromPhone))).content,
        'sent before removal',
      );
      expect(
        (await laptop.decrypt(h.wire(fromPhone))).content,
        'sent before removal',
      );
      // Replies go to the new key and the remaining devices only.
      final reply = await h.client('bob').messages.create('chat', {
        'content': 'reply',
      });
      expect(reply.ok, true);
      expect(
        (await tablet.decrypt(h.wire(h.wireContent!, author: 'bob'))).content,
        'reply',
      );
      await expectLater(
        laptop.removeDevices([await deviceIdOf(laptop)]),
        throwsA(isA<EncryptionException>()),
      );
    },
  );

  test(
    'contacts that first see an account after a rotation verify old devices via version 1',
    () async {
      await h.setup();
      await h.e('charlie').initialize();
      h.current.add('charlie');
      await h.client('alice-phone', user: 'alice').encryption!.initialize();
      await h.approve('alice', 'alice-phone');
      final phone = h.e('alice-phone');
      // Neither bob nor charlie has looked at alice's keys yet.
      final fromPhone = await send(phone, 'before rotation');
      await h.e('alice').removeDevices([await deviceIdOf(phone)]);

      // Without the version-1 entry (older servers) the revoked phone's
      // certificate cannot be checked by a contact who pins version 2 now.
      h.server.legacySuccessions = true;
      final unknown = await h.e('bob').decrypt(h.wire(fromPhone));
      expect(unknown.encryptionError, contains('device is unavailable'));
      final trust =
          jsonDecode(
                h.stores['bob']!.values['e2ee.v1.${scopeOf('bob')}.trust']!,
              )
              as Map;
      expect((trust['alice'] as Map)['accounts'], hasLength(1));

      // With it, the pinned contact backfills version 1 (it links forward to
      // the pin) and a first-time contact trusts the listed chain.
      h.server.legacySuccessions = false;
      for (final name in ['bob', 'charlie']) {
        final old = await h.e(name).decrypt(h.wire(fromPhone));
        expect(old.encryptionError, isNull, reason: name);
        expect(old.content, 'before rotation');
      }
      final pinned =
          jsonDecode(
                h.stores['bob']!.values['e2ee.v1.${scopeOf('bob')}.trust']!,
              )
              as Map;
      expect((pinned['alice'] as Map)['version'], 2);
      expect((pinned['alice'] as Map)['accounts'], hasLength(2));

      // A forged version 1 that does not link to the pinned key is ignored,
      // and a changed pinned version still blocks.
      final real = h.server.users['alice']!.accounts.first;
      h.server.users['alice']!.accounts[0] = FakeAccount(
        1,
        base64Encode(List.filled(32, 41)),
        base64Encode(List.filled(32, 42)),
      );
      final dave = h.e('dave');
      await dave.initialize();
      h.server.legacySuccessions = true;
      await dave.participants('chat', requireReady: false); // Pins v2 only.
      h.server.legacySuccessions = false;
      await dave.participants('chat', requireReady: false);
      final daveTrust =
          jsonDecode(
                h.stores['dave']!.values['e2ee.v1.${scopeOf('dave')}.trust']!,
              )
              as Map;
      expect((daveTrust['alice'] as Map)['accounts'], hasLength(1));
      await expectLater(
        h.e('bob').participants('chat'),
        throwsA(isA<EncryptionException>()),
      );
      h.server.users['alice']!.accounts[0] = real;
      expect((await h.e('bob').participants('chat'))['alice']!['version'], 2);
    },
  );

  test(
    'a broken succession chain is blocked like an identity change',
    () async {
      await h.setup();
      final bob = h.e('bob');
      await bob.participants('chat'); // Pins alice at version 1.
      final forged = FakeAccount(
        2,
        base64Encode(List.filled(32, 21)),
        base64Encode(List.filled(32, 22)),
        base64Encode(List.filled(64, 1)),
      );
      h.server.users['alice']!.accounts.add(forged);
      await expectLater(
        bob.participants('chat'),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.message,
            'message',
            contains('changed'),
          ),
        ),
      );
      final refused = await h.client('bob').messages.create('chat', {
        'content': 'must not leak',
      });
      expect(refused.ok, false);
      expect(h.server.requests, isEmpty);
      // A missing link (version 3 without version 2) is blocked too.
      h.server.users['alice']!.accounts.removeLast();
      h.server.users['alice']!.accounts.add(
        FakeAccount(3, forged.exchangeKey, forged.signingKey, forged.signature),
      );
      await expectLater(
        bob.participants('chat'),
        throwsA(isA<EncryptionException>()),
      );
    },
  );

  test('backup v2 round-trips the keyring; v1 backups still import', () async {
    await h.setup();
    await h.client('alice-phone', user: 'alice').encryption!.initialize();
    await h.approve('alice', 'alice-phone');
    final beforeRotation = await send(h.e('bob'), 'version 1 era');
    await h.e('alice').removeDevices([await deviceIdOf(h.e('alice-phone'))]);
    final afterRotation = await send(h.e('bob'), 'version 2 era');

    const password = 'correct horse battery';
    final backup = await h.e('alice').exportBackup(password);
    expect(jsonDecode(backup)['version'], 2);
    final restored = h.client('alice-new', user: 'alice').encryption!;
    await restored.importBackup(backup, password);
    expect(restored.setup, PrivateChatSetup.active);
    for (final (message, text) in [
      (beforeRotation, 'version 1 era'),
      (afterRotation, 'version 2 era'),
    ]) {
      expect(
        (await restored.decrypt(h.wire(message, author: 'bob'))).content,
        text,
      );
    }

    // A v1 backup of an account that has since rotated is out of date.
    final stale = await v1Backup(
      scopeOf('alice'),
      jsonEncode(v1Secret(h, 'alice')),
      password,
    );
    await expectLater(
      h
          .client('alice-old', user: 'alice')
          .encryption!
          .importBackup(stale, password),
      throwsA(isA<EncryptionException>()),
    );

    // A v1 backup of an unrotated account restores it as version 1.
    await h.e('carol').initialize();
    final carolBackup = await v1Backup(
      scopeOf('carol'),
      jsonEncode(v1Secret(h, 'carol')),
      password,
    );
    final carol = h.client('carol-new', user: 'carol').encryption!;
    await carol.importBackup(carolBackup, password);
    expect(carol.setup, PrivateChatSetup.active);
    expect(
      h.server.users['carol']!.devices.values.map((d) => d['status']),
      everyElement('active'),
    );
  }, timeout: const Timeout(Duration(minutes: 5)));

  test(
    'a 409 for a stale recipient set refreshes discovery and retries once',
    () async {
      await h.setup();
      await h.e('charlie').initialize();
      h.server.beforeAdmit = () async => h.current.add('charlie');
      final sent = await h.client('alice').messages.create('chat', {
        'content': 'raced',
      });
      expect(sent.ok, true);
      expect(h.server.messageAttempts, 2);
      expect(
        (payloadOf(h.wireContent!)[9] as List).map((r) => (r as List)[0]),
        contains('charlie'),
      );
      expect(
        (await h.e('charlie').decrypt(h.wire(h.wireContent!))).content,
        'raced',
      );

      h.server.alwaysConflict = true;
      h.server.messageAttempts = 0;
      final refused = await h.client('alice').messages.create('chat', {
        'content': 'again',
      });
      expect(refused.ok, false);
      expect(refused.statusCode, 409);
      expect(h.server.messageAttempts, 2);
      h.server.messageAttempts = 0;
      final edit = await h.client('alice').messages.edit('chat', 'message', {
        'content': 'edit',
      });
      expect(edit.ok, false);
      expect(h.server.messageAttempts, 2);
    },
  );
}
