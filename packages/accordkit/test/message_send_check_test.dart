import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  late AccordClient client;
  late List<http.Request> writes;
  setUp(() {
    writes = [];
    client = AccordClient(
        baseUrl: 'https://example.test',
        httpClient: MockClient((request) async {
          writes.add(request);
          return http.Response(
              jsonEncode({'id': 'm', 'channel_id': 'c', 'content': 'Hello'}),
              200);
        }));
  });
  tearDown(() => client.dispose());

  Future<RestResult> upload(Map<String, dynamic> data) =>
      client.messages.createWithAttachments('c', data, [
        {
          'filename': 'hello.txt',
          'content': Uint8List.fromList([1, 2]),
          'content_type': 'text/plain'
        },
      ]);

  test('a held check prevents create, edit, and upload before any HTTP request',
      () async {
    var checked = 0;
    client.messages.sendGuard = (channel, snapshot) async {
      checked++;
      return MessageSendCheck.hold(
          AccordError(code: 'held', message: 'Held draft'));
    };
    expect(
        (await client.messages.create('c', {'content': 'Hello'})).ok, isFalse);
    expect((await client.messages.edit('c', 'm', {'content': 'Hello'})).ok,
        isFalse);
    expect((await upload({'content': 'Hello'})).ok, isFalse);
    expect(checked, 3);
    expect(writes, isEmpty);
  });

  test('an exception in the application check cannot bypass it', () async {
    client.messages.sendGuard =
        (channel, snapshot) async => throw StateError('Unavailable');
    expect(
        (await client.messages.create('c', {'content': 'Hello'})).error?.code,
        'message_check_failed');
    expect(writes, isEmpty);
  });

  test('a caller cannot replace or mutate text while its snapshot is checked',
      () async {
    final gate = Completer<void>();
    Map<String, dynamic>? assessed;
    client.messages.sendGuard = (_, snapshot) async {
      assessed = snapshot;
      await gate.future;
      return const MessageSendCheck.allow();
    };
    final original = <String, dynamic>{
      'content': 'Checked',
      'embeds': <Object?>[]
    };
    final result = client.messages.create('c', original);
    original['content'] = 'Unchecked replacement';
    (original['embeds'] as List).add({'description': 'Unchecked embed'});
    await Future<void>.delayed(Duration.zero);
    expect(assessed!['content'], 'Checked');
    expect(() => assessed!['content'] = 'Replacement', throwsUnsupportedError);
    expect(() => (assessed!['embeds'] as List).add('Replacement'),
        throwsUnsupportedError);
    gate.complete();
    expect((await result).ok, isTrue);
    expect(jsonDecode(writes.single.body)['content'], 'Checked');
    expect(jsonDecode(writes.single.body)['embeds'], isEmpty);
  });

  test('approval is rechecked immediately before each actual network write',
      () async {
    for (final operation in <Future<RestResult> Function()>[
      () => client.messages.create('c', {'content': 'Hello'}),
      () => client.messages.edit('c', 'm', {'content': 'Hello'}),
      () => upload({'content': 'Hello'}),
    ]) {
      var checks = 0;
      client.messages.sendGuard = (channel, snapshot) async =>
          MessageSendCheck.allow(isCurrent: () => ++checks == 1);
      expect((await operation()).error?.code, 'message_check_stale');
    }
    expect(writes, isEmpty);
  });

  test('approved operations send exactly once without an implicit retry',
      () async {
    var checks = 0;
    client.messages.sendGuard = (channel, snapshot) async {
      checks++;
      return const MessageSendCheck.allow();
    };
    expect(
        (await client.messages.create('c', {'content': 'Hello'})).ok, isTrue);
    expect((await client.messages.edit('c', 'm', {'content': 'Hello'})).ok,
        isTrue);
    expect((await upload({'content': 'Hello'})).ok, isTrue);
    expect(checks, 3);
    expect(writes.map((r) => r.method), ['POST', 'PATCH', 'POST']);
  });

  test(
      'a rate-limited edit is returned without reusing approval for an automatic retry',
      () async {
    var attempts = 0;
    var sleeps = 0;
    final limited = AccordClient(
        baseUrl: 'https://example.test',
        sleep: (_) async {
          sleeps++;
        },
        httpClient: MockClient((request) async {
          attempts++;
          return http.Response(
              jsonEncode({
                'code': 'rate_limited',
                'message': 'Wait',
                'retry_after': 1
              }),
              429);
        }));
    addTearDown(limited.dispose);
    limited.messages.sendGuard =
        (channel, snapshot) async => const MessageSendCheck.allow();
    final result = await limited.messages.edit('c', 'm', {'content': 'Hello'});
    expect(result.statusCode, 429);
    expect(attempts, 1);
    expect(sleeps, 0);
  });
}
