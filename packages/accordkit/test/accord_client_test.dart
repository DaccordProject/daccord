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
    expect(client.voiceManager, isA<VoiceManager>());
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
