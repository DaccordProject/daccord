import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/experiences/controllers/turns.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccordExperienceSession snapshot(
  String id,
  int revision, {
  String? turn = 'player',
  String state = 'running',
}) => AccordExperienceSession.fromJson({
  'id': id,
  'space_id': 'space',
  'game_id': 'chess',
  'version': '1.0.0',
  'digest': 'digest',
  'mode': 'turn_based',
  'state': state,
  'revision': revision,
  'host_user_id': 'player',
  'turn_user_id': turn,
  'participants': [],
  'game': {},
});
void main() {
  test(
    'turn alerts isolate servers, reject stale events and preserve dismissals',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final turns = container.read(experienceTurnsProvider.notifier);
      turns.update('a', 'player', snapshot('session', 1));
      turns.update('b', 'player', snapshot('session', 1));
      expect(container.read(experienceTurnsProvider), hasLength(2));
      turns.dismiss((serverKey: 'a', sessionId: 'session'));
      turns.update('a', 'player', snapshot('session', 1));
      expect(container.read(experienceTurnsProvider), hasLength(1));
      turns.update('a', 'player', snapshot('session', 2));
      turns.update('a', 'player', snapshot('session', 1, turn: 'other'));
      expect(container.read(experienceTurnsProvider), hasLength(2));
      turns.update('a', 'player', snapshot('session', 3, state: 'ended'));
      expect(container.read(experienceTurnsProvider), hasLength(1));
      turns.clearServer('b');
      expect(container.read(experienceTurnsProvider), isEmpty);
    },
  );
  test('turn history and visible alerts have fixed bounds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final turns = container.read(experienceTurnsProvider.notifier);
    for (var i = 0; i < 1000; i++) {
      turns.update('server', 'player', snapshot('$i', i));
    }
    expect(container.read(experienceTurnsProvider), hasLength(128));
    turns.clearServer('server');
    expect(container.read(experienceTurnsProvider), isEmpty);
  });
}
