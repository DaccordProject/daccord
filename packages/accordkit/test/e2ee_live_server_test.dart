@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// End-to-end private chat encryption v2 against a real accordserver.
///
/// Skipped unless `ACCORD_E2E_URL` points at a disposable server with open
/// registration, e.g.
///
///   accordserver --data-dir /tmp/accord-e2e --port 39099 --bind 127.0.0.1
///   ACCORD_E2E_URL=http://127.0.0.1:39099 dart test test/e2ee_live_server_test.dart
///
/// Registers two fresh accounts per run (the server allows five registrations
/// per IP per 15 minutes).
final _baseUrl = Platform.environment['ACCORD_E2E_URL'];

class _MemoryKeys implements EncryptionKeyStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

typedef _Account = ({String id, String token});

Future<_Account> _register(String username) async {
  final response = await http.post(
    Uri.parse('$_baseUrl/api/v1/auth/register'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(
        {'username': username, 'password': 'correct-horse-$username'}),
  );
  expect(response.statusCode, 200, reason: response.body);
  final data = (jsonDecode(response.body) as Map)['data'] as Map;
  return (
    id: (data['user'] as Map)['id'] as String,
    token: data['token'] as String
  );
}

/// A second session for [username]: a separate device.
Future<String> _login(String username) async {
  final response = await http.post(
    Uri.parse('$_baseUrl/api/v1/auth/login'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(
        {'username': username, 'password': 'correct-horse-$username'}),
  );
  expect(response.statusCode, 200, reason: response.body);
  return ((jsonDecode(response.body) as Map)['data'] as Map)['token'] as String;
}

AccordClient _device(String token, String userId, String name) => AccordClient(
      token: token,
      tokenType: 'Bearer',
      baseUrl: _baseUrl!,
      encryptionStore: _MemoryKeys(),
      encryptionUserId: userId,
      encryptionDeviceName: name,
    );

Future<List<AccordMessage>> _history(
    AccordClient client, String channel) async {
  final result = await client.messages.list(channel);
  expect(result.ok, true, reason: '${result.error}');
  return (result.data as List).cast<AccordMessage>();
}

Future<Map<String, dynamic>> _rawLatest(String token, String channel) async {
  final response = await http.get(
    Uri.parse('$_baseUrl/api/v1/channels/$channel/messages?limit=1'),
    headers: {'authorization': 'Bearer $token'},
  );
  expect(response.statusCode, 200, reason: response.body);
  return ((jsonDecode(response.body) as Map)['data'] as List).first
      as Map<String, dynamic>;
}

void main() {
  legacyMain();
  test(
    'devices: pending → approved reads history, removal rotates the account',
    () async {
      final suffix = Random().nextInt(1 << 32).toRadixString(36);
      final alice = await _register('alice$suffix');
      final bob = await _register('bob$suffix');
      final laptop = _device(alice.token, alice.id, 'Laptop');
      final bobClient = _device(bob.token, bob.id, 'Bob desktop');
      final clients = [laptop, bobClient];
      addTearDown(() async {
        for (final c in clients) {
          await c.dispose();
        }
      });

      await laptop.encryption!.initialize();
      await bobClient.encryption!.initialize();
      expect(laptop.encryption!.setup, PrivateChatSetup.active);
      expect(bobClient.encryption!.setup, PrivateChatSetup.active);

      final dm = await bobClient.users.createDm({
        'recipients': [alice.id],
      });
      expect(dm.ok, true, reason: '${dm.error}');
      final channel = (dm.data as AccordChannel).id;

      final first =
          await bobClient.messages.create(channel, {'content': 'hello 1'});
      expect(first.ok, true, reason: '${first.error}');
      final raw = await _rawLatest(alice.token, channel);
      expect(raw['content'], startsWith(PrivateChatEncryption.prefixV2));
      expect(raw['content'], isNot(contains('hello 1')));
      expect((await _history(laptop, channel)).first.content, 'hello 1');

      // A second session is a new device: pending, can't read yet.
      final phone = _device(await _login('alice$suffix'), alice.id, 'Phone');
      clients.add(phone);
      await phone.encryption!.initialize();
      expect(phone.encryption!.setup, PrivateChatSetup.pending);
      expect(
        (await _history(phone, channel)).first.content,
        PrivateChatEncryption.pendingMessage,
      );

      // Approve from the laptop after comparing codes.
      final pending = (await laptop.encryption!.listDevices())
          .singleWhere((d) => d.status == EncryptionDeviceStatus.pending);
      expect(pending.name, 'Phone');
      expect(await laptop.encryption!.linkCodeFor(pending),
          await phone.encryption!.linkCode());
      await laptop.encryption!.approveDevice(pending.deviceId);
      // Approved elsewhere, but unusable until confirmed on this device too.
      expect(await phone.encryption!.checkApproval(), false);
      expect(phone.encryption!.setup, PrivateChatSetup.approved);
      await phone.encryption!.confirmApproval();
      expect(phone.encryption!.setup, PrivateChatSetup.active);
      expect((await _history(phone, channel)).first.content, 'hello 1');

      final fromPhone =
          await phone.messages.create(channel, {'content': 'from phone'});
      expect(fromPhone.ok, true, reason: '${fromPhone.error}');
      expect((await _history(bobClient, channel)).first.content, 'from phone');
      final beforeRotation = await _rawLatest(alice.token, channel);
      final laptopId = (await laptop.encryption!.listDevices())
          .singleWhere((d) => d.current)
          .deviceId;
      expect(beforeRotation['content'], contains(laptopId));

      // Remove the laptop from the phone: rotation + the laptop is signed out.
      await phone.encryption!.removeDevices([laptopId]);
      final signedOut = await laptop.messages.list(channel);
      expect(signedOut.ok, false);
      expect(signedOut.statusCode, 401);

      // Bob's next send must pick up the rotation (stale keys → refresh and
      // retry) and must not address the removed laptop.
      final afterRotation = await bobClient.messages
          .create(channel, {'content': 'after removal'});
      expect(afterRotation.ok, true, reason: '${afterRotation.error}');
      final wire = await _rawLatest(bob.token, channel);
      expect(wire['content'], isNot(contains(laptopId)));
      expect((await _history(phone, channel)).first.content, 'after removal');

      // Bob's pin advances through the signed succession: the phone's
      // post-rotation message still verifies for him.
      final postRotation =
          await phone.messages.create(channel, {'content': 'still trusted'});
      expect(postRotation.ok, true, reason: '${postRotation.error}');
      expect(
        (await _history(bobClient, channel)).first.content,
        'still trusted',
      );

      // History written before the rotation stays readable on the phone.
      final history = await _history(phone, channel);
      expect(history.map((m) => m.content),
          containsAll(['hello 1', 'from phone', 'after removal']));
    },
    skip: _baseUrl == null ? 'set ACCORD_E2E_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'gateway delivers device approval requests on direct_messages',
    () async {
      final suffix = Random().nextInt(1 << 32).toRadixString(36);
      final alice = await _register('carol$suffix');
      final laptop = AccordClient(
        token: alice.token,
        tokenType: 'Bearer',
        baseUrl: _baseUrl!,
        gatewayUrl: '${_baseUrl!.replaceFirst('http', 'ws')}/ws',
        intents: [GatewayIntents.directMessages],
        encryptionStore: _MemoryKeys(),
        encryptionUserId: alice.id,
        encryptionDeviceName: 'Laptop',
      );
      final phone = _device(await _login('carol$suffix'), alice.id, 'Phone');
      addTearDown(() async {
        await laptop.dispose();
        await phone.dispose();
      });
      await laptop.encryption!.initialize();
      final ready = laptop.onReady.first;
      laptop.login();
      await ready.timeout(const Duration(seconds: 15));

      final requested = laptop.encryption!.onDevicePending.first;
      await phone.encryption!.initialize();
      final device = await requested.timeout(const Duration(seconds: 15));
      expect(device.name, 'Phone');
      expect(device.status, EncryptionDeviceStatus.pending);

      // Approval reaches the phone's account state via the laptop's update.
      final updated = laptop.encryption!.onDevicesUpdate.first;
      await laptop.encryption!.linkCodeFor(device);
      await laptop.encryption!.approveDevice(device.deviceId);
      await updated.timeout(const Duration(seconds: 15));
      await phone.encryption!.checkApproval();
      expect(phone.encryption!.setup, PrivateChatSetup.approved);
      await phone.encryption!.confirmApproval();
      expect(phone.encryption!.setup, PrivateChatSetup.active);
    },
    skip: _baseUrl == null ? 'set ACCORD_E2E_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// Against a server that predates per-device keys (v1 only). Set
/// `ACCORD_E2E_LEGACY_URL` to such a server, e.g. a build of accordserver
/// before private chat encryption v2.
final _legacyUrl = Platform.environment['ACCORD_E2E_LEGACY_URL'];

void legacyMain() {
  test(
    'v1-only server: new clients fall back to v1 and stay usable',
    () async {
      final suffix = Random().nextInt(1 << 32).toRadixString(36);
      Future<_Account> register(String name) async {
        final response = await http.post(
          Uri.parse('$_legacyUrl/api/v1/auth/register'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'username': name,
            'password': 'correct-horse-$name',
          }),
        );
        expect(response.statusCode, 200, reason: response.body);
        final data = (jsonDecode(response.body) as Map)['data'] as Map;
        return (
          id: (data['user'] as Map)['id'] as String,
          token: data['token'] as String,
        );
      }

      AccordClient device(String token, String id) => AccordClient(
            token: token,
            tokenType: 'Bearer',
            baseUrl: _legacyUrl!,
            encryptionStore: _MemoryKeys(),
            encryptionUserId: id,
            encryptionDeviceName: 'Legacy',
          );

      final dana = await register('dana$suffix');
      final eli = await register('eli$suffix');
      final danaClient = device(dana.token, dana.id);
      final eliClient = device(eli.token, eli.id);
      addTearDown(() async {
        await danaClient.dispose();
        await eliClient.dispose();
      });
      await danaClient.encryption!.initialize();
      await eliClient.encryption!.initialize();
      expect(danaClient.encryption!.legacyServer, isTrue);
      expect(danaClient.encryption!.setup, PrivateChatSetup.active);
      expect(eliClient.encryption!.setup, PrivateChatSetup.active);

      final dm = await eliClient.users.createDm({
        'recipients': [dana.id],
      });
      expect(dm.ok, true, reason: '${dm.error}');
      final channel = (dm.data as AccordChannel).id;
      final sent = await eliClient.messages.create(channel, {
        'content': 'v1 still works',
      });
      expect(sent.ok, true, reason: '${sent.error}');
      final history = await danaClient.messages.list(channel);
      expect(
        (history.data as List).cast<AccordMessage>().first.content,
        'v1 still works',
      );
      await expectLater(
        danaClient.encryption!.listDevices(),
        throwsA(isA<EncryptionException>()),
      );
    },
    skip: _legacyUrl == null ? 'set ACCORD_E2E_LEGACY_URL to run' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
