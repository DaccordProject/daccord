import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/services/device_fingerprint.dart';
import 'package:bonfire/features/events/services/accord_ready_sync.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _refProvider = Provider<Ref>((ref) => ref);
final _server = AccordServer.fromBaseUrl('https://accord.example.test');

void main() {
  late List<http.Request> requests;
  late int status;

  setUp(() {
    requests = [];
    status = 204;
  });

  (ProviderContainer, AccordClient) setUpConnection(
    AccordSession session, {
    void Function()? onUnauthorized,
  }) {
    final client = AccordClient(
      token: session.token,
      tokenType: session.tokenType,
      baseUrl: _server.baseUrl,
      gatewayUrl: _server.gatewayUrl,
      onUnauthorized: onUnauthorized,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('', status);
      }),
    );
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [
        deviceFingerprintProvider.overrideWithValue(
          DeviceFingerprint(platformId: () async => 'device-1'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(connectionsControllerProvider.notifier).register(session);
    return (container, client);
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  AccordSession session({bool isGuest = false, String tokenType = 'Bearer'}) =>
      AccordSession(
        server: _server,
        token: 't',
        tokenType: tokenType,
        userId: 'u-self',
        username: 'self',
        isGuest: isGuest,
      );

  test('READY records the per-server fingerprint for the session', () async {
    final s = session();
    final (container, client) = setUpConnection(s);

    registerDeviceOnReady(
      container.read(_refProvider),
      client,
      serverKey: s.key,
    );
    await settle();

    final request = requests.single;
    expect(request.method, 'PUT');
    expect(request.url.path, '/api/v1/users/@me/device');
    expect(
      request.body,
      '{"device_fingerprint":"${DeviceFingerprint.derive('device-1', _server.baseUrl)}"}',
    );
  });

  test('an older server or a banned device is not an error', () async {
    for (final code in [404, 405, 403]) {
      requests.clear();
      status = code;
      final s = session();
      final (container, client) = setUpConnection(s);
      registerDeviceOnReady(
        container.read(_refProvider),
        client,
        serverKey: s.key,
      );
      await settle();
      expect(requests, hasLength(1));
    }
  });

  test('a banned device signs the session out; an older server does not', () async {
    for (final (code, signsOut) in [(403, true), (404, false)]) {
      status = code;
      var signedOut = false;
      final s = session();
      final (container, client) = setUpConnection(
        s,
        onUnauthorized: () => signedOut = true,
      );
      registerDeviceOnReady(
        container.read(_refProvider),
        client,
        serverKey: s.key,
      );
      await settle();
      expect(signedOut, signsOut, reason: 'status $code');
    }
  });

  test('guests, bots and unknown connections are skipped', () async {
    for (final s in [session(isGuest: true), session(tokenType: 'Bot')]) {
      final (container, client) = setUpConnection(s);
      registerDeviceOnReady(
        container.read(_refProvider),
        client,
        serverKey: s.key,
      );
      registerDeviceOnReady(
        container.read(_refProvider),
        client,
        serverKey: 'someone@https://elsewhere.test',
      );
    }
    await settle();
    expect(requests, isEmpty);
  });
}
