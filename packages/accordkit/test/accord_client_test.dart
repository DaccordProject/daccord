import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/fake_gateway_connection.dart';

Future<void> pump([int times = 2]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('rejects cleartext remote REST and gateway configuration', () {
    expect(
      () => AccordClient(baseUrl: 'http://chat.example.test'),
      throwsFormatException,
    );
    expect(
      () => AccordClient(gatewayUrl: 'ws://chat.example.test/ws'),
      throwsFormatException,
    );
  });

  test('wires config, endpoint APIs, and applies token to REST', () {
    final client = AccordClient(
      token: 'abc',
      tokenType: 'Bearer',
      baseUrl: 'https://srv',
      intents: ['messages'],
    );
    expect(client.config.apiUrl(), 'https://srv/api/v1');
    expect(client.rest.token, 'abc');
    expect(client.rest.tokenType, 'Bearer');
    expect(client.users, isA<UsersApi>());
    expect(client.directory, isA<DirectoryApi>());
    expect(client.automod, isA<AutomodApi>());
  });

  test('applies the default request timeout, and an override', () {
    expect(
      AccordClient(baseUrl: 'https://srv').rest.timeout,
      AccordConfig.defaultRequestTimeout,
    );
    expect(
      AccordClient(
        baseUrl: 'https://srv',
        requestTimeout: const Duration(seconds: 5),
      ).rest.timeout,
      const Duration(seconds: 5),
    );
  });

  test('applies the default upload timeout, and an override', () {
    expect(
      AccordClient(baseUrl: 'https://srv').rest.uploadTimeout,
      AccordConfig.defaultUploadTimeout,
    );
    expect(
      AccordClient(
        baseUrl: 'https://srv',
        uploadTimeout: const Duration(minutes: 1),
      ).rest.uploadTimeout,
      const Duration(minutes: 1),
    );
  });

  test('forwards gateway events through the client', () async {
    final factory = FakeConnectionFactory();
    final client = AccordClient(
      token: 'tok',
      connectionFactory: factory.call,
      sleep: (_) async {},
    );
    final messages = <AccordMessage>[];
    client.onMessageCreate.listen(messages.add);

    client.login();
    await pump();
    factory.last.receive(jsonEncode({
      'op': GatewayOpcodes.event,
      'type': 'message.create',
      'data': {'id': '1', 'channel_id': '5', 'content': 'yo'},
    }));
    await pump();

    expect(messages.single.content, 'yo');
    await client.dispose();
  });

  test('routes encryption device events to the encryption layer', () async {
    final factory = FakeConnectionFactory();
    final requests = <String>[];
    final client = AccordClient(
      token: 'tok',
      baseUrl: 'https://chat.test',
      encryptionStore: _MemoryStore(),
      encryptionUserId: 'alice',
      encryptionDeviceName: '  Daccord on Linux  ',
      connectionFactory: factory.call,
      sleep: (_) async {},
      httpClient: MockClient((req) async {
        requests.add('${req.method} ${req.url.path}');
        return http.Response('{}', 503);
      }),
    );
    expect(client.encryption!.deviceName, 'Daccord on Linux');
    expect(client.encryption!.setup, PrivateChatSetup.unknown);
    final pending = <EncryptionDevice>[];
    var updates = 0;
    client.encryption!.onDevicePending.listen(pending.add);
    client.encryption!.onDevicesUpdate.listen((_) => updates++);

    client.login();
    await pump();
    factory.last.receive(jsonEncode({
      'op': GatewayOpcodes.event,
      'type': 'encryption.device_pending',
      'data': {
        'device_id': 'AAAAAAAAAAAAAAAAAAAAAA',
        'name': 'Daccord on iOS',
        'exchange_key': 'x',
        'signing_key': 's',
        'certificate': null,
        'account_version': null,
        'status': 'pending',
        'created_at': '2026-11-10T12:00:00Z',
        'last_seen_at': '2026-11-10T12:00:00Z',
        'current': false,
      },
    }));
    factory.last.receive(jsonEncode({
      'op': GatewayOpcodes.event,
      'type': 'encryption.devices_update',
      'data': {},
    }));
    await pump(6);

    expect(pending.single.name, 'Daccord on iOS');
    expect(pending.single.status, EncryptionDeviceStatus.pending);
    expect(pending.single.createdAt, DateTime.utc(2026, 11, 10, 12));
    expect(updates, 1);
    // devices_update also checks this device's approval (here: offline).
    expect(requests, contains('GET /api/v1/users/@me/encryption'));
    await client.dispose();
  });

  test('REST endpoints work through the client with a mock http client',
      () async {
    final mock = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'data': {'id': '1', 'username': 'me'}
        }),
        200,
      );
    });
    final client = AccordClient(token: 'tok', httpClient: mock);
    final result = await client.users.getMe();
    expect((result.data as AccordUser).username, 'me');
    await client.dispose();
  });
}

class _MemoryStore implements EncryptionKeyStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
