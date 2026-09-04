import 'package:bonfire/features/channels/controllers/read_state.dart';
import 'package:bonfire/features/events/services/accord_ready_sync.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _serverKey = 'u-self@https://accord.example.test';
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('hydrateReadStateFromReady', () {
    test('seeds unread entries, recovering space_id from channels', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      hydrateReadStateFromReady(
        container.read(_refProvider),
        {
          'unread': [
            {'channel_id': 'c1', 'space_id': 's1', 'mention_count': 3},
            // No space_id on the entry itself; recovered from `channels`.
            {'channel_id': 'c2', 'mention_count': 0},
            // No id at all: dropped.
            {'mention_count': 1},
          ],
          'channels': [
            {'id': 'c2', 'space_id': 's2'},
          ],
        },
        serverKey: _serverKey,
      );

      final snapshot = container.read(readStateControllerProvider(_serverKey));
      expect(snapshot.entries.keys, unorderedEquals(['c1', 'c2']));
      expect(snapshot.mentionCount('c1'), 3);
      expect(snapshot.entries['c1']?.spaceId, 's1');
      expect(snapshot.entries['c2']?.spaceId, 's2');
    });

    test('a non-list unread payload leaves existing state untouched', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(readStateControllerProvider(_serverKey).notifier)
          .markUnread('c1', spaceId: 's1');

      hydrateReadStateFromReady(
        container.read(_refProvider),
        {'unread': 'not-a-list'},
        serverKey: _serverKey,
      );

      final snapshot = container.read(readStateControllerProvider(_serverKey));
      expect(snapshot.isUnread('c1'), isTrue);
    });
  });

  group('seedVoiceStatesFromReady', () {
    test('buckets voice states by channel_id', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      seedVoiceStatesFromReady(
        container.read(_refProvider),
        {
          'voice_states': [
            {'user_id': 'u1', 'channel_id': 'vc1'},
            {'user_id': 'u2', 'channel_id': 'vc1'},
            {'user_id': 'u3', 'channel_id': 'vc2'},
            // No channel_id: dropped rather than bucketed under null.
            {'user_id': 'u4'},
          ],
        },
        serverKey: _serverKey,
      );

      final states = container.read(voiceStatesControllerProvider(_serverKey));
      expect(states['vc1']?.keys, unorderedEquals(['u1', 'u2']));
      expect(states['vc2']?.keys, unorderedEquals(['u3']));
      expect(states.containsKey('vc3'), isFalse);
    });

    test('a non-list voice_states payload seeds nothing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      seedVoiceStatesFromReady(
        container.read(_refProvider),
        {'voice_states': null},
        serverKey: _serverKey,
      );

      expect(container.read(voiceStatesControllerProvider(_serverKey)), isEmpty);
    });
  });
}
