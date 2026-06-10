import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/error_reporting/controllers/error_reporting.dart';
import 'package:bonfire/features/error_reporting/repositories/glitchtip_client.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('scrubPiiText', () {
    // Ported from the reference client's test_error_reporting.gd.
    test('redacts Bearer tokens', () {
      expect(
        scrubPiiText('Error: Bearer eyJhbGciOi.secret_token in request'),
        'Error: Bearer [REDACTED] in request',
      );
    });

    test('redacts token= query parameters', () {
      expect(
        scrubPiiText('GET /cdn/file?token=abc123&size=64 failed'),
        'GET /cdn/file?token=[REDACTED]&size=64 failed',
      );
    });

    test('redacts dk_ hex tokens', () {
      expect(
        scrubPiiText('auth with dk_0123456789abcdef rejected'),
        'auth with [TOKEN REDACTED] rejected',
      );
    });

    test('redacts bare 64-char hex tokens', () {
      final token = 'a' * 64;
      expect(
        scrubPiiText('stored $token locally'),
        'stored [TOKEN REDACTED] locally',
      );
    });

    test('redacts URLs with explicit ports', () {
      expect(
        scrubPiiText('connect to https://accord.example.com:8443/ws failed'),
        'connect to [URL REDACTED] failed',
      );
    });

    test('leaves ordinary text untouched', () {
      expect(
        scrubPiiText('a perfectly normal error'),
        'a perfectly normal error',
      );
    });
  });

  test('the dev DSN is used when no dart-define override is set', () {
    expect(resolveGlitchTipDsn(), kDefaultGlitchTipDsn);
  });

  group('ErrorReportingController', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('error-reporting-test');
      Hive.init(tempDir.path);
      await Hive.openBox('accord-settings');
    });

    tearDown(() async {
      await Hive.deleteBoxFromDisk('accord-settings');
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    ProviderContainer makeContainer() {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container;
    }

    test('inactive by default (no consent given)', () {
      final c = makeContainer();
      expect(c.read(errorReportingControllerProvider), isFalse);
    });

    test('guarded methods are no-ops while disabled', () async {
      final c = makeContainer();
      final reporting = c.read(errorReportingControllerProvider.notifier);
      reporting.addBreadcrumb('test message', 'test');
      reporting.spaceSelected('space_123');
      reporting.channelSelected('chan_456');
      reporting.messageSent();
      reporting.voiceError('ice failed');
      reporting.updateContext();
      await reporting.reportProblem('something broke');
      expect(reporting.lastEventId, isEmpty);
      expect(c.read(errorReportingControllerProvider), isFalse);
    });

    test('the settings toggle activates reporting and stamps consent', () {
      final c = makeContainer();
      final settings = c.read(settingsControllerProvider.notifier);
      expect(
        c.read(settingsControllerProvider).errorReportingConsentShown,
        isFalse,
      );

      settings.setErrorReportingEnabled(true);
      final state = c.read(settingsControllerProvider);
      expect(state.errorReportingEnabled, isTrue);
      expect(state.errorReportingConsentShown, isTrue);
      // Activation parses the DSN only — no network happens until an event is
      // actually captured.
      expect(c.read(errorReportingControllerProvider), isTrue);

      settings.setErrorReportingEnabled(false);
      expect(c.read(errorReportingControllerProvider), isFalse);
    });

    test('markErrorReportingConsentShown leaves the toggle off', () {
      final c = makeContainer();
      c
          .read(settingsControllerProvider.notifier)
          .markErrorReportingConsentShown();
      final state = c.read(settingsControllerProvider);
      expect(state.errorReportingConsentShown, isTrue);
      expect(state.errorReportingEnabled, isFalse);
    });
  });

  group('GlitchTipClient', () {
    const validDsn = 'https://abc123@crash.example.com/2';
    const legacyDsn = 'https://pubkey:secret@crash.example.com/2';
    const prefixedDsn = 'https://abc123@crash.example.com/sentry/3';

    group('init / _parseDsn', () {
      test('accepts a standard DSN and derives the store URL', () {
        final c = GlitchTipClient();
        expect(c.init(validDsn), isTrue);
        expect(c.isInitialized, isTrue);
        expect(c.storeUrl, 'https://crash.example.com/api/2/store/');
      });

      test('only uses the public key when DSN has key:secret format', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        expect(c.init(legacyDsn), isTrue);
        await c.captureMessage('test');
        expect(requests, hasLength(1));
        final auth = requests.first.headers['X-Sentry-Auth']!;
        expect(auth, contains('sentry_key=pubkey'));
        expect(auth, isNot(contains('secret')));
      });

      test('accepts a DSN with a path prefix', () {
        final c = GlitchTipClient();
        expect(c.init(prefixedDsn), isTrue);
        expect(c.storeUrl, 'https://crash.example.com/sentry/api/3/store/');
      });

      test('rejects blank DSN', () {
        final c = GlitchTipClient();
        expect(c.init(''), isFalse);
        expect(c.isInitialized, isFalse);
      });

      test('rejects DSN with no path segment (missing project ID)', () {
        final c = GlitchTipClient();
        expect(c.init('https://key@crash.example.com'), isFalse);
      });

      test('rejects non-HTTP scheme', () {
        final c = GlitchTipClient();
        expect(c.init('ftp://key@crash.example.com/1'), isFalse);
      });
    });

    group('addBreadcrumb ring buffer', () {
      test('retains up to maxBreadcrumbs entries', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        c.init(validDsn);
        for (var i = 0; i < GlitchTipClient.maxBreadcrumbs + 10; i++) {
          c.addBreadcrumb('msg $i', 'test');
        }
        await c.captureMessage('flush');
        final body = jsonDecode(requests.first.body) as Map<String, dynamic>;
        final crumbs =
            (body['breadcrumbs']['values'] as List).cast<Map<String, dynamic>>();
        expect(crumbs, hasLength(GlitchTipClient.maxBreadcrumbs));
        expect(crumbs.last['message'], 'msg ${GlitchTipClient.maxBreadcrumbs + 9}');
      });
    });

    group('captureMessage', () {
      test('posts a JSON event with the correct level and message', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        c.init(validDsn);
        await c.captureMessage('hello world');
        expect(requests, hasLength(1));
        final req = requests.first;
        expect(req.url.toString(), c.storeUrl);
        expect(req.headers['Content-Type'], 'application/json');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['level'], 'info');
        expect((body['message'] as Map)['formatted'], 'hello world');
        expect(body['event_id'], isNotEmpty);
      });

      test('is a no-op when not initialized', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        await c.captureMessage('should not send');
        expect(requests, isEmpty);
      });
    });

    group('captureError', () {
      test('attaches parsed stack frames when stack is provided', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        c.init(validDsn);
        const stack = '#0      main (file:///app/lib/main.dart:10:5)\n'
            '#1      runApp (file:///app/lib/main.dart:5:3)';
        await c.captureError('oops', stack: stack);
        final body =
            jsonDecode(requests.first.body) as Map<String, dynamic>;
        expect(body['level'], 'error');
        final frames = (body['exception']['values'][0]['stacktrace']['frames']
            as List).cast<Map<String, dynamic>>();
        expect(frames, hasLength(2));
        // Sentry expects oldest frame first.
        expect(frames.first['function'], 'runApp');
        expect(frames.last['function'], 'main');
      });

      test('omits exception key when stack is empty', () async {
        final requests = <http.Request>[];
        final c = GlitchTipClient(
          httpClient: MockClient((req) async {
            requests.add(req);
            return http.Response('{}', 200);
          }),
        );
        c.init(validDsn);
        await c.captureError('oops');
        final body =
            jsonDecode(requests.first.body) as Map<String, dynamic>;
        expect(body.containsKey('exception'), isFalse);
      });
    });

    group('parseStackFrames', () {
      test('parses standard Dart frame lines', () {
        const input = '#0      doThing (package:app/src/foo.dart:42:13)\n'
            '#1      main (file:///app/main.dart:10:5)';
        final frames = GlitchTipClient.parseStackFrames(input);
        // Reversed so oldest (main) comes first.
        expect(frames, hasLength(2));
        expect(frames[0]['function'], 'main');
        expect(frames[0]['filename'], 'file:///app/main.dart');
        expect(frames[0]['lineno'], 10);
        expect(frames[1]['function'], 'doThing');
        expect(frames[1]['filename'], 'package:app/src/foo.dart');
        expect(frames[1]['lineno'], 42);
      });

      test('keeps async-suspension markers as filename-only frames', () {
        const input = '#0      foo (package:app/foo.dart:1)\n'
            '<asynchronous suspension>';
        final frames = GlitchTipClient.parseStackFrames(input);
        expect(frames, hasLength(2));
        expect(frames[0]['filename'], '<asynchronous suspension>');
        expect(frames[0].containsKey('function'), isFalse);
      });

      test('returns empty list for blank input', () {
        expect(GlitchTipClient.parseStackFrames(''), isEmpty);
        expect(GlitchTipClient.parseStackFrames('   \n  '), isEmpty);
      });
    });
  });

  group('AccordSettings round-trip', () {
    test('error-reporting flags survive toJson -> fromJson', () {
      const settings = AccordSettings(
        errorReportingEnabled: true,
        errorReportingConsentShown: true,
      );
      final restored = AccordSettings.fromJson(settings.toJson());
      expect(restored.errorReportingEnabled, isTrue);
      expect(restored.errorReportingConsentShown, isTrue);
    });

    test('error-reporting flags default to off', () {
      final restored = AccordSettings.fromJson(const {});
      expect(restored.errorReportingEnabled, isFalse);
      expect(restored.errorReportingConsentShown, isFalse);
    });
  });
}
