import 'dart:io';

import 'package:bonfire/features/error_reporting/controllers/error_reporting.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/settings/models/accord_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

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
