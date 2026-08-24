import 'dart:convert';
import 'dart:io';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

class _LoggedInAuth extends AccordAuth {
  _LoggedInAuth(this.initial);

  final AccordAuthLoggedIn initial;

  @override
  AccordAuthState build() => initial;
}

void main() {
  late Directory tempDir;
  late HttpServer httpServer;
  late AccordServer server;
  late String? changePasswordAuthorization;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('force-password-reset-test');
    Hive.init(tempDir.path);
    await Hive.openBox('accord-session');
    changePasswordAuthorization = null;

    httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server = AccordServer.fromBaseUrl(
      'http://${httpServer.address.address}:${httpServer.port}',
    );
    httpServer.listen((request) async {
      if (request.uri.path == '/api/v1/auth/login') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'user': {'id': 'reset-user', 'username': 'reset-user'},
              'token': 'temporary-token',
              'force_password_reset': true,
            }),
          );
      } else if (request.uri.path == '/api/v1/auth/change-password') {
        changePasswordAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'message': 'Password rejected'}));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await httpServer.close(force: true);
    await Hive.deleteBoxFromDisk('accord-session');
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test(
    'primary login exposes reset challenge without saving a session',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final auth = container.read(accordAuthProvider.notifier);

      final result = await auth.loginWithCredentials(
        server: server,
        username: 'reset-user',
        password: 'temporary-password',
      );

      expect(result, isA<AccordAuthPasswordResetRequired>());
      final reset = result as AccordAuthPasswordResetRequired;
      expect(reset.pending.token, 'temporary-token');
      expect(container.read(accordAuthProvider), same(result));
      expect(auth.client, isNull);
      expect(auth.keyForBaseUrl(server.baseUrl), isNull);
      expect(Hive.box('accord-session').get('session'), isNull);
      expect(Hive.box('accord-session').get('accounts'), isNull);
    },
  );

  test(
    'add-server login preserves the active session until reset succeeds',
    () async {
      final existingServer = AccordServer.fromBaseUrl(
        'https://existing.example',
      );
      final existingSession = AccordSession(
        server: existingServer,
        token: 'existing-token',
        userId: 'existing-user',
        username: 'Existing User',
      );
      final existingClient = AccordClient(
        token: existingSession.token,
        baseUrl: existingServer.baseUrl,
      );
      addTearDown(existingClient.dispose);
      final initial = AccordAuthLoggedIn(
        client: existingClient,
        session: existingSession,
      );
      final container = ProviderContainer(
        overrides: [
          accordAuthProvider.overrideWith(() => _LoggedInAuth(initial)),
        ],
      );
      addTearDown(container.dispose);
      final auth = container.read(accordAuthProvider.notifier);

      final result = await auth.addServerWithCredentials(
        server: server,
        username: 'reset-user',
        password: 'temporary-password',
      );

      expect(result.needsPasswordReset, isTrue);
      expect(result.passwordResetSession?.token, 'temporary-token');
      expect(container.read(accordAuthProvider), same(initial));
      expect(auth.keyForBaseUrl(server.baseUrl), isNull);
      expect(Hive.box('accord-session').get('session'), isNull);
      expect(Hive.box('accord-session').get('accounts'), isNull);

      final retried = await auth.addServerSubmitPasswordChange(
        pending: result.passwordResetSession!,
        oldPassword: 'temporary-password',
        newPassword: 'replacement-password',
      );

      expect(retried.needsPasswordReset, isTrue);
      expect(retried.error, isNotEmpty);
      expect(changePasswordAuthorization, 'Bearer temporary-token');
      expect(container.read(accordAuthProvider), same(initial));
      expect(auth.keyForBaseUrl(server.baseUrl), isNull);
      expect(Hive.box('accord-session').get('session'), isNull);
      expect(Hive.box('accord-session').get('accounts'), isNull);
    },
  );
}
