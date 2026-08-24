import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory temporary;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('daccord-guest-session-');
    Hive.init(temporary.path);
  });

  tearDown(() async {
    await Hive.close();
    temporary.deleteSync(recursive: true);
  });

  AccordSession session({bool guest = false, DateTime? expiresAt}) =>
      AccordSession(
        server: AccordServer.fromBaseUrl('https://accord.example.test'),
        token: guest ? 'guest-secret' : 'user-secret',
        userId: guest ? 'guest' : 'user',
        username: guest ? 'Guest' : 'User',
        isGuest: guest,
        expiresAt: expiresAt,
      );

  test('guest credentials never survive a restart', () async {
    final store = AccordSessionStore();
    await store.persist(session(guest: true));
    await store.persistActive(session(guest: true));

    expect(await store.readRestorableActive(), isNull);
    expect(await store.listAccounts(), isEmpty);
    expect(
      (await Hive.openBox('accord-session')).toMap().toString(),
      isNot(contains('guest-secret')),
    );
  });

  test(
    'legacy guest and expired active records are purged on restore',
    () async {
      final store = AccordSessionStore();
      final box = await Hive.openBox('accord-session');
      await box.put('session', session(guest: true).toJson());
      expect(await store.readRestorableActive(), isNull);
      expect(box.containsKey('session'), isFalse);

      await box.put('session', session(expiresAt: DateTime.utc(2020)).toJson());
      expect(await store.readRestorableActive(), isNull);
      expect(box.containsKey('session'), isFalse);
    },
  );

  test('guest expiry supports endpoint fields and JWT exp', () {
    final now = DateTime.utc(2026, 8, 24, 10);
    expect(
      guestSessionExpiry({'expires_in': 90}, 'opaque', now: now),
      now.add(const Duration(seconds: 90)),
    );
    expect(
      guestSessionExpiry({'expires_at': '2026-08-24T12:00:00Z'}, 'opaque'),
      DateTime.utc(2026, 8, 24, 12),
    );

    final payload = base64Url.encode(
      utf8.encode(jsonEncode({'exp': 1787562000})),
    );
    expect(
      guestSessionExpiry({}, 'header.$payload.signature'),
      DateTime.fromMillisecondsSinceEpoch(1787562000000, isUtc: true),
    );
  });

  test('guest entry point stays hidden until write restrictions are wired', () {
    final login = File(
      'lib/features/authentication/views/accord_login.dart',
    ).readAsStringSync();
    expect(login, isNot(contains("Text('Browse as guest'")));
  });
}
