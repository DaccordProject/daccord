import 'dart:io';

import 'package:bonfire/features/updates/controllers/release_notes_controller.dart';
import 'package:bonfire/shared/app_info.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A GitHub `releases/tags/...` payload with [body] as the notes.
String _releaseJson(String tag, String body) =>
    '{"tag_name":"$tag","name":"$tag","body":"$body",'
    '"html_url":"https://example/releases/$tag","published_at":"","assets":[]}';

late Directory _tempDir;

ProviderContainer _container() {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c;
}

ReleaseNotesController _notifier(ProviderContainer c) =>
    c.read(releaseNotesControllerProvider.notifier);

void main() {
  // The persisted marker lives in the existing `accord-settings` box (its own
  // key, not part of AccordSettings) — see ReleaseNotesController.
  setUp(() async {
    _tempDir = Directory.systemTemp.createTempSync('release-notes-test');
    Hive.init(_tempDir.path);
    await Hive.openBox('accord-settings');
  });

  tearDown(() async {
    ReleaseNotesController.debugHttpClient = null;
    kAppVersion = '0.0.0';
    await Hive.deleteBoxFromDisk('accord-settings');
    await Hive.close();
    if (_tempDir.existsSync()) _tempDir.deleteSync(recursive: true);
  });

  group('releaseNotesTrigger', () {
    test('first install (no marker) never shows notes', () {
      expect(
        releaseNotesTrigger(lastSeenVersion: '', currentVersion: '1.2.0'),
        ReleaseNotesTrigger.firstInstall,
      );
    });

    test('same version does not show notes again', () {
      expect(
        releaseNotesTrigger(lastSeenVersion: '1.2.0', currentVersion: '1.2.0'),
        ReleaseNotesTrigger.unchanged,
      );
      // A stored `v`-prefixed marker is the same version, not an update.
      expect(
        releaseNotesTrigger(lastSeenVersion: 'v1.2.0', currentVersion: '1.2.0'),
        ReleaseNotesTrigger.unchanged,
      );
    });

    test('a newer running build shows notes', () {
      expect(
        releaseNotesTrigger(lastSeenVersion: '1.2.0', currentVersion: '1.2.1'),
        ReleaseNotesTrigger.updated,
      );
      expect(
        releaseNotesTrigger(lastSeenVersion: '0.9.9', currentVersion: '1.0.0'),
        ReleaseNotesTrigger.updated,
      );
    });

    test('a prerelease → stable change on the same core counts as an update', () {
      expect(
        releaseNotesTrigger(
          lastSeenVersion: '1.2.0-beta.1',
          currentVersion: '1.2.0',
        ),
        ReleaseNotesTrigger.updated,
      );
    });

    test('a downgrade shows nothing', () {
      expect(
        releaseNotesTrigger(lastSeenVersion: '2.0.0', currentVersion: '1.9.0'),
        ReleaseNotesTrigger.downgraded,
      );
    });

    test('an unknown running version (0.0.0 fallback) shows nothing', () {
      expect(
        releaseNotesTrigger(lastSeenVersion: '1.0.0', currentVersion: '0.0.0'),
        ReleaseNotesTrigger.unknownVersion,
      );
      expect(
        releaseNotesTrigger(lastSeenVersion: '1.0.0', currentVersion: ''),
        ReleaseNotesTrigger.unknownVersion,
      );
    });
  });

  group('maybeLoadOnStartup', () {
    test('first install: stamps the marker and fetches nothing', () async {
      kAppVersion = '1.2.0';
      var requests = 0;
      ReleaseNotesController.debugHttpClient = MockClient((_) async {
        requests++;
        return http.Response(_releaseJson('v1.2.0', 'hello'), 200);
      });
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(requests, 0);
      expect(_notifier(c).lastSeenVersion, '1.2.0');
    });

    test('same version: nothing shown, nothing fetched', () async {
      kAppVersion = '1.2.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      var requests = 0;
      ReleaseNotesController.debugHttpClient = MockClient((_) async {
        requests++;
        return http.Response(_releaseJson('v1.2.0', 'hello'), 200);
      });
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(requests, 0);
    });

    test('version increased: fetches the running tag and returns the notes',
        () async {
      kAppVersion = '1.3.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      Uri? requested;
      ReleaseNotesController.debugHttpClient = MockClient((req) async {
        requested = req.url;
        return http.Response(
          _releaseJson('v1.3.0', '## Fixed\\n- things'),
          200,
        );
      });
      final c = _container();
      final release = await _notifier(c).maybeLoadOnStartup();
      expect(release, isNotNull);
      expect(release!.version, '1.3.0');
      expect(release.notes, contains('Fixed'));
      // Notes come from the *running* tag, not `releases/latest`.
      expect(requested.toString(), endsWith('/releases/tags/v1.3.0'));
      // Marker stamped → a second launch on the same build shows nothing.
      expect(_notifier(c).lastSeenVersion, '1.3.0');
    });

    test('is a no-op the second time it runs in one session', () async {
      kAppVersion = '1.3.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      ReleaseNotesController.debugHttpClient = MockClient(
        (_) async => http.Response(_releaseJson('v1.3.0', 'notes'), 200),
      );
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNotNull);
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
    });

    test('downgrade: no notes, but the marker follows the running build',
        () async {
      kAppVersion = '1.1.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '2.0.0');
      var requests = 0;
      ReleaseNotesController.debugHttpClient = MockClient((_) async {
        requests++;
        return http.Response(_releaseJson('v1.1.0', 'notes'), 200);
      });
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(requests, 0);
      // Restamped, so upgrading forward again re-shows that release's notes.
      expect(_notifier(c).lastSeenVersion, '1.1.0');
    });

    test('unknown running version: neither shows nor stamps', () async {
      kAppVersion = '0.0.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(_notifier(c).lastSeenVersion, '1.2.0');
    });

    test('a 404 (no such release) fails silent but still stamps', () async {
      kAppVersion = '1.3.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      ReleaseNotesController.debugHttpClient = MockClient(
        (_) async => http.Response('{"message":"Not Found"}', 404),
      );
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(_notifier(c).lastSeenVersion, '1.3.0');
    });

    test('a network failure fails silent but still stamps', () async {
      kAppVersion = '1.3.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      ReleaseNotesController.debugHttpClient = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
      expect(_notifier(c).lastSeenVersion, '1.3.0');
    });

    test('an empty release body shows nothing', () async {
      kAppVersion = '1.3.0';
      Hive.box('accord-settings').put('release-notes-seen-version', '1.2.0');
      ReleaseNotesController.debugHttpClient = MockClient(
        (_) async => http.Response(_releaseJson('v1.3.0', ''), 200),
      );
      final c = _container();
      expect(await _notifier(c).maybeLoadOnStartup(), isNull);
    });
  });

  group('loadNotesForCurrentVersion', () {
    test('caches the result and re-fetches only when forced', () async {
      kAppVersion = '1.3.0';
      var requests = 0;
      ReleaseNotesController.debugHttpClient = MockClient((_) async {
        requests++;
        return http.Response(_releaseJson('v1.3.0', 'notes'), 200);
      });
      final c = _container();
      expect((await _notifier(c).loadNotesForCurrentVersion())?.notes, 'notes');
      await _notifier(c).loadNotesForCurrentVersion();
      expect(requests, 1);
      expect(c.read(releaseNotesControllerProvider).hasNotes, isTrue);
      await _notifier(c).loadNotesForCurrentVersion(force: true);
      expect(requests, 2);
    });

    test('never calls GitHub for the 0.0.0 fallback version', () async {
      kAppVersion = '0.0.0';
      var requests = 0;
      ReleaseNotesController.debugHttpClient = MockClient((_) async {
        requests++;
        return http.Response(_releaseJson('v0.0.0', 'notes'), 200);
      });
      final c = _container();
      expect(await _notifier(c).loadNotesForCurrentVersion(), isNull);
      expect(requests, 0);
    });
  });
}
