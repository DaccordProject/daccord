import 'dart:io';

import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:bonfire/features/profiles/models/device_profile.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class MemoryCredentialVault implements SessionCredentialVault {
  final values = <String, String>{};
  Object? writeError;

  @override
  Future<void> write(String reference, String token) async {
    if (writeError case final error?) throw error;
    values[reference] = token;
  }

  @override
  Future<String?> read(String reference) async => values[reference];

  @override
  Future<void> delete(String reference) async {
    values.remove(reference);
  }
}

AccordSession session({String token = 'super-secret-token'}) => AccordSession(
  server: AccordServer.fromBaseUrl('https://accord.example.test'),
  token: token,
  userId: 'user-1',
  username: 'User',
);

void main() {
  late Directory temporary;
  late MemoryCredentialVault vault;
  late AccordSessionStore store;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('daccord-vault-test-');
    Hive.init(temporary.path);
    vault = MemoryCredentialVault();
    store = AccordSessionStore(
      credentialVault: vault,
      createReference: () => 'abcdefghijklmnopqrstuvwxyzABCDEF',
    );
  });

  tearDown(() async {
    await Hive.close();
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  });

  test(
    'persists only an opaque reference and restores through the vault',
    () async {
      await store.persist(session());
      final box = await Hive.openBox('accord-session');
      final persisted = box.toMap().toString();

      expect(persisted, isNot(contains('super-secret-token')));
      expect(persisted, contains('credentialRef'));
      expect(vault.values.values, contains('super-secret-token'));
      expect((await store.readRestorableActive())?.token, 'super-secret-token');
      expect((await store.listAccounts()).single.token, 'super-secret-token');
    },
  );

  test(
    'migrates legacy plaintext only after the vault write succeeds',
    () async {
      final box = await Hive.openBox('accord-session');
      final legacy = session(token: 'legacy-secret').toJson();
      await box.put('session', legacy);
      await box.put('accounts', {session().key: legacy});

      expect((await store.readRestorableActive())?.token, 'legacy-secret');
      expect((await store.listAccounts()).single.token, 'legacy-secret');
      expect(box.toMap().toString(), isNot(contains('legacy-secret')));
      expect(vault.values.values, everyElement('legacy-secret'));
    },
  );

  test('a vault failure leaves legacy plaintext intact for retry', () async {
    final box = await Hive.openBox('accord-session');
    final legacy = session(token: 'recoverable-secret').toJson();
    await box.put('session', legacy);
    vault.writeError = StateError('vault locked');

    await expectLater(store.readRestorableActive(), throwsStateError);
    expect(box.get('session').toString(), contains('recoverable-secret'));
  });

  test('removing the final reference deletes the vault credential', () async {
    final value = session();
    await store.persist(value);
    expect(vault.values, isNotEmpty);

    await store.removeAccount(value.key);
    expect(
      vault.values,
      isNotEmpty,
      reason: 'active pointer still references it',
    );
    await store.deleteActive();
    expect(vault.values, isEmpty);
  });

  test(
    'a new login repairs a missing credential without changing its reference',
    () async {
      await store.persist(session());
      final reference = vault.values.keys.single;
      vault.values.clear();
      expect(await store.readRestorableActive(), isNull);
      await store.persist(session(token: 'fresh-token'));
      expect(vault.values.keys, [reference]);
      expect((await store.readRestorableActive())?.token, 'fresh-token');
    },
  );

  test(
    'the same account in two profiles retains independent credentials',
    () async {
      await ProfileStore.bootstrap(temporary.path);
      final first = AccordSessionStore(credentialVault: vault);
      await first.persist(session(token: 'default-token'));
      final firstReference = vault.values.keys.single;
      final workId = ProfileStore.create('Work');
      await ProfileStore.switchTo(workId);
      final second = AccordSessionStore(credentialVault: vault);
      await second.persist(session(token: 'work-token'));
      expect(vault.values.length, 2);
      expect((await second.readRestorableActive())?.token, 'work-token');
      await second.removeAccount(session().key);
      await second.deleteActive();
      expect(vault.values, {firstReference: 'default-token'});
      await ProfileStore.switchTo(DeviceProfile.defaultId);
      expect((await first.readRestorableActive())?.token, 'default-token');
    },
  );

  test('native packaging and Web threat documentation stay wired', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:allowBackup="false"'),
    );
    expect(
      File('dist/build-deb.sh').readAsStringSync(),
      contains('libsecret-1-0'),
    );
    for (final path in [
      'ios/Runner/DebugProfile.entitlements',
      'ios/Runner/Release.entitlements',
      'macos/Runner/DebugProfile.entitlements',
      'macos/Runner/Release.entitlements',
      'macos/Runner/AppStore.entitlements',
    ]) {
      expect(
        File(path).readAsStringSync(),
        contains('keychain-access-groups'),
        reason: path,
      );
    }
    final privacy = File('docs/privacy-network.md').readAsStringSync();
    expect(privacy, contains('non-exportable WebCrypto key'));
    expect(privacy, contains('does not fall back to plaintext storage'));
  });
}
