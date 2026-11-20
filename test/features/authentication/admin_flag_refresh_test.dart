import 'dart:io';
import 'package:accordkit/accordkit.dart';

import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_session_store.dart';
import 'package:bonfire/features/profiles/services/profile_store.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

/// In-memory store: records metadata rewrites instead of touching Hive.
class _RecordingStore extends AccordSessionStore {
  _RecordingStore(this.accounts);

  final List<AccordSession> accounts;
  final updated = <AccordSession>[];

  @override
  Future<List<AccordSession>> listAccounts() async => accounts;

  @override
  Future<AccordSession?> readRestorableActive() async => null;

  @override
  Future<void> persistActive(AccordSession session) async {}

  @override
  Future<void> updateMetadata(AccordSession session) async {
    updated.add(session);
  }
}

Map<String, dynamic> _ready(String userId, {required bool isAdmin}) => {
  'user': {'id': userId, 'username': userId, 'is_admin': isAdmin},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpServer server;
  late List<WebSocket> sockets;
  late Directory hiveRoot;

  setUp(() async {
    // Activating a connection reads the profile's settings box.
    hiveRoot = await Directory.systemTemp.createTemp('daccord-admin-flag-');
    Hive.init(hiveRoot.path);
    await ProfileStore.bootstrap(hiveRoot.path);
    sockets = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        sockets.add(await WebSocketTransformer.upgrade(request));
      } else {
        request.response.statusCode = 404;
        await request.response.close();
      }
    });
  });

  tearDown(() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
    await Hive.close();
    if (hiveRoot.existsSync()) hiveRoot.deleteSync(recursive: true);
  });

  Future<
    ({ProviderContainer container, AccordAuth auth, _RecordingStore store})
  >
  connect(AccordSession saved) async {
    final store = _RecordingStore([saved]);
    final container = ProviderContainer(
      overrides: [
        accordAuthProvider.overrideWith(() => AccordAuth(sessionStore: store)),
      ],
    );
    addTearDown(container.dispose);
    final auth = container.read(accordAuthProvider.notifier);
    await auth.ensureConnectionForBaseUrl(saved.server.baseUrl);
    return (container: container, auth: auth, store: store);
  }

  AccordSession saved({bool isAdmin = false}) => AccordSession(
    server: AccordServer.fromBaseUrl('http://127.0.0.1:${server.port}'),
    token: 'saved-token',
    userId: 'u1',
    username: 'u1',
    isAdmin: isAdmin,
  );

  test(
    'READY grants a saved session the admin flag without sign-out',
    () async {
      final session = saved();
      final (:container, :auth, :store) = await connect(session);
      auth.setActiveServer(session.key);
      final client = auth.clientForKey(session.key)!;

      auth.syncSelfFromReady(session.key, client, _ready('u1', isAdmin: true));

      final state = container.read(accordAuthProvider);
      expect(state, isA<AccordAuthLoggedIn>());
      expect((state as AccordAuthLoggedIn).session.isAdmin, isTrue);
      expect(
        container
            .read(connectionsControllerProvider)
            .connectionFor(session.key)
            ?.session
            .isAdmin,
        isTrue,
      );
      expect(store.updated.single.isAdmin, isTrue);
      expect(store.updated.single.token, 'saved-token');
      await client.dispose();
    },
  );

  test('READY revokes the flag on a background connection', () async {
    final session = saved(isAdmin: true);
    final (:container, :auth, :store) = await connect(session);
    final client = auth.clientForKey(session.key)!;

    auth.syncSelfFromReady(session.key, client, _ready('u1', isAdmin: false));

    expect(
      container
          .read(connectionsControllerProvider)
          .connectionFor(session.key)
          ?.session
          .isAdmin,
      isFalse,
    );
    // A background connection must not become the visible account.
    expect(container.read(accordAuthProvider), isA<AccordAuthLoggedOut>());
    expect(store.updated.single.isAdmin, isFalse);
    await client.dispose();
  });

  test('unchanged, foreign and stale READY payloads are ignored', () async {
    final session = saved();
    final (:container, :auth, :store) = await connect(session);
    final client = auth.clientForKey(session.key)!;

    auth.syncSelfFromReady(session.key, client, _ready('u1', isAdmin: false));
    auth.syncSelfFromReady(session.key, client, _ready('u2', isAdmin: true));
    auth.syncSelfFromReady(session.key, client, const {'user': null});
    // A READY from a client that no longer owns the connection.
    final stale = AccordClient(
      token: 'old-token',
      baseUrl: session.server.baseUrl,
      gatewayUrl: session.server.gatewayUrl,
    );
    auth.syncSelfFromReady(session.key, stale, _ready('u1', isAdmin: true));
    await stale.dispose();

    expect(store.updated, isEmpty);
    expect(
      container
          .read(connectionsControllerProvider)
          .connectionFor(session.key)
          ?.session
          .isAdmin,
      isFalse,
    );
    await client.dispose();
  });
}
