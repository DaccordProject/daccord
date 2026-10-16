import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/session_credential_vault.dart';
import 'package:bonfire/features/authentication/services/device_fingerprint.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// A vault whose platform storage is unavailable.
class _BrokenVault extends PlatformSessionCredentialVault {
  @override
  Future<String?> readKey(String key) async => throw StateError('no vault');

  @override
  Future<void> writeKey(String key, String value) async =>
      throw StateError('no vault');
}

void main() {
  late Directory tempDir;
  late HttpServer httpServer;
  late AccordServer server;
  late List<({String path, Map<String, dynamic> body})> requests;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('device-fingerprint-auth');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-session');
    requests = [];

    httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = AccordServer.fromBaseUrl(
      'http://${httpServer.address.address}:${httpServer.port}',
    );
    httpServer.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add((
        path: request.uri.path,
        body: jsonDecode(body) as Map<String, dynamic>,
      ));
      final response = request.response..headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/v1/auth/login':
          response.write(jsonEncode({'mfa_required': true, 'ticket': 'tk'}));
        case '/api/v1/auth/login/mfa':
          response
            ..statusCode = HttpStatus.forbidden
            ..write(
              jsonEncode({
                'error': {
                  'code': 'forbidden',
                  'message': 'sign-in is not available from this device',
                },
              }),
            );
        case '/api/v1/auth/register':
          response
            ..statusCode = HttpStatus.forbidden
            ..write(
              jsonEncode({
                'error': {
                  'code': 'forbidden',
                  'message': 'registration is not available from this device',
                },
              }),
            );
        default:
          response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
  });

  tearDown(() async {
    await httpServer.close(force: true);
    await Hive.deleteBoxFromDisk('accord-session');
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  ProviderContainer containerWith(DeviceFingerprint fingerprints) {
    final container = ProviderContainer(
      overrides: [deviceFingerprintProvider.overrideWithValue(fingerprints)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'sign-in sends the per-server fingerprint and shows a device ban verbatim',
    () async {
      final container = containerWith(
        DeviceFingerprint(platformId: () async => 'device-1'),
      );
      final auth = container.read(accordAuthProvider.notifier);
      final expected = DeviceFingerprint.derive('device-1', server.baseUrl);

      final challenge = await auth.loginWithCredentials(
        server: server,
        username: 'alice',
        password: 'password123',
      );
      expect(challenge, isA<AccordAuthMfaRequired>());
      final result = await auth.submitMfa('123456');

      expect(requests.map((r) => r.path), [
        '/api/v1/auth/login',
        '/api/v1/auth/login/mfa',
      ]);
      for (final request in requests) {
        expect(request.body['device_fingerprint'], expected);
      }
      expect(result, isA<AccordAuthFailed>());
      expect(
        (result as AccordAuthFailed).message,
        'sign-in is not available from this device',
      );
    },
  );

  test(
    'registration omits the field when no fingerprint is available',
    () async {
      final container = containerWith(
        DeviceFingerprint(platformId: () async => null, vault: _BrokenVault()),
      );
      final auth = container.read(accordAuthProvider.notifier);

      final result = await auth.registerWithCredentials(
        server: server,
        username: 'alice',
        password: 'password123',
      );

      expect(requests.single.path, '/api/v1/auth/register');
      expect(requests.single.body.containsKey('device_fingerprint'), isFalse);
      expect(requests.single.body['username'], 'alice');
      expect(
        (result as AccordAuthFailed).message,
        'registration is not available from this device',
      );
    },
  );
}
