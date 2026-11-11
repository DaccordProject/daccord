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
      final approved = phone.setupChanges.firstWhere(
        (s) => s == PrivateChatSetup.approved,
      );
      phone.handleGatewayEvent(update.type, update.data);
      await updated;
      await approved;
      expect(h.server.users['alice']!.packages, isEmpty); // acknowledged
      // R1: nothing is readable until the user confirms on this device too.
      expect(
        (await phone.decrypt(h.wire(v2))).encryptionError,
        PrivateChatEncryption.pendingMessage,
      );
      expect(await phone.checkApproval(), false);
      await phone.confirmApproval();
      await Future<void>.delayed(Duration.zero); // Deliver the broadcast.
      expect(setups, [
        PrivateChatSetup.pending,
        PrivateChatSetup.approved,
        PrivateChatSetup.active,
      ]);
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

  test(
    'finding 1: a new device never trusts a server-chosen account key without its user',
    () async {
      await h.setup();
      final alice = h.e('alice');
      // The server shows the new device an account key it controls.
      final attacker = await SeededAccount(1, 9, 10).init();
      h.server.accountOverride['alice-phone'] = attacker.fake;
      final phone = h.client('alice-phone', user: 'alice').encryption!;
      await phone.initialize();
      expect(phone.setup, PrivateChatSetup.pending);
      final phoneCode = await phone.linkCode();
      final request = (await alice.listDevices()).firstWhere((d) => !d.current);
      expect(await alice.linkCodeFor(request), isNot(phoneCode));
      // Even if the user approves anyway, the real keyring does not match
      // the key behind the phone's code: the package is refused.
      await alice.approveDevice(request.deviceId);
      expect(await phone.checkApproval(), false);
      expect(phone.setup, PrivateChatSetup.pending);

      // A server-made package for its own key is only staged: the device is
      // "approved" but stays unusable until its user confirms the codes.
      h.server.users['alice']!.packages[request.deviceId] = await sealPackage(
        user: 'alice',
        deviceId: request.deviceId,
        deviceExchangeKey: request.exchangeKey,
        keyringJson: attacker.keyringJson,
      );
      expect(await phone.checkApproval(), false);
      expect(phone.setup, PrivateChatSetup.approved);
      final sent = await alice.encrypt('chat', {'content': 'secret'});
      expect(
        (await phone.decrypt(
          h.wire(sent.data['content'] as String),
        )).encryptionError,
        PrivateChatEncryption.pendingMessage,
      );
      // The codes differed, so the user rejects: a new device, a new code.
      final again = phone.setupChanges.first;
      await phone.rejectApproval();
      expect(await again, PrivateChatSetup.pending);
      expect(phone.setup, PrivateChatSetup.pending);
      expect(await phone.linkCode(), isNot(phoneCode));
      expect(
        h.stores['alice-phone']!.values['e2ee.v2.${scopeOf('alice')}.approval'],
        '',
      );
      expect(
        h.stores['alice-phone']!.values['e2ee.v2.${scopeOf('alice')}.keyring'],
        isNull,
      );
    },
  );

  test(
    'finding 1: an active device never adopts a server-substituted account key',
    () async {
      await h.setup();
      final keyring =
          h.stores['alice']!.values['e2ee.v2.${scopeOf('alice')}.keyring'];
      // The server swaps in its own key (same version, then a "rotation"
      // without a valid succession) and seals that keyring to the device.
      final attacker = await SeededAccount(1, 9, 10).init();
      final alice = h.server.users['alice']!;
      final real = alice.accounts.single;
      alice.accounts[0] = attacker.fake;
      final id = alice.devices.keys.single;
      alice.packages[id] = await sealPackage(
        user: 'alice',
        deviceId: id,
        deviceExchangeKey: alice.devices[id]!['exchange_key'] as String,
        keyringJson: attacker.keyringJson,
      );
      expect(await h.e('alice').checkApproval(), false);
      expect(h.e('alice').setup, PrivateChatSetup.blocked);
      final restarted = await h.restart('alice');
      expect(restarted.setup, PrivateChatSetup.blocked); // Never pending.
      expect(
        h.stores['alice']!.values['e2ee.v2.${scopeOf('alice')}.keyring'],
        keyring,
      );
      final forged2 = await SeededAccount(2, 11, 12).init();
      alice.accounts[0] = real;
      alice.accounts.add(
        forged2.fake..signature = base64Encode(List.filled(64, 1)),
      );
      expect(await restarted.checkApproval(), false);
      expect(restarted.setup, PrivateChatSetup.blocked);
      await expectLater(
        restarted.encrypt('chat', {'content': 'x'}),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.message,
            'message',
            PrivateChatEncryption.blockedMessage,
          ),
        ),
      );
      // Once the server shows the real key again, the device recovers.
      alice.accounts.removeLast();
      expect(await restarted.checkApproval(), true);
    },
  );

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
      // (R5: its signed account version 1 is not verifiable for this pin.)
      expect(unknown.encryptionError, contains('could not be verified'));
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

  /// laptop ("alice") + approved phone; returns the phone's device id.
  Future<String> withPhone() async {
    await h.setup();
    await h.client('alice-phone', user: 'alice').encryption!.initialize();
    await h.approve('alice', 'alice-phone');
    return deviceIdOf(h.e('alice-phone'));
  }

  test(
    'finding 2: an active device never falls back to an older own account version',
    () async {
      final phoneId = await withPhone();
      final laptop = h.e('alice');
      final alice = h.server.users['alice']!;
      final saved = {
        for (final e in alice.devices.entries)
          e.key: Map<String, dynamic>.from(e.value),
      };
      await laptop.removeDevices([phoneId]);
      // The server rolls back: version 1 is current again and the removed
      // phone is active with its old certificate.
      alice.accounts.removeLast();
      alice.revoked.remove(phoneId);
      alice.devices
        ..clear()
        ..addAll(saved);
      h.server.deletedSessions.remove('alice-phone');
      final sent = await h.client('alice').messages.create('chat', {
        'content': 'must not reach the removed phone',
      });
      expect(sent.ok, false);
      expect(sent.error!.message, PrivateChatEncryption.blockedMessage);
      expect(h.server.requests, isEmpty);
      final restarted = await h.restart('alice');
      expect(restarted.setup, PrivateChatSetup.blocked);
      // A backup of the old version cannot roll the device back either.
      const password = 'correct horse battery';
      final stale = await v1Backup(
        scopeOf('alice'),
        jsonEncode(v1Secret(h, 'alice')),
        password,
      );
      await expectLater(
        restarted.importBackup(stale, password),
        throwsA(isA<EncryptionException>()),
      );
      expect(restarted.setup, PrivateChatSetup.blocked);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'finding 3: rotation never re-certifies a removed device the server lists as active',
    () async {
      final phoneId = await withPhone();
      await h.client('alice-tablet', user: 'alice').encryption!.initialize();
      await h.approve('alice', 'alice-tablet');
      final tabletId = await deviceIdOf(h.e('alice-tablet'));
      final alice = h.server.users['alice']!;
      final phoneRow = Map<String, dynamic>.from(alice.devices[phoneId]!);
      await h.e('alice').removeDevices([phoneId]);
      // The server resurrects the phone with its version-1 certificate.
      alice.devices[phoneId] = {...phoneRow, 'status': 'active'};
      alice.revoked.remove(phoneId);
      await expectLater(
        h.e('alice').removeDevices([tabletId]),
        throwsA(isA<EncryptionException>()),
      );
      expect(alice.account!.version, 2);
      expect(alice.packages.containsKey(phoneId), false);
      expect(alice.devices[tabletId]!['status'], 'active');
    },
  );

  test(
    'finding 4: older account versions need back-signatures; forged history is refused',
    () async {
      final phoneId = await withPhone();
      await h.e('charlie').initialize();
      h.current.add('charlie');
      await h.e('alice').removeDevices([phoneId]);
      final alice = h.server.users['alice']!;
      // The server invents a version 1 and signs the real version 2 with it
      // ("older signs newer"); it cannot produce version 2's back-signature.
      final fake = await SeededAccount(1, 51, 52).init();
      alice.accounts[0] = fake.fake;
      final v2 = alice.accounts[1];
      v2.signature = await fake.sign([
        'daccord-e2ee-rotate-v2',
        'alice',
        2,
        v2.exchangeKey,
        v2.signingKey,
      ]);
      final forged = await encryptV1(
        author: 'alice',
        authorSecret: fake.secret,
        recipients: {
          'alice': fake.exchangeKey,
          'bob': h.server.users['bob']!.account!.exchangeKey,
          'charlie': h.server.users['charlie']!.account!.exchangeKey,
        },
        content: 'forged history',
      );
      final read = await h.e('charlie').decrypt(h.wire(forged));
      expect(read.encryptionError, isNotNull);
      expect(read.content, isNot('forged history'));
      // A device certified by the invented version is not accepted either.
      const fakeId = 'ZmFrZWZha2VmYWtlZmFrZQ';
      alice.devices[fakeId] = {
        'device_id': fakeId,
        'exchange_key': fake.exchangeKey,
        'signing_key': fake.signingKey,
        'certificate': await fake.sign([
          'daccord-e2ee-device-v2',
          'alice',
          1,
          fakeId,
          fake.exchangeKey,
          fake.signingKey,
        ]),
        'account_version': 1,
        'status': 'revoked',
      };
      final keys = await h.e('charlie').participants('chat');
      expect((keys['alice']!['devices'] as Map).containsKey(fakeId), false);
      expect(
        (keys['alice']!['accounts'] as List).map((a) => (a as Map)['version']),
        [2],
      );
    },
  );

  test(
    'finding 5: a rotation whose response is lost is completed on restart',
    () async {
      final phoneId = await withPhone();
      h.server.loseRotationResponse = true;
      await expectLater(
        h.e('alice').removeDevices([phoneId]),
        throwsA(isA<EncryptionException>()),
      );
      expect(h.server.users['alice']!.account!.version, 2);
      expect(
        h.stores['alice']!.values['e2ee.v2.${scopeOf('alice')}.rotation'],
        isNotEmpty,
      );
      final restarted = await h.restart('alice');
      expect(restarted.setup, PrivateChatSetup.active);
      expect(
        h.stores['alice']!.values['e2ee.v2.${scopeOf('alice')}.rotation'],
        '',
      );
      final sent = await h.client('alice').messages.create('chat', {
        'content': 'still mine',
      });
      expect(sent.ok, true);
      expect(payloadOf(h.wireContent!)[10], 2);
      expect(
        (await h.e('bob').decrypt(h.wire(h.wireContent!))).content,
        'still mine',
      );
    },
  );

  test(
    'R5: the signed sender account version advances pins; history survives re-certification',
    () async {
      final phoneId = await withPhone();
      final bob = h.e('bob');
      final before = await bob.participants('chat');
      final earlier = await send(h.e('alice'), 'version 1 era');
      expect(payloadOf(earlier)[10], 1);
      await h.e('alice').removeDevices([phoneId]);
      // The laptop is re-certified at version 2; what it signed at version 1
      // must still verify (a live-server run caught this being refused).
      expect((await bob.decrypt(h.wire(earlier))).content, 'version 1 era');
      final after = await send(h.e('alice'), 'version 2 era');
      expect(payloadOf(after), hasLength(11));
      expect(payloadOf(after)[10], 2);
      final stale = await bob.decrypt(h.wire(after), participantKeys: before);
      expect(stale.encryptionError, contains('could not be verified'));
      expect((await bob.decrypt(h.wire(after))).content, 'version 2 era');

      // Re-signed by the device with a different version: the body was sealed
      // to the original context, so it no longer opens.
      final p = payloadOf(after)..[10] = 1;
      final device = deviceSecret(h, 'alice', user: 'alice');
      final signature = await Ed25519().sign(
        utf8.encode(jsonEncode(p)),
        keyPair: await Ed25519().newKeyPairFromSeed(
          base64Decode(device['signing_private'] as String),
        ),
      );
      final downgraded =
          '${PrivateChatEncryption.prefixV2}${jsonEncode({'payload': p, 'signature': base64Encode(signature.bytes)})}';
      expect(
        (await bob.decrypt(h.wire(downgraded))).encryptionError,
        isNotNull,
      );
    },
  );
}
