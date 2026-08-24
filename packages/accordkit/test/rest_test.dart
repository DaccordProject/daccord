import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import 'support/test_helpers.dart';

void main() {
  group('AccordRest transport security', () {
    test('rejects a cleartext remote API before making a request', () {
      expect(
        () => AccordRest('http://chat.example.test/api/v1'),
        throwsFormatException,
      );
    });

    test('allows a cleartext loopback API for development', () {
      final rest = AccordRest('http://[::1]:3000/api/v1');
      addTearDown(rest.close);
      expect(rest.baseUrl, 'http://[::1]:3000/api/v1');
    });
  });

  group('RestResult', () {
    test('success/failure factories and hasMore', () {
      final ok = RestResult.success(200, {'a': 1}, {'has_more': true});
      expect(ok.ok, isTrue);
      expect(ok.hasMore, isTrue);
      final err = RestResult.failure(400, AccordError(message: 'x'));
      expect(err.ok, isFalse);
      expect(err.error!.message, 'x');
    });

    test('deserialize and deserializeArray', () {
      final r = RestResult.success(200, {'id': '1', 'username': 'a'});
      r.deserialize(AccordUser.fromJson);
      expect((r.data as AccordUser).username, 'a');

      final arr = RestResult.success(200, [
        {'id': '1', 'username': 'a'},
        {'id': '2', 'username': 'b'},
      ]);
      arr.deserializeArray(AccordUser.fromJson);
      expect((arr.data as List).map((u) => (u as AccordUser).id), ['1', '2']);
    });
  });

  group('AccordError', () {
    test('fromJson', () {
      final e = AccordError.fromJson({
        'code': 'BAD',
        'message': 'nope',
        'details': {'k': 'v'}
      });
      expect(e.code, 'BAD');
      expect(e.details['k'], 'v');
    });
  });

  group('AccordRest.makeRequest', () {
    test('builds URL, encodes query, sets auth headers', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(
        log: log,
        responder: (_) => jsonData({'ok': true}),
      );
      await rest.makeRequest('GET', '/users/@me',
          query: {'limit': 10, 'q': 'a b', 'skip': null});

      final req = log.single;
      expect(req.method, 'GET');
      expect(req.url.path, '/api/v1/users/@me');
      expect(req.url.queryParameters['limit'], '10');
      expect(req.url.queryParameters['q'], 'a b');
      expect(req.url.queryParameters.containsKey('skip'), isFalse);
      expect(req.headers['authorization'], 'Bot test-token');
      expect(req.headers['user-agent'], contains('AccordKit'));
    });

    test('encodes JSON body for POST', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => jsonData(null));
      await rest.makeRequest('POST', '/x', body: {'a': 1});
      expect(log.single.jsonBody, {'a': 1});
    });

    test('parses data envelope with cursor normalisation', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response(
          jsonEncode({
            'data': [
              {'id': '1'}
            ],
            'cursor': {'after': '99'},
          }),
          200,
        ),
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isTrue);
      expect(result.hasMore, isTrue); // derived from non-empty after
      expect(result.cursor['after'], '99');
    });

    test('parses error envelope', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => jsonError('FORBIDDEN', 'no', status: 403),
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isFalse);
      expect(result.statusCode, 403);
      expect(result.error!.code, 'FORBIDDEN');
    });

    test('plain dict (no envelope) returned as map on success', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => jsonRaw({'hello': 'world'}),
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isTrue);
      expect((result.data as Map)['hello'], 'world');
    });

    test('empty success body yields null data', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response('', 204),
      );
      final result = await rest.makeRequest('DELETE', '/x');
      expect(result.ok, isTrue);
      expect(result.data, isNull);
    });

    test('retries on 429 then succeeds', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) {
          calls++;
          if (calls == 1) {
            return http.Response('{"retry_after":0.01}', 429,
                headers: {'retry-after': '0.01'});
          }
          return jsonData({'ok': true});
        },
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(calls, 2);
      expect(result.ok, isTrue);
    });

    test('gives up after max retries on persistent 429', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) {
          calls++;
          return http.Response('', 429, headers: {'retry-after': '0'});
        },
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(calls, AccordRest.maxRetries);
      expect(result.ok, isFalse);
      expect(result.statusCode, 429);
    });

    test('transport exception becomes INTERNAL error', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => throw Exception('boom'),
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isFalse);
      expect(result.error!.code, 'INTERNAL');
    });

    test('fires onUnauthorized on a 401 response', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) => jsonError('UNAUTHORIZED', 'nope', status: 401),
        onUnauthorized: () => calls++,
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isFalse);
      expect(result.statusCode, 401);
      expect(calls, 1);
    });

    test('does not fire onUnauthorized on non-401 failures', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) => jsonError('FORBIDDEN', 'no', status: 403),
        onUnauthorized: () => calls++,
      );
      await rest.makeRequest('GET', '/x');
      expect(calls, 0);
    });

    test('does not fire onUnauthorized on success', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) => jsonData({'ok': true}),
        onUnauthorized: () => calls++,
      );
      await rest.makeRequest('GET', '/x');
      expect(calls, 0);
    });
  });

  group('AccordRest.makeRawRequest', () {
    test('returns raw bytes on success', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response.bytes([1, 2, 3], 200),
      );
      final result = await rest.makeRawRequest('/plugins/1/bundle');
      expect(result.ok, isTrue);
      expect(result.data, isA<Uint8List>());
      expect(result.data as Uint8List, [1, 2, 3]);
    });

    test('non-2xx becomes failure', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response.bytes([], 404),
      );
      final result = await rest.makeRawRequest('/x');
      expect(result.ok, isFalse);
      expect(result.statusCode, 404);
    });

    test('401 invokes onUnauthorized', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response.bytes([], 401),
        onUnauthorized: () => calls++,
      );
      final result = await rest.makeRawRequest('/plugins/1/bundle');
      expect(result.ok, isFalse);
      expect(calls, 1);
    });
  });

  group('AccordRest.makeMultipartRequest', () {
    test('sends multipart body and parses response', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(
        log: log,
        responder: (_) => jsonData({'id': '1', 'channel_id': '2'}),
      );
      final form = MultipartForm(boundary: 'BOUND')
        ..addJson('payload_json', {'content': 'hi'})
        ..addFile('files[0]', 'a.txt', utf8.encode('hello'),
            contentType: 'text/plain');
      final result = await rest.makeMultipartRequest('POST', '/upload', form);
      expect(result.ok, isTrue);

      final body = utf8.decode(log.single.bodyBytes);
      expect(log.single.headers['content-type'], contains('boundary=BOUND'));
      expect(body, contains('name="payload_json"'));
      expect(body, contains('filename="a.txt"'));
      expect(body, contains('hello'));
      expect(body.trimRight().endsWith('--BOUND--'), isTrue);
    });

    test('fires onUnauthorized on a 401 response', () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        responder: (_) => jsonError('UNAUTHORIZED', 'nope', status: 401),
        onUnauthorized: () => calls++,
      );
      final form = MultipartForm(boundary: 'BOUND')..addField('a', 'b');
      final result =
          await rest.makeMultipartRequest('POST', '/upload', form);
      expect(result.ok, isFalse);
      expect(calls, 1);
    });
  });

  group('MultipartForm', () {
    test('builds well-formed parts', () {
      final form = MultipartForm(boundary: 'X')..addField('a', 'b');
      final out = utf8.decode(form.build());
      expect(out, contains('--X\r\nContent-Disposition: form-data; name="a"'));
      expect(out, contains('\r\nb\r\n'));
      expect(out.endsWith('--X--\r\n'), isTrue);
    });

    test('escapes the filename fallback and adds an RFC 5987 filename', () {
      final form = MultipartForm(boundary: 'X')
        ..addFile('file', 'résumé "final"\\100%.txt', [1, 2, 3]);

      final out = utf8.decode(form.build());
      expect(out, contains(r'''filename="r_sum_ \"final\"\\100%.txt"'''));
      expect(
        out,
        contains(
          "filename*=UTF-8''r%C3%A9sum%C3%A9%20%22final%22%5C100%25.txt",
        ),
      );
    });

    test('does not emit control characters in the filename fallback', () {
      final form = MultipartForm(boundary: 'X')
        ..addFile('file', 'null\u0000tab\t.txt', [1]);

      final out = utf8.decode(form.build());
      expect(out, contains('filename="null_tab_.txt"'));
      expect(out, contains("filename*=UTF-8''null%00tab%09.txt"));
    });

    test('rejects filenames containing CR or LF', () {
      for (final filename in [
        'evil\rname.txt',
        'evil\nname.txt',
        'evil\r\nX-Injected: true.txt',
      ]) {
        final form = MultipartForm(boundary: 'X');
        expect(
          () => form.addFile('file', filename, [1]),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'filename',
            ),
          ),
        );
        expect(utf8.decode(form.build()), isNot(contains('X-Injected')));
      }
    });
  });
}
