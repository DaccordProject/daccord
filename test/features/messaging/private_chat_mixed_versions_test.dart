import 'package:accordkit/accordkit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2ee_test_server.dart';

Matcher _refused(String message) => throwsA(
  isA<EncryptionException>().having((e) => e.message, 'message', message),
);

void main() {
  late Harness h;
  setUp(() => h = Harness());
  tearDown(() async => h.close());

  test(
    'legacy server: v1 setup and messaging work; device APIs refuse cleanly',
    () async {
      h.server.legacy = true;
      await h.setup();
      final alice = h.e('alice');
      expect(alice.setup, PrivateChatSetup.active);
      expect(alice.legacyServer, true);
      expect(h.e('bob').setup, PrivateChatSetup.active);

      final sent = await h.client('alice').messages.create('chat', {
        'content': 'hello from v1',
      });
      expect(sent.ok, true, reason: '${sent.error}');
      expect(h.wireContent, startsWith(PrivateChatEncryption.prefixV1));
      expect(
        (await h.e('bob').decrypt(h.wire(h.wireContent!))).content,
        'hello from v1',
      );
      final reply = await h.client('bob').messages.create('chat', {
        'content': 'reply',
      });
      expect(reply.ok, true, reason: '${reply.error}');
      expect(
        (await alice.decrypt(h.wire(h.wireContent!, author: 'bob'))).content,
        'reply',
      );

      const message = PrivateChatEncryption.legacyDevicesMessage;
      await expectLater(alice.listDevices(), _refused(message));
      await expectLater(alice.linkCode(), _refused(message));
      await expectLater(alice.approveDevice('x'), _refused(message));
      await expectLater(alice.declineDevice('x'), _refused(message));
      await expectLater(alice.removeDevices(['x']), _refused(message));
      await expectLater(alice.confirmApproval(), _refused(message));
      await expectLater(alice.rejectApproval(), _refused(message));
      await expectLater(
        alice.linkCodeFor(
          const EncryptionDevice(
            deviceId: 'AAAAAAAAAAAAAAAAAAAAAA',
            name: 'x',
            status: EncryptionDeviceStatus.pending,
            exchangeKey: 'x',
            signingKey: 'x',
          ),
        ),
        _refused(message),
      );
      expect(await alice.checkApproval(), true);
      expect(h.server.paths.where((p) => p.contains('/devices')), isEmpty);
    },
  );

  test(
    'legacy server: a second device is blocked (sticky) until it imports a backup',
    () async {
      h.server.legacy = true;
      await h.setup();
      const password = 'correct horse battery';
      final backup = await h.e('alice').exportBackup(password);
      final fromBob = await h.e('bob').encrypt('chat', {'content': 'history'});
      final phone = h.client('alice-phone', user: 'alice').encryption!;
      await phone.initialize();
      expect(phone.setup, PrivateChatSetup.blocked);
      expect(phone.blockedReason, PrivateChatEncryption.legacyConflictMessage);
      for (var i = 0; i < 3; i++) {
        final read = await phone.decrypt(
          h.wire(fromBob.data['content'] as String, author: 'bob'),
        );
        expect(
          read.encryptionError,
          PrivateChatEncryption.legacyConflictMessage,
        );
      }
      final blocked = await h.client('alice-phone').messages.create('chat', {
        'content': 'x',
      });
      expect(blocked.ok, false);
      expect(
        blocked.error!.message,
        PrivateChatEncryption.legacyConflictMessage,
      );
      // One registration attempt, not one per message.
      expect(
        h.server.paths.where((p) => p == 'PUT /users/@me/encryption'),
        hasLength(3), // alice, bob, phone
      );
      await phone.importBackup(backup, password);
      expect(phone.setup, PrivateChatSetup.active);
      expect(
        (await phone.decrypt(
          h.wire(fromBob.data['content'] as String, author: 'bob'),
        )).content,
        'history',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'server upgrade: the next start re-probes into v2 with history intact',
    () async {
      h.server.legacy = true;
      await h.setup();
      final first =
          (await h.e('alice').encrypt('chat', {
                'content': 'before the upgrade',
              })).data['content']
              as String;
      expect(first, startsWith(PrivateChatEncryption.prefixV1));

      h.server.legacy = false;
      final alice = await h.restart('alice');
      final bob = await h.restart('bob');
      expect(alice.legacyServer, false);
      expect(alice.setup, PrivateChatSetup.active);
      expect(bob.setup, PrivateChatSetup.active);
      expect(
        h.server.users['alice']!.devices.values.single['status'],
        'active',
      );
      expect((await bob.decrypt(h.wire(first))).content, 'before the upgrade');
      expect(
        (await alice.decrypt(h.wire(first))).content,
        'before the upgrade',
      );
      final sent = await h.client('alice').messages.create('chat', {
        'content': 'after the upgrade',
      });
      expect(sent.ok, true, reason: '${sent.error}');
      expect(h.wireContent, startsWith(PrivateChatEncryption.prefixV2));
      expect(
        (await bob.decrypt(h.wire(h.wireContent!))).content,
        'after the upgrade',
      );
      expect((await alice.listDevices()), hasLength(1));
    },
  );

  test(
    'v2 server: a participant on an old client gets v1, even after a rotation',
    () async {
      await h.setup();
      await h.client('alice-phone', user: 'alice').encryption!.initialize();
      await h.approve('alice', 'alice-phone');
      await h.e('alice').removeDevices([
        (await h.e('alice-phone').listDevices())
            .firstWhere((d) => d.current)
            .deviceId,
      ]);
      // dave registered with a pre-v2 client: an identity, no devices.
      final dave = await SeededAccount(1, 61, 62).init();
      h.server.user('dave').accounts.add(dave.fake);
      h.current.add('dave');

      final sent = await h.client('alice').messages.create('chat', {
        'content': 'readable everywhere',
      });
      expect(sent.ok, true, reason: '${sent.error}');
      expect(h.wireContent, startsWith(PrivateChatEncryption.prefixV1));
      // Signed by alice's current (rotated) account key, as v1 admission
      // and old clients check it.
      expect(
        await decryptAsOldClient(
          content: h.wireContent!,
          user: 'dave',
          account: dave,
          authorSigningKey: h.server.users['alice']!.account!.signingKey,
        ),
        'readable everywhere',
      );
      expect(
        (await h.e('bob').decrypt(h.wire(h.wireContent!))).content,
        'readable everywhere',
      );

      // Without old clients in the chat, v2 again.
      h.current.remove('dave');
      final next = await h.client('alice').messages.create('chat', {
        'content': 'v2 again',
      });
      expect(next.ok, true, reason: '${next.error}');
      expect(h.wireContent, startsWith(PrivateChatEncryption.prefixV2));
    },
  );

  test('a v1 chat home (no v2 discovery fields) gets v1 envelopes', () async {
    await h.setup();
    h.server.v1Discovery = true;
    final sent = await h.client('alice').messages.create('chat', {
      'content': 'via an old chat home',
    });
    expect(sent.ok, true, reason: '${sent.error}');
    expect(h.wireContent, startsWith(PrivateChatEncryption.prefixV1));
    expect(
      (await h.e('bob').decrypt(h.wire(h.wireContent!))).content,
      'via an old chat home',
    );
  });
}
