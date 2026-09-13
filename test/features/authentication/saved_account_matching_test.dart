import 'dart:async';
import 'dart:io';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _SavedSessions extends AccordSessionStore {
  _SavedSessions(this.accounts, {this.active});

  final List<AccordSession> accounts;
  AccordSession? active;
  Completer<void>? reading;

  @override
  Future<List<AccordSession>> listAccounts() async {
    await reading?.future;
    return accounts;
  }

  @override
  Future<AccordSession?> readRestorableActive() async => active;
}

AccordSession _session(String base, String user) => AccordSession(
  server: AccordServer.fromBaseUrl(base),
  token: 'saved-$user-token',
  userId: user,
  username: user,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('endpoint identity normalizes spelling without crossing origins', () {
    for (final equivalent in [
      'CHAT.Example',
      ' HTTPS://CHAT.Example:443/// ',
      'https://chat.example/',
    ]) {
      expect(AccordServer.sameEndpoint(equivalent, 'https://chat.example'), isTrue);
    }
    expect(AccordServer.sameEndpoint('http://localhost:80/', 'http://LOCALHOST'), isTrue);
    expect(AccordServer.sameEndpoint('http://localhost', 'https://localhost'), isFalse);
    for (final different in [
      'https://chat.example:8443',
      'https://elsewhere.example',
      'https://chat.example/another-instance',
    ]) {
      expect(AccordServer.sameEndpoint(different, 'https://chat.example'), isFalse);
    }
    expect(AccordServer.sameEndpoint('https://chat.example/Team', 'https://chat.example/team'), isFalse);
  });

  AccordAuth authFor(_SavedSessions store) {
    final container = ProviderContainer(overrides: [
      accordAuthProvider.overrideWith(() => AccordAuth(sessionStore: store)),
    ]);
    addTearDown(container.dispose);
    return container.read(accordAuthProvider.notifier);
  }

  test('saved account matches before any live connection has been restored', () async {
    final saved = _session('https://chat.example/', 'saved-user');
    final auth = authFor(_SavedSessions([saved]));
    expect(auth.keyForBaseUrl(saved.server.baseUrl), isNull);
    expect(auth.clientForKey(saved.key), isNull);
    expect(await auth.accountForBaseUrl('https://CHAT.example:443'), same(saved));
    expect(await auth.accountForBaseUrl('https://unknown.example'), isNull);
  });

  test('persisted active account wins over an earlier saved account', () async {
    final first = _session('https://chat.example', 'first');
    final active = _session('https://CHAT.example:443/', 'active');
    final auth = authFor(_SavedSessions([first, active], active: active));
    expect(await auth.accountForBaseUrl('chat.example'), same(active));
  });

  test('a pending vault read does not report an absent saved account', () async {
    final saved = _session('https://chat.example', 'saved-user');
    final store = _SavedSessions([saved])..reading = Completer<void>();
    final auth = authFor(store);
    var completed = false;
    final lookup = auth.accountForBaseUrl('chat.example').then((value) {
      completed = true;
      return value;
    });
    await Future<void>.value();
    expect(completed, isFalse);
    store.reading!.complete();
    expect(await lookup, same(saved));
    expect(auth.client, isNull);
  });

  test('concurrent empty startup restores share the same attempt', () async {
    final auth = authFor(_SavedSessions([]));
    final first = auth.restoreSession();
    final second = auth.restoreSession();
    expect(identical(first, second), isTrue);
    expect(await first, isA<AccordAuthLoggedOut>());
  });

  test('on-demand reconnect creates one client without changing active auth', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
    final saved = _session('http://127.0.0.1:${server.port}', 'saved-user');
    final store = _SavedSessions([saved]);
    final container = ProviderContainer(overrides: [
      accordAuthProvider.overrideWith(() => AccordAuth(
        sessionStore: store,
      )),
    ]);
    final auth = container.read(accordAuthProvider.notifier);
    try {
      final keys = await Future.wait([
        auth.ensureConnectionForBaseUrl(saved.server.baseUrl),
        auth.ensureConnectionForBaseUrl('${saved.server.baseUrl}/'),
      ]);
      expect(keys, [saved.key, saved.key]);
      expect(auth.clientForKey(saved.key), isNotNull);
      expect(container.read(connectionsControllerProvider).connections, hasLength(1));
      expect(container.read(connectionsControllerProvider).activeKey, isNull);
      expect(container.read(accordAuthProvider), isA<AccordAuthLoggedOut>());
      final active = _session(saved.server.baseUrl, 'active-user');
      store.active = active;
      expect(await auth.accountForBaseUrl(saved.server.baseUrl), same(active));
      await auth.clientForKey(saved.key)!.dispose();
    } finally {
      container.dispose();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    }
  });
}
