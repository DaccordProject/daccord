import 'dart:convert';

import 'package:bonfire/features/error_reporting/repositories/glitchtip_client.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('DSN parsing', () {
    test('valid DSN initializes and derives the store URL', () {
      final client = GlitchTipClient();
      expect(client.init('https://abc123@crash.daccord.gg/1'), isTrue);
      expect(client.isInitialized, isTrue);
      expect(client.storeUrl, 'https://crash.daccord.gg/api/1/store/');
    });

    test('DSN with port and path prefix keeps both', () {
      final client = GlitchTipClient();
      expect(client.init('http://key@errors.example.com:8000/gt/42'), isTrue);
      expect(
        client.storeUrl,
        'http://errors.example.com:8000/gt/api/42/store/',
      );
    });

    test('rejects blank, schemeless, keyless, and projectless DSNs', () {
      expect(GlitchTipClient().init(''), isFalse);
      expect(GlitchTipClient().init('crash.daccord.gg/1'), isFalse);
      expect(GlitchTipClient().init('ftp://key@host/1'), isFalse);
      expect(GlitchTipClient().init('https://crash.daccord.gg/1'), isFalse);
      expect(GlitchTipClient().init('https://key@crash.daccord.gg'), isFalse);
    });
  });

  group('event sending', () {
    late List<http.Request> requests;
    late GlitchTipClient client;

    setUp(() {
      requests = [];
      client = GlitchTipClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"id":"1"}', 200);
        }),
      );
      client.init('https://thekey@crash.example.com/7');
    });

    test('captureMessage posts a Sentry event with auth header', () async {
      client.setTag('type', 'user-feedback');
      client.addBreadcrumb('Opened channel: …1234', 'navigation');
      await client.captureMessage('it broke');

      expect(requests, hasLength(1));
      final request = requests.single;
      expect(request.url.toString(), 'https://crash.example.com/api/7/store/');
      expect(request.headers['X-Sentry-Auth'], contains('sentry_version=7'));
      expect(request.headers['X-Sentry-Auth'], contains('sentry_key=thekey'));

      final event = jsonDecode(request.body) as Map<String, dynamic>;
      expect(event['event_id'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(event['event_id'], client.lastEventId);
      expect(event['level'], 'info');
      expect(event['release'], 'daccord@$kAppVersion');
      expect(event['message'], {'formatted': 'it broke'});
      expect(event['tags']['type'], 'user-feedback');
      expect(event['tags']['app_version'], kAppVersion);
      final crumbs = event['breadcrumbs']['values'] as List;
      expect(crumbs.single['message'], 'Opened channel: …1234');
      expect(crumbs.single['category'], 'navigation');
      expect(event['timestamp'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')));
    });

    test('captureError attaches parsed stack frames', () async {
      const stack = '''
#0      Foo.bar (package:bonfire/foo.dart:12:5)
#1      main (package:bonfire/main.dart:3:1)
<asynchronous suspension>
''';
      await client.captureError('boom', stack: stack);

      final event = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect(event['level'], 'error');
      final frames =
          event['exception']['values'][0]['stacktrace']['frames'] as List;
      // Oldest first: the non-frame line, then main, then Foo.bar.
      expect(frames.first, {'filename': '<asynchronous suspension>'});
      expect(frames.last, {
        'function': 'Foo.bar',
        'filename': 'package:bonfire/foo.dart',
        'lineno': 12,
      });
    });

    test('nothing is sent before init', () async {
      final uninitialized = GlitchTipClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('', 200);
        }),
      );
      await uninitialized.captureMessage('dropped');
      expect(requests, isEmpty);
    });

    test('a failing transport never throws', () async {
      final failing = GlitchTipClient(
        httpClient: MockClient((_) async => throw Exception('offline')),
      );
      failing.init('https://k@host.example/1');
      await failing.captureMessage('still fine');
    });
  });

  test('removeTag removes a previously set tag from events', () async {
    late http.Request captured;
    final client = GlitchTipClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      }),
    );
    client.init('https://k@host.example/1');
    client.setTag('type', 'user-feedback');
    client.removeTag('type');
    await client.captureMessage('check');
    final event = jsonDecode(captured.body) as Map<String, dynamic>;
    expect((event['tags'] as Map).containsKey('type'), isFalse);
  });

  test('breadcrumbs are capped at maxBreadcrumbs', () async {
    late http.Request captured;
    final client = GlitchTipClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 200);
      }),
    );
    client.init('https://k@host.example/1');
    for (var i = 0; i < GlitchTipClient.maxBreadcrumbs + 10; i++) {
      client.addBreadcrumb('crumb $i', 'test');
    }
    await client.captureMessage('check');
    final event = jsonDecode(captured.body) as Map<String, dynamic>;
    final crumbs = event['breadcrumbs']['values'] as List;
    expect(crumbs, hasLength(GlitchTipClient.maxBreadcrumbs));
    expect(crumbs.first['message'], 'crumb 10'); // oldest dropped
    expect(crumbs.last['message'], 'crumb 109');
  });
}
