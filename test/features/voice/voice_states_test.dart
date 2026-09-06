import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AccordVoiceState vs(String userId, String? channelId) =>
    AccordVoiceState(userId: userId, channelId: channelId);

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  VoiceStatesController ctl(ProviderContainer c) =>
      c.read(voiceStatesControllerProvider('').notifier);
  Map<String, Map<String, AccordVoiceState>> stateOf(ProviderContainer c) =>
      c.read(voiceStatesControllerProvider(''));

  test('starts empty', () {
    final c = makeContainer();
    expect(stateOf(c), isEmpty);
  });

  test('upsert adds a user to a channel', () {
    final c = makeContainer();
    ctl(c).upsert(vs('u1', 'chan-a'));
    expect(voiceUserCount(stateOf(c), 'chan-a'), 1);
    expect(voiceStatesFor(stateOf(c), 'chan-a').single.userId, 'u1');
  });

  test('upsert moves a user between channels (no duplication)', () {
    final c = makeContainer();
    ctl(c)
      ..upsert(vs('u1', 'chan-a'))
      ..upsert(vs('u2', 'chan-a'))
      ..upsert(vs('u1', 'chan-b'));
    expect(voiceUserCount(stateOf(c), 'chan-a'), 1); // only u2 left
    expect(voiceUserCount(stateOf(c), 'chan-b'), 1);
    expect(voiceStatesFor(stateOf(c), 'chan-b').single.userId, 'u1');
  });

  test('upsert with null channel removes the user from voice entirely', () {
    final c = makeContainer();
    ctl(c)
      ..upsert(vs('u1', 'chan-a'))
      ..upsert(vs('u1', null));
    expect(stateOf(c).containsKey('chan-a'), isFalse); // empty bucket pruned
  });

  test(
    'updates and moves preserve previous snapshots and participant order',
    () {
      final c = makeContainer();
      ctl(c)
        ..seedChannel('chan-a', [vs('u1', 'chan-a'), vs('u2', 'chan-a')])
        ..seedChannel('chan-b', [vs('u3', 'chan-b')])
        ..seedChannel('chan-c', [vs('u4', 'chan-c')]);
      final before = stateOf(c);
      final muted = vs('u1', 'chan-a')..selfMute = true;

      ctl(c).upsert(muted);
      final updated = stateOf(c);
      expect(updated['chan-a']!.keys, ['u2', 'u1']);
      expect(updated['chan-a']!['u1']!.selfMute, isTrue);
      expect(before['chan-a']!.keys, ['u1', 'u2']);
      expect(before['chan-a']!['u1']!.selfMute, isFalse);
      expect(updated['chan-c'], same(before['chan-c']));

      ctl(c).upsert(vs('u1', 'chan-b'));
      expect(stateOf(c).keys, ['chan-a', 'chan-b', 'chan-c']);
      expect(stateOf(c)['chan-a']!.keys, ['u2']);
      expect(stateOf(c)['chan-b']!.keys, ['u3', 'u1']);
      expect(updated['chan-a']!['u1'], same(muted));
      expect(updated['chan-b']!.keys, ['u3']);
    },
  );

  for (final destination in ['chan-c', null, '']) {
    test('upsert clears stale memberships when channel is $destination', () {
      final c = makeContainer();
      ctl(c)
        ..seedChannel('chan-a', [vs('u1', 'chan-a')])
        ..seedChannel('chan-b', [vs('u1', 'chan-b'), vs('u2', 'chan-b')]);
      final before = stateOf(c);

      ctl(c).upsert(vs('u1', destination));

      expect(stateOf(c).containsKey('chan-a'), isFalse);
      expect(stateOf(c)['chan-b']!.keys, ['u2']);
      expect(before['chan-a']!.keys, ['u1']);
      expect(before['chan-b']!.keys, ['u1', 'u2']);
      if (destination == 'chan-c') {
        expect(stateOf(c)['chan-c']!.keys, ['u1']);
      } else {
        expect(stateOf(c).keys, ['chan-b']);
      }
    });
  }

  test('upsert ignores an empty user id', () {
    final c = makeContainer();
    ctl(c).upsert(vs('u1', 'chan-a'));
    final before = stateOf(c);
    ctl(c).upsert(vs('', 'chan-b'));
    expect(stateOf(c), same(before));
  });

  test('seedChannel replaces a channel, clears when empty', () {
    final c = makeContainer();
    ctl(c).seedChannel('chan-a', [vs('u1', 'chan-a'), vs('u2', 'chan-a')]);
    expect(voiceUserCount(stateOf(c), 'chan-a'), 2);
    ctl(c).seedChannel('chan-a', const []);
    expect(stateOf(c).containsKey('chan-a'), isFalse);
  });

  test('removeUser drops one user and prunes an emptied channel', () {
    final c = makeContainer();
    ctl(c)
      ..upsert(vs('u1', 'chan-a'))
      ..upsert(vs('u2', 'chan-a'))
      ..removeUser('chan-a', 'u1');
    expect(voiceUserCount(stateOf(c), 'chan-a'), 1);
    ctl(c).removeUser('chan-a', 'u2');
    expect(stateOf(c).containsKey('chan-a'), isFalse);
  });

  test('clear empties the whole cache', () {
    final c = makeContainer();
    ctl(c).upsert(vs('u1', 'chan-a'));
    ctl(c).clear();
    expect(stateOf(c), isEmpty);
  });

  test('voiceStatesFor / voiceUserCount default for an unknown channel', () {
    expect(voiceStatesFor(const {}, 'nope'), isEmpty);
    expect(voiceUserCount(const {}, 'nope'), 0);
  });
}
