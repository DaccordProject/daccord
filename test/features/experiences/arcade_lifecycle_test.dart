import 'dart:async';
import 'dart:convert';
import 'reference_fixture.dart';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/experiences/views/experience_canvas.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Auth extends AccordAuth {
  final AccordClient client;
  final AccordSession session;
  _Auth(this.client, this.session);
  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: client, session: session);
  @override
  AccordClient? clientForKey(String key) => key == session.key ? client : null;
}

class _Connections extends ConnectionsController {
  final AccordSession session;
  _Connections(this.session);
  @override
  ConnectionsState build() => ConnectionsState(
    activeKey: session.key,
    connections: [
      AccordConnection(session: session, status: ConnectionStatus.ready),
    ],
  );
}

Future<void> frameUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) return;
  }
  fail('The bounded host did not reach the expected state');
}

void main() {
  late Map<String, dynamic> release;
  late Map<String, dynamic> snapshot;
  late AccordSession account;
  setUpAll(() async {
    final payload = utf8.encode(referenceChessPackage);
    final algorithm = Ed25519();
    final key = await algorithm.newKeyPairFromSeed(List.filled(32, 1));
    final public = await key.extractPublicKey();
    final signature = await algorithm.sign(payload, keyPair: key);
    String hex(List<int> bytes) =>
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final digest = sha256.convert(payload).toString();
    release = {
      'status': 'approved',
      'digest': digest,
      'payload': base64Encode(payload),
      'verification_key': hex(public.bytes),
      'signature': hex(signature.bytes),
    };
    snapshot = {
      'id': 'session',
      'space_id': 'space',
      'game_id': 'chess',
      'version': '1.0.0',
      'digest': digest,
      'mode': 'turn_based',
      'state': 'running',
      'host_user_id': 'owner',
      'revision': 1,
      'turn_user_id': 'owner',
      'participants': [
        {'user_id': 'owner', 'role': 'player', 'slot': 0, 'ready': true},
      ],
      'game': {'board': List.filled(64, 0)},
    };
    account = AccordSession(
      server: AccordServer.fromBaseUrl('https://arcade.test'),
      token: 'host-only-fixture',
      tokenType: 'Bearer',
      userId: 'owner',
      username: 'owner',
    );
  });
  Widget scope(AccordClient client) => ProviderScope(
    overrides: [
      accordAuthProvider.overrideWith(() => _Auth(client, account)),
      connectionsControllerProvider.overrideWith(() => _Connections(account)),
    ],
    child: MaterialApp(
      home: ExperienceSessionView(
        serverKey: account.key,
        spaceId: 'space',
        initialSession: AccordExperienceSession.fromJson(snapshot),
      ),
    ),
  );
  testWidgets(
    'covering a game stops execution; returning revalidates; account switch clears it',
    (tester) async {
      var packages = 0;
      final client = AccordClient(
        baseUrl: account.server.baseUrl,
        token: account.token,
        tokenType: 'Bearer',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/package')) {
            packages++;
            return http.Response(jsonEncode({'data': release}), 200);
          }
          return http.Response(jsonEncode({'data': snapshot}), 200);
        }),
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(scope(client));
      await frameUntil(
        tester,
        () => find.byType(ExperienceCanvas).evaluate().isNotEmpty,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExperienceSessionView)),
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push<void>(
          MaterialPageRoute(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = packages;
      await tester.pump(const Duration(seconds: 6));
      expect(packages, before);
      expect(find.byType(ExperienceCanvas, skipOffstage: false), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      await frameUntil(
        tester,
        () => find.byType(ExperienceCanvas).evaluate().isNotEmpty,
      );
      expect(packages, greaterThan(before));
      container
          .read(connectionsControllerProvider.notifier)
          .setActive('different-account');
      await tester.pump();
      expect(find.byType(ExperienceCanvas, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'a late package response cannot restore a grant after account switch',
    (tester) async {
      final pending = Completer<http.Response>();
      var requested = false;
      final client = AccordClient(
        baseUrl: account.server.baseUrl,
        token: account.token,
        tokenType: 'Bearer',
        httpClient: MockClient((request) {
          if (request.url.path.endsWith('/package')) {
            requested = true;
            return pending.future;
          }
          return Future.value(
            http.Response(jsonEncode({'data': snapshot}), 200),
          );
        }),
      );
      addTearDown(client.dispose);
      await tester.pumpWidget(scope(client));
      await frameUntil(tester, () => requested);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ExperienceSessionView)),
      );
      container
          .read(connectionsControllerProvider.notifier)
          .setActive('different-account');
      await tester.pump();
      pending.complete(http.Response(jsonEncode({'data': release}), 200));
      await tester.pumpAndSettle();
      expect(find.byType(ExperienceCanvas, skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
