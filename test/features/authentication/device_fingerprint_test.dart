import 'dart:convert';
import 'dart:math';

import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:bonfire/features/authentication/services/device_fingerprint.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A vault whose platform storage is unavailable.
class _BrokenVault extends PlatformSessionCredentialVault {
  @override
  Future<String?> readKey(String key) async => throw StateError('no vault');

  @override
  Future<void> writeKey(String key, String value) async =>
      throw StateError('no vault');
}

void main() {
  final hex64 = RegExp(r'^[0-9a-f]{64}$');

  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('derives a per-server SHA-256 over the canonical origin', () {
    final fingerprint = DeviceFingerprint.derive(
      'raw-id',
      'https://chat.example',
    );
    expect(fingerprint, matches(hex64));
    expect(
      fingerprint,
      sha256
          .convert(
            utf8.encode('daccord-device-v1\nraw-id\nhttps://chat.example'),
          )
          .toString(),
    );
    // Equivalent spellings of one server agree...
    expect(DeviceFingerprint.derive('raw-id', 'chat.example/'), fingerprint);
    // ...but another server, port or scheme can't link the device.
    expect(
      DeviceFingerprint.derive('raw-id', 'https://other.example'),
      isNot(fingerprint),
    );
    expect(
      DeviceFingerprint.derive('raw-id', 'https://chat.example:8443'),
      isNot(fingerprint),
    );
  });

  test('resolves the platform id once and caches it', () async {
    var calls = 0;
    final service = DeviceFingerprint(
      platformId: () async {
        calls++;
        return ' machine-id ';
      },
    );

    final first = await service.forServer('https://a.example');
    final second = await service.forServer('https://b.example');

    expect(calls, 1);
    expect(await service.rawId(), 'machine-id');
    expect(first, DeviceFingerprint.derive('machine-id', 'https://a.example'));
    expect(second, isNot(first));
  });

  test('falls back to a generated id persisted in the vault', () async {
    final service = DeviceFingerprint(
      platformId: () async => null,
      random: Random(1),
    );
    final id = await service.rawId();
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(
      await PlatformSessionCredentialVault().readKey(
        DeviceFingerprint.storageKey,
      ),
      id,
    );

    // A fresh process (new service) reuses the stored id, even when the
    // platform id lookup throws.
    final restarted = DeviceFingerprint(
      platformId: () async => throw StateError('no channel'),
    );
    expect(await restarted.rawId(), id);
  });

  test('omits the fingerprint when no id can be resolved or stored', () async {
    final service = DeviceFingerprint(
      platformId: () async => '',
      vault: _BrokenVault(),
    );
    expect(await service.forServer('https://a.example'), isNull);
  });
}
