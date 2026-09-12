import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/developer/services/mcp_server_io.dart';
import 'package:bonfire/features/developer/services/mcp_tools.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _toolsProvider = Provider<McpTools>((ref) => McpTools(ref));

void main() {
  late ProviderContainer container;
  late McpServer server;
  var token = '';

  setUp(() {
    container = ProviderContainer();
    token = '';
    server = McpServer(
      tools: container.read(_toolsProvider),
      tokenGetter: () => token,
      allowedGroupsGetter: () => const ['read'],
      onActivity: (_) {},
    );
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
  });

  test('refuses to start until a nonblank token exists', () async {
    expect(await server.start(0), isFalse);
    expect(server.isListening, isFalse);

    token = '   ';
    expect(await server.start(0), isFalse);
    expect(server.isListening, isFalse);

    token = ''.padLeft(64, 'a');
    expect(await server.start(0), isTrue);
    expect(server.isListening, isTrue);
    expect(server.port, greaterThan(0));
  });

  test('an empty live token never authenticates a request', () async {
    token = ''.padLeft(64, 'b');
    expect(await server.start(0), isTrue);
    token = '';

    expect(await _postInitialize(server.port), HttpStatus.unauthorized);
  });

  test('a matching nonempty bearer token still authenticates', () async {
    token = ''.padLeft(64, 'c');
    expect(await server.start(0), isTrue);

    expect(
      await _postInitialize(server.port, bearerToken: token),
      HttpStatus.ok,
    );
  });

  test(
    'handshake notifications have no body and tool discovery still works',
    () async {
      token = ''.padLeft(64, 'd');
      expect(await server.start(0), isTrue);
      final client = HttpClient();
      try {
        Future<(int, String)> post(Map<String, dynamic> message) async {
          final request = await client.postUrl(
            Uri.parse('http://127.0.0.1:${server.port}/mcp'),
          );
          request.headers.contentType = ContentType.json;
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          request.write(jsonEncode(message));
          final response = await request.close();
          return (
            response.statusCode,
            await utf8.decoder.bind(response).join(),
          );
        }

        final initialized = await post({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
        });
        expect(initialized.$1, HttpStatus.ok);
        expect(
          jsonDecode(initialized.$2)['result']['serverInfo']['name'],
          'daccord',
        );

        for (final method in [
          'notifications/initialized',
          'notifications/cancelled',
        ]) {
          final notification = await post({'jsonrpc': '2.0', 'method': method});
          expect(notification, (HttpStatus.accepted, ''));
        }

        final listed = await post({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/list',
        });
        expect(listed.$1, HttpStatus.ok);
        final body = jsonDecode(listed.$2);
        expect(body['id'], 2);
        expect(body['result']['tools'], isNotEmpty);
      } finally {
        client.close(force: true);
      }
    },
  );
}

Future<int> _postInitialize(int port, {String? bearerToken}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse('http://127.0.0.1:$port/mcp'),
    );
    request.headers.contentType = ContentType.json;
    if (bearerToken != null) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $bearerToken',
      );
    }
    request.write(
      jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize'}),
    );
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}
