/// Real Flutter Pong UI + reviewed directory/community transport.
/// Supply ACCORD_EXPERIENCE_TEST_URL through run_fixture.py (see validation.md).
library;

import 'dart:async';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth_state.dart';
import 'package:bonfire/features/authentication/models/accord_session.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/connection.dart';
import 'package:bonfire/features/experiences/views/arcade.dart';
import 'package:bonfire/features/experiences/views/experience_canvas.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/server/models/accord_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Auth extends AccordAuth {
  _Auth(this.client, this.session);
  @override
  final AccordClient client;
  final AccordSession session;
  @override
  AccordAuthState build() =>
      AccordAuthLoggedIn(client: client, session: session);
  @override
  AccordClient? clientForKey(String key) => key == session.key ? client : null;
}

class _Connections extends ConnectionsController {
  _Connections(this.session);
  final AccordSession session;
  @override
  ConnectionsState build() => ConnectionsState(
    activeKey: session.key,
    connections: [
      AccordConnection(session: session, status: ConnectionStatus.ready),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('ACCORD_EXPERIENCE_TEST_URL');
  testWidgets(
    'live Pong input reaches the Flutter frame; pause, reconnect and disable revoke it',
    (tester) async {
      await tester.runAsync(() async {
        final clients = <AccordClient>[];
        addTearDown(() async {
          for (final client in clients) {
            await client.dispose();
          }
        });
        Future<(AccordClient, AccordSession)> account(String role) async {
          final registration = AccordClient(baseUrl: url);
          final username = 'pong$role${DateTime.now().microsecondsSinceEpoch}';
          final result = await registration.auth.register({
            'username': username,
            'password': 'experience-test-only',
          });
          await registration.dispose();
          expect(
            result.ok,
            isTrue,
            reason: '${result.statusCode}: ${result.error}',
          );
          final data = result.data! as Map;
          final user = data['user'] as AccordUser;
          final token = data['token'] as String;
          final client = AccordClient(
            baseUrl: url,
            token: token,
            tokenType: 'Bearer',
          );
          clients.add(client);
          return (
            client,
            AccordSession(
              server: AccordServer.fromBaseUrl(url),
              token: token,
              tokenType: 'Bearer',
              userId: user.id,
              username: user.username,
            ),
          );
        }

        final (owner, ownerSession) = await account('owner');
        final (peer, _) = await account('peer');
        final created = await owner.spaces.create({
          'name': 'Pong UI fixture',
          'public': true,
        });
        expect(created.ok, isTrue, reason: '${created.error}');
        final space = (created.data! as AccordSpace).id;
        expect((await peer.spaces.join(space)).ok, isTrue);
        expect(
          (await owner.experiences.enable(space, 'pong', '1.0.0')).ok,
          isTrue,
        );
        Future<AccordExperienceSession> require(
          Future<RestResult> request,
        ) async {
          final response = await request;
          expect(
            response.ok,
            isTrue,
            reason: '${response.statusCode}: ${response.error}',
          );
          return response.data! as AccordExperienceSession;
        }

        var session = await require(owner.experiences.create(space, 'pong'));
        session = await require(
          peer.experiences.membership(
            space,
            session.id,
            'join',
            session.revision,
          ),
        );
        for (final client in [owner, peer]) {
          session = await require(
            client.experiences.membership(
              space,
              session.id,
              'ready',
              session.revision,
              ready: true,
            ),
          );
        }
        session = await require(
          owner.experiences.membership(
            space,
            session.id,
            'start',
            session.revision,
          ),
        );
        var remote = await ExperienceLiveSession.connect(
          peer,
          space,
          session.id,
        );
        addTearDown(() => remote.close());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              accordAuthProvider.overrideWith(() => _Auth(owner, ownerSession)),
              connectionsControllerProvider.overrideWith(
                () => _Connections(ownerSession),
              ),
            ],
            child: MaterialApp(
              home: ExperienceSessionView(
                serverKey: ownerSession.key,
                spaceId: space,
                initialSession: session,
              ),
            ),
          ),
        );
        Future<void> until(
          bool Function() condition, {
          String stage = 'update',
        }) async {
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while (DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            if (condition()) return;
          }
          final visibleText = tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
              .join(' | ');
          fail('Pong UI timed out during $stage. Visible text: $visibleText');
        }

        ExperienceCanvas canvas() =>
            tester.widget<ExperienceCanvas>(find.byType(ExperienceCanvas));
        await until(
          () => find.byType(ExperienceCanvas).evaluate().isNotEmpty,
          stage: 'loading the reviewed game',
        );
        expect(canvas().drawings, hasLength(3));
        await tester.scrollUntilVisible(find.byType(Slider), 200);
        await until(
          () => tester.widget<Slider>(find.byType(Slider)).onChanged != null,
          stage: 'enabling paddle input',
        );
        final localInput = remote.snapshots
            .firstWhere((s) => s.game['rects'][1] > 600)
            .timeout(const Duration(seconds: 5));
        final slider = tester.getRect(find.byType(Slider));
        await tester.tapAt(
          Offset(slider.left + slider.width * .85, slider.center.dy),
        );
        await localInput;
        // Measure the complete peer input -> authoritative snapshot -> guest render
        // -> Flutter widget frame path; report samples instead of timing API calls.
        final latencies = <int>[];
        for (final target in [100, 700, 200, 600, 300]) {
          final stopwatch = Stopwatch()..start();
          remote.input(target);
          await until(
            () => canvas().drawings[1].values[3] == target,
            stage: 'rendering peer paddle $target',
          );
          latencies.add(stopwatch.elapsedMilliseconds);
        }
        latencies.sort();
        final p95 = latencies.last;
        debugPrint(
          'Pong input-to-Flutter-frame milliseconds: $latencies; p95=$p95; budget=250',
        );
        expect(
          p95,
          lessThanOrEqualTo(250),
          reason: 'The local reference-game input budget is 250 ms',
        );
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        final paused = remote.snapshots
            .firstWhere((s) => s.game['paused'] == true)
            .timeout(const Duration(seconds: 10));
        unawaited(
          navigator.push<void>(
            MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('covered Pong')),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await paused;
        expect(
          find.byType(ExperienceCanvas, skipOffstage: false),
          findsNothing,
        );
        final resumed = remote.snapshots
            .firstWhere((s) => s.game['paused'] == false)
            .timeout(const Duration(seconds: 10));
        navigator.pop();
        await tester.pump(const Duration(milliseconds: 500));
        await resumed;
        await until(() => find.byType(ExperienceCanvas).evaluate().isNotEmpty);
        await remote.close();
        await until(
          () => find
              .text('Paused while the other player reconnects.')
              .evaluate()
              .isNotEmpty,
        );
        remote = await ExperienceLiveSession.connect(peer, space, session.id);
        await until(
          () => find
              .text('Paused while the other player reconnects.')
              .evaluate()
              .isEmpty,
        );
        final disabled = await owner.experiences.configure(
          space,
          'pong',
          enabled: false,
        );
        expect(
          disabled.ok,
          isTrue,
          reason: '${disabled.statusCode}: ${disabled.error}',
        );
        await until(() => find.byType(ExperienceCanvas).evaluate().isEmpty);
        expect(find.textContaining('disabled'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
      });
    },
    skip: url.isEmpty,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
