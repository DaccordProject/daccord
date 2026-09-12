import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
    test('success/failure factories', () {
      final ok = RestResult.success(200, {'a': 1});
      expect(ok.ok, isTrue);
      expect(ok.data, {'a': 1});
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

    test('extras default to empty and pendingAttachments to none', () {
      final r = RestResult.success(200, {'id': '1'});
      expect(r.extras, isEmpty);
      expect(r.pendingAttachments, isEmpty);
      expect(r.accepted, isFalse);
    });

    test('pendingAttachments reads string ids and tolerates junk', () {
      final r = RestResult.success(202, null, extras: {
        'pending_attachments': ['u1', 2, null, ''],
      });
      expect(r.pendingAttachments, ['u1', '2']);
      expect(r.accepted, isTrue);

      final notAList =
          RestResult.success(202, null, extras: {'pending_attachments': 'u1'});
      expect(notAList.pendingAttachments, isEmpty);
    });
  });

  group('AccordError', () {
    test('fromJson', () {
      final e = AccordError.fromJson({'code': 'BAD', 'message': 'nope'});
      expect(e.code, 'BAD');
      expect(e.message, 'nope');
      expect(e.retryAfter, isNull);
      expect(e.isRateLimited, isFalse);
    });

    test('fromJson keeps the server rate-limit code, message and retry_after',
        () {
      final e = AccordError.fromJson({
        'code': 'rate_limited',
        'message': 'rate limited, retry after 12s',
        'retry_after': 12,
      });
      expect(e.code, 'rate_limited');
      expect(e.isRateLimited, isTrue);
      expect(e.message, 'rate limited, retry after 12s');
      expect(e.retryAfter, const Duration(seconds: 12));
      expect(e.toString(), contains('retryAfter: 12s'));
    });

    test('parseRetryAfter accepts numbers and numeric strings in seconds', () {
      expect(AccordError.parseRetryAfter(5), const Duration(seconds: 5));
      expect(AccordError.parseRetryAfter(0), Duration.zero);
      expect(
        AccordError.parseRetryAfter(0.25),
        const Duration(milliseconds: 250),
      );
      expect(AccordError.parseRetryAfter(' 30 '), const Duration(seconds: 30));
      expect(
        AccordError.parseRetryAfter('1.5'),
        const Duration(milliseconds: 1500),
      );
    });

    test('parseRetryAfter rejects missing, malformed and negative values', () {
      expect(AccordError.parseRetryAfter(null), isNull);
      expect(AccordError.parseRetryAfter(''), isNull);
      expect(AccordError.parseRetryAfter('soon'), isNull);
      expect(AccordError.parseRetryAfter(-3), isNull);
      expect(AccordError.parseRetryAfter(double.nan), isNull);
      expect(AccordError.parseRetryAfter(double.infinity), isNull);
      expect(AccordError.parseRetryAfter(true), isNull);
      expect(AccordError.parseRetryAfter(const {}), isNull);
    });

    test('parseRetryAfter clamps to the maximum slowmode', () {
      expect(AccordError.parseRetryAfter(21600), AccordError.maxRetryAfter);
      expect(AccordError.parseRetryAfter(999999999), AccordError.maxRetryAfter);
      expect(AccordError.maxRetryAfter, const Duration(hours: 6));
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

    test('parses data envelope', () async {
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
      expect(result.data, [
        {'id': '1'}
      ]);
    });

    test('keeps envelope siblings of data on extras', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response(
          jsonEncode({
            'data': {'id': '1'},
            'cursor': {'after': '99'},
          }),
          200,
        ),
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.data, {'id': '1'});
      expect(result.extras, {
        'cursor': {'after': '99'}
      });
      expect(result.pendingAttachments, isEmpty);
    });

    test('a 202 with pending_attachments is a success that keeps the ids',
        () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response(
          jsonEncode({
            'data': {'id': 'm1', 'channel_id': '5', 'attachments': []},
            'pending_attachments': ['u1', 'u2'],
          }),
          202,
        ),
      );
      final result = await rest.makeRequest('POST', '/x');
      expect(result.ok, isTrue);
      expect(result.statusCode, 202);
      expect(result.accepted, isTrue);
      expect(result.data, {'id': 'm1', 'channel_id': '5', 'attachments': []});
      expect(result.pendingAttachments, ['u1', 'u2']);
    });

    test('a 200 from a server that predates pending_attachments has none',
        () async {
      final rest = mockRest(
        log: [],
        responder: (_) => jsonData({'id': 'm1'}),
      );
      final result = await rest.makeRequest('POST', '/x');
      expect(result.statusCode, 200);
      expect(result.accepted, isFalse);
      expect(result.extras, isEmpty);
      expect(result.pendingAttachments, isEmpty);
    });

    test('a plain (non-envelope) body has no extras', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => jsonRaw({
          'id': 'm1',
          'pending_attachments': ['u1']
        }),
      );
      final result = await rest.makeRequest('POST', '/x');
      expect(result.extras, isEmpty);
      expect(result.pendingAttachments, isEmpty);
      expect((result.data as Map)['id'], 'm1');
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

    test('a stalled response times out as a normal failure, not a throw',
        () async {
      final rest = mockRest(
        log: [],
        timeout: const Duration(milliseconds: 20),
        // Never completes — a black-holed server (#306).
        responder: (_) => Completer<http.Response>().future,
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(result.ok, isFalse);
      expect(result.statusCode, 0);
      expect(result.error!.code, 'INTERNAL');
      expect(result.error!.message, contains('timed out'));
    });

    test('the timeout is per attempt, so a 429 retry still gets a full one',
        () async {
      var calls = 0;
      final rest = mockRest(
        log: [],
        timeout: const Duration(milliseconds: 200),
        responder: (_) async {
          calls++;
          if (calls == 1) {
            // Burns most of one attempt's budget, then rate-limits. A budget
            // shared across retries would leave the second attempt no time.
            await Future<void>.delayed(const Duration(milliseconds: 120));
            return http.Response('', 429, headers: {'retry-after': '0'});
          }
          await Future<void>.delayed(const Duration(milliseconds: 120));
          return jsonData({'ok': true});
        },
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(calls, 2);
      expect(result.ok, isTrue);
    });

    test('defaults to AccordConfig.defaultRequestTimeout', () {
      final rest = mockRest(log: [], responder: (_) => jsonData(null));
      expect(rest.timeout, AccordConfig.defaultRequestTimeout);
      expect(AccordConfig.defaultRequestTimeout, greaterThan(Duration.zero));
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

  group('AccordRest rate limiting (#330)', () {
    /// The server's exact 429 shape (accordserver `AppError::RateLimited`):
    /// `Retry-After` header plus `error.retry_after`, both in seconds.
    http.Response rateLimited({
      Object? bodyRetryAfter = 12,
      String? headerRetryAfter = '12',
      String message = 'rate limited, retry after 12s',
    }) {
      return http.Response(
        jsonEncode({
          'error': {
            'code': 'rate_limited',
            'message': message,
            if (bodyRetryAfter != null) 'retry_after': bodyRetryAfter,
          },
        }),
        429,
        headers: {
          'content-type': 'application/json',
          if (headerRetryAfter != null) 'retry-after': headerRetryAfter,
        },
      );
    }

    test('a user send opted out of retry gets the server error after one POST',
        () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => rateLimited());
      final result = await rest.makeRequest(
        'POST',
        '/channels/c/messages',
        body: {'content': 'hi'},
        retryOnRateLimit: false,
      );
      expect(log, hasLength(1));
      expect(result.ok, isFalse);
      expect(result.statusCode, 429);
      final error = result.error!;
      expect(error.code, 'rate_limited');
      expect(error.isRateLimited, isTrue);
      expect(error.message, 'rate limited, retry after 12s');
      expect(error.retryAfter, const Duration(seconds: 12));
    });

    test('MessagesApi.create makes exactly one request on a 429', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => rateLimited());
      final result = await MessagesApi(rest).create('c', {'content': 'hi'});
      expect(log, hasLength(1));
      expect(log.single.method, 'POST');
      expect(result.statusCode, 429);
      expect(result.error!.code, 'rate_limited');
      expect(result.error!.retryAfter, const Duration(seconds: 12));
    });

    test('a thread reply through MessagesApi.create is not retried either',
        () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => rateLimited());
      await MessagesApi(rest).create('c', {'content': 'hi', 'thread_id': 'r'});
      expect(log, hasLength(1));
      expect(log.single.jsonBody!['thread_id'], 'r');
    });

    test('a multipart upload is never retransmitted on a 429', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => rateLimited());
      final result = await MessagesApi(rest).createWithAttachments(
        'c',
        {'content': 'pic'},
        [
          {
            'filename': 'a.png',
            'content': Uint8List.fromList([1, 2, 3]),
            'content_type': 'image/png',
          },
        ],
      );
      expect(log, hasLength(1));
      expect(log.single.url.path, endsWith('/channels/c/messages/upload'));
      expect(result.ok, isFalse);
      expect(result.statusCode, 429);
      expect(result.error!.code, 'rate_limited');
      expect(result.error!.retryAfter, const Duration(seconds: 12));
    });

    test('makeMultipartRequest honours retryOnRateLimit: false directly',
        () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => rateLimited());
      final form = MultipartForm()..addField('x', 'y');
      final result = await rest.makeMultipartRequest(
        'POST',
        '/upload',
        form,
        retryOnRateLimit: false,
      );
      expect(log, hasLength(1));
      expect(result.error!.retryAfter, const Duration(seconds: 12));
    });

    test('a GET is still retried after the server pause and then succeeds',
        () async {
      final sleeps = <Duration>[];
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        if (calls == 1) {
          return rateLimited(bodyRetryAfter: 2, headerRetryAfter: '2');
        }
        return jsonData({'ok': true});
      });
      final rest = AccordRest(
        'https://example.test/api/v1',
        token: 't',
        client: client,
        sleep: (d) async => sleeps.add(d),
      );
      addTearDown(rest.close);
      final result = await rest.makeRequest('GET', '/x');
      expect(calls, 2);
      expect(result.ok, isTrue);
      expect(sleeps, [const Duration(seconds: 2)]);
    });

    test('exhausted retries keep the last server error and retryAfter',
        () async {
      final log = <CapturedRequest>[];
      var calls = 0;
      final rest = mockRest(
        log: log,
        responder: (_) {
          calls++;
          return rateLimited(
            bodyRetryAfter: calls * 10,
            headerRetryAfter: '${calls * 10}',
            message: 'attempt $calls',
          );
        },
      );
      final result = await rest.makeRequest('GET', '/x');
      expect(log, hasLength(AccordRest.maxRetries));
      expect(result.ok, isFalse);
      expect(result.statusCode, 429);
      expect(result.error!.code, 'rate_limited');
      expect(result.error!.message, 'attempt ${AccordRest.maxRetries}');
      expect(
        result.error!.retryAfter,
        Duration(seconds: AccordRest.maxRetries * 10),
      );
    });

    test('the body retry_after wins over the header', () async {
      final rest = mockRest(
        log: [],
        responder: (_) => rateLimited(bodyRetryAfter: 7, headerRetryAfter: '3'),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.error!.retryAfter, const Duration(seconds: 7));
    });

    test('the header is used when the body carries no retry_after', () async {
      final rest = mockRest(
        log: [],
        responder: (_) =>
            rateLimited(bodyRetryAfter: null, headerRetryAfter: '3'),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.error!.retryAfter, const Duration(seconds: 3));
      expect(result.error!.code, 'rate_limited');
    });

    test('a string-encoded body retry_after is accepted', () async {
      final rest = mockRest(
        log: [],
        responder: (_) =>
            rateLimited(bodyRetryAfter: '45', headerRetryAfter: null),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.error!.retryAfter, const Duration(seconds: 45));
    });

    test('malformed body and header fall back to the 1s default', () async {
      final rest = mockRest(
        log: [],
        responder: (_) =>
            rateLimited(bodyRetryAfter: 'soon', headerRetryAfter: 'later'),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.error!.retryAfter, AccordRest.defaultRetryAfter);
      expect(AccordRest.defaultRetryAfter, const Duration(seconds: 1));
    });

    test('an empty 429 body still yields a rate_limited error with retryAfter',
        () async {
      final rest = mockRest(
        log: [],
        responder: (_) => http.Response('', 429),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.statusCode, 429);
      expect(result.error!.code, 'rate_limited');
      expect(result.error!.message, isNotEmpty);
      expect(result.error!.retryAfter, AccordRest.defaultRetryAfter);
    });

    test('an oversized retry_after is capped at the maximum slowmode',
        () async {
      final rest = mockRest(
        log: [],
        responder: (_) => rateLimited(
          bodyRetryAfter: 99999999,
          headerRetryAfter: '99999999',
        ),
      );
      final result =
          await rest.makeRequest('POST', '/x', retryOnRateLimit: false);
      expect(result.error!.retryAfter, AccordError.maxRetryAfter);
    });

    test('a 200 is never retried', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(log: log, responder: (_) => jsonData({'id': '1'}));
      final result = await rest.makeRequest('POST', '/x', body: {'a': 1});
      expect(log, hasLength(1));
      expect(result.ok, isTrue);
      expect(result.statusCode, 200);
    });

    test('an accepted 202 is never retried', () async {
      final log = <CapturedRequest>[];
      final rest = mockRest(
        log: log,
        responder: (_) => jsonData({'id': '1'}, status: 202),
      );
      final result = await MessagesApi(rest).createWithAttachments(
        'c',
        {'content': 'pic'},
        [
          {'filename': 'a.png', 'content': Uint8List.fromList([1])},
        ],
      );
      expect(log, hasLength(1));
      expect(result.ok, isTrue);
      expect(result.statusCode, 202);
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
      final result = await rest.makeMultipartRequest('POST', '/upload', form);
      expect(result.ok, isFalse);
      expect(calls, 1);
    });

    test('is bounded by uploadTimeout rather than the shorter request timeout',
        () async {
      // A large or slow-link attachment upload can easily outrun the ordinary
      // request timeout without being stuck; uploadTimeout gives it a
      // separate, longer budget (#306 follow-up).
      final rest = mockRest(
        log: [],
        timeout: const Duration(milliseconds: 20),
        uploadTimeout: const Duration(milliseconds: 200),
        responder: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return jsonData({'id': '1'});
        },
      );
      final form = MultipartForm(boundary: 'BOUND')..addField('a', 'b');
      final result = await rest.makeMultipartRequest('POST', '/upload', form);
      expect(result.ok, isTrue);
    });

    test('still times out as a normal failure once uploadTimeout elapses',
        () async {
      final rest = mockRest(
        log: [],
        uploadTimeout: const Duration(milliseconds: 20),
        responder: (_) => Completer<http.Response>().future,
      );
      final form = MultipartForm(boundary: 'BOUND')..addField('a', 'b');
      final result = await rest.makeMultipartRequest('POST', '/upload', form);
      expect(result.ok, isFalse);
      expect(result.error!.message, contains('timed out'));
    });

    test('defaults to AccordConfig.defaultUploadTimeout', () {
      final rest = mockRest(log: [], responder: (_) => jsonData(null));
      expect(rest.uploadTimeout, AccordConfig.defaultUploadTimeout);
      expect(
        AccordConfig.defaultUploadTimeout,
        greaterThan(AccordConfig.defaultRequestTimeout),
      );
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
