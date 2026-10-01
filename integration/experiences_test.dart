import 'dart:io';
import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/experiences/services/experience_package.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/harness.dart';

Future<void> main() async {
  if (Platform.environment['ACCORD_TEST_EXPERIENCES'] != '1') {
    test(
      'curated stack requires its isolated fixture',
      () {},
      skip: 'Run tools/experiences/run_fixture.py',
    );
    return;
  }
  final harness = await IntegrationHarness.resolve();
  test(
    'real directory, community server and client agree on signed multiplayer sessions',
    () async {
      expect(harness.skipReason, isNull);
      addTearDown(harness.dispose);
      final owner = await harness.newAccount('chesswhite', connect: false);
      final black = await harness.newAccount('chessblack', connect: false);
      final spectator = await harness.newAccount('spectator', connect: false);
      final created = await owner.client.spaces.create({
        'name': 'Curated Arcade',
        'public': true,
      });
      expect(created.ok, isTrue, reason: '${created.error}');
      final space = (created.data! as AccordSpace).id;
      for (final account in [black, spectator]) {
        expect((await account.client.spaces.join(space)).ok, isTrue);
      }
      final directory = await owner.client.experiences.directory(space);
      expect(directory.ok, isTrue, reason: '${directory.error}');
      expect(
        (directory.data! as List).cast<AccordExperienceManifest>().map(
          (m) => m.id,
        ),
        containsAll(['chess', 'pong']),
      );
      expect(
        (await spectator.client.experiences.enable(
          space,
          'chess',
          '1.0.0',
        )).statusCode,
        403,
      );
      for (final game in ['chess', 'pong']) {
        expect(
          (await owner.client.experiences.enable(space, game, '1.0.0')).ok,
          isTrue,
        );
      }
      final arcade = await owner.client.experiences.arcade(space);
      expect((arcade.data! as Map)['visible'], isTrue);
      Future<AccordExperienceSession> require(
        Future<RestResult> request,
      ) async {
        final response = await request;
        expect(response.ok, isTrue, reason: '${response.error}');
        return response.data! as AccordExperienceSession;
      }

      Future<AccordExperienceSession> start(String game) async {
        var session = await require(
          owner.client.experiences.create(space, game),
        );
        session = await require(
          black.client.experiences.membership(
            space,
            session.id,
            'join',
            session.revision,
          ),
        );
        for (final account in [owner, black]) {
          session = await require(
            account.client.experiences.membership(
              space,
              session.id,
              'ready',
              session.revision,
              ready: true,
            ),
          );
        }
        return require(
          owner.client.experiences.membership(
            space,
            session.id,
            'start',
            session.revision,
          ),
        );
      }

      var chess = await start('chess');
      final release = await owner.client.experiences.package(space, 'chess');
      expect(release.ok, isTrue);
      final module = await validateExperiencePackage(
        release.data! as Map,
        digest: chess.digest,
        gameId: chess.gameId,
        version: chess.version,
        platform: 'linux',
      );
      final action = module
          .invoke(
            'input',
            [0, 12, 28],
            readState: (k, i) => (chess.game['board'] as List)[i] as int,
            grantValid: () => true,
          )
          .actions
          .single;
      chess = await require(
        owner.client.experiences.action(
          space,
          chess.id,
          chess.revision,
          'move',
          a: action.a,
          b: action.b,
        ),
      );
      expect(chess.turnUserId, black.userId);
      expect(chess.game['board'][28], 1);
      expect(
        (await owner.client.experiences.action(
          space,
          chess.id,
          chess.revision,
          'move',
          a: 11,
          b: 27,
        )).statusCode,
        403,
      );
      expect(
        (await spectator.client.experiences.action(
          space,
          chess.id,
          chess.revision,
          'move',
          a: 52,
          b: 36,
        )).statusCode,
        403,
      );
      // No participant has a gateway: persisted turn state survives all going offline.
      final resumed = await require(
        black.client.experiences.session(space, chess.id),
      );
      expect(resumed.revision, chess.revision);
      expect(
        module
            .invoke(
              'render',
              [],
              readState: (k, i) => (resumed.game['board'] as List)[i] as int,
              grantValid: () => true,
            )
            .drawings[28]
            .values
            .last,
        1,
      );
      chess = await require(
        black.client.experiences.action(
          space,
          chess.id,
          chess.revision,
          'resign',
        ),
      );
      expect(chess.result!['winner_user_id'], owner.userId);
      final pong = await start('pong');
      final left = await ExperienceLiveSession.connect(
        owner.client,
        space,
        pong.id,
      );
      final right = await ExperienceLiveSession.connect(
        black.client,
        space,
        pong.id,
      );
      addTearDown(left.close);
      addTearDown(right.close);
      final snapshots = right.snapshots
          .firstWhere((s) => s.game['rects'][1] == 300 && s.game['tick'] > 0)
          .timeout(const Duration(seconds: 10));
      left.input(300);
      final live = await snapshots;
      expect(live.mode, 'real_time');
      expect(live.id, pong.id);
      expect(
        (await owner.client.experiences.configure(
          space,
          'pong',
          enabled: false,
        )).ok,
        isTrue,
      );
      final ended = await require(
        black.client.experiences.session(space, pong.id),
      );
      expect(ended.state, 'ended');
      expect(ended.result!['reason'], 'disabled');
      expect(
        (await owner.client.experiences.package(space, 'pong')).statusCode,
        403,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
