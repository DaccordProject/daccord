import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/events/services/accord_event_handler.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exposes a real [Ref] to the test so the READY seeding helper (which takes
/// the same `Ref` the gateway handler holds) can be driven directly.
final _refProvider = Provider<Ref>((ref) => ref);

const _keyA = 'u1@https://a.example';
const _keyB = 'u2@https://b.example';

AccordPresence presence(String userId, String status, {String? custom}) =>
    AccordPresence(
      userId: userId,
      status: status,
      activities:
          custom == null ? [] : [AccordActivity(name: custom, type: 'custom')],
    );

Map<String, dynamic> ready(List<Map<String, dynamic>> presences) => {
      'presences': presences,
    };

Map<String, dynamic> readyEntry(String userId, String status) => {
      'user_id': userId,
      'status': status,
    };

void main() {
  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PresenceController ctl(ProviderContainer c, String serverKey) =>
      c.read(presenceControllerProvider(serverKey).notifier);
  Map<String, AccordPresence> stateOf(ProviderContainer c, String serverKey) =>
      c.read(presenceControllerProvider(serverKey));

  void setActive(ProviderContainer c, String? key) =>
      c.read(connectionsControllerProvider.notifier).setActive(key);

  group('PresenceController (per-connection)', () {
    test('starts empty', () {
      final c = makeContainer();
      expect(stateOf(c, _keyA), isEmpty);
    });

    test('upsert stores a presence for that server only', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('alice', 'online'));
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      // The same snowflake on another server is untouched — no collision.
      expect(accordPresenceStatus(stateOf(c, _keyB), 'alice'), 'offline');
    });

    test('upsert ignores an empty user id', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('', 'online'));
      expect(stateOf(c, _keyA), isEmpty);
    });

    test('seeding two connections does not clobber either', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('alice', 'online'), presence('bob', 'idle')]);
      // Second connection READYs afterwards — the regression from #191 was
      // this wiping the first connection's map.
      ctl(c, _keyB).seed([presence('carol', 'dnd')]);

      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'idle');
      expect(accordPresenceStatus(stateOf(c, _keyB), 'carol'), 'dnd');
      expect(accordPresenceStatus(stateOf(c, _keyB), 'alice'), 'offline');
    });

    test('seed replaces this server\'s map (a dropped user goes offline)', () {
      final c = makeContainer();
      ctl(c, _keyA)
        ..seed([presence('alice', 'online'), presence('bob', 'idle')])
        ..seed([presence('alice', 'idle')]);
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'idle');
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'offline');
    });

    test('merge keeps users absent from the payload', () {
      final c = makeContainer();
      ctl(c, _keyA)
        ..seed([presence('alice', 'online'), presence('bob', 'idle')])
        ..merge([presence('carol', 'dnd')]);
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'idle');
      expect(accordPresenceStatus(stateOf(c, _keyA), 'carol'), 'dnd');
    });

    test('clear empties only that server', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      ctl(c, _keyB).seed([presence('carol', 'dnd')]);
      ctl(c, _keyA).clear();
      expect(stateOf(c, _keyA), isEmpty);
      expect(accordPresenceStatus(stateOf(c, _keyB), 'carol'), 'dnd');
    });
  });

  group('activePresencesProvider', () {
    test('is empty when no connection is active', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      expect(c.read(activePresencesProvider), isEmpty);
    });

    test('reads the active connection', () {
      final c = makeContainer();
      setActive(c, _keyA);
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      expect(
        accordPresenceStatus(c.read(activePresencesProvider), 'alice'),
        'online',
      );
    });

    test('a background connection is seeded and stays correct on switch', () {
      final c = makeContainer();
      setActive(c, _keyA);
      ctl(c, _keyA).seed([presence('alice', 'online')]);

      // Server B READYs and pushes live updates while it is *not* active.
      ctl(c, _keyB)
        ..seed([presence('carol', 'idle')])
        ..upsert(presence('dave', 'dnd'));

      // Still on A: B's data must not leak into the visible panes.
      expect(
        accordPresenceStatus(c.read(activePresencesProvider), 'carol'),
        'offline',
      );

      // Switching to B surfaces what arrived in the background — no reconnect.
      setActive(c, _keyB);
      final onB = c.read(activePresencesProvider);
      expect(accordPresenceStatus(onB, 'carol'), 'idle');
      expect(accordPresenceStatus(onB, 'dave'), 'dnd');
    });

    test('presence survives a server switch and switch back', () {
      final c = makeContainer();
      setActive(c, _keyA);
      ctl(c, _keyA).seed([presence('alice', 'online', custom: 'Working')]);
      setActive(c, _keyB);
      ctl(c, _keyB).seed([presence('carol', 'dnd')]);
      setActive(c, _keyA);

      final onA = c.read(activePresencesProvider);
      expect(accordPresenceStatus(onA, 'alice'), 'online');
      expect(accordCustomStatus(onA, 'alice'), 'Working');
      expect(accordPresenceStatus(onA, 'carol'), 'offline');
    });

    test('a live presence.update on the active server is observed', () {
      final c = makeContainer();
      setActive(c, _keyA);
      c.listen(activePresencesProvider, (_, _) {}, fireImmediately: true);
      ctl(c, _keyA).upsert(presence('alice', 'online'));
      expect(
        accordPresenceStatus(c.read(activePresencesProvider), 'alice'),
        'online',
      );
    });
  });

  group('seedPresencesFromReady', () {
    test('parses READY presences into the connection keyed by serverKey', () {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      seedPresencesFromReady(
        ref,
        ready([readyEntry('alice', 'online'), readyEntry('bob', 'idle')]),
        serverKey: _keyA,
      );
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'idle');
      expect(stateOf(c, _keyB), isEmpty);
    });

    test('two connections READYing in sequence keep their own presences', () {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      seedPresencesFromReady(ref, ready([readyEntry('alice', 'online')]),
          serverKey: _keyA);
      seedPresencesFromReady(ref, ready([readyEntry('carol', 'dnd')]),
          serverKey: _keyB);
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      expect(accordPresenceStatus(stateOf(c, _keyB), 'carol'), 'dnd');
    });

    test('an empty presences array clears the server (everyone offline)', () {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      seedPresencesFromReady(ref, ready(const []), serverKey: _keyA);
      expect(stateOf(c, _keyA), isEmpty);
    });

    test('a missing presences field leaves the previous seed alone', () {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      seedPresencesFromReady(ref, const {}, serverKey: _keyA);
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
    });
  });

  group('status helpers', () {
    test('unknown user defaults to offline with no custom status', () {
      expect(accordPresenceStatus(const {}, 'nobody'), 'offline');
      expect(accordCustomStatus(const {}, 'nobody'), isNull);
    });

    test('custom status returns the first non-blank activity name', () {
      final map = {
        'alice': AccordPresence(
          userId: 'alice',
          status: 'online',
          activities: [
            AccordActivity(name: '  ', type: 'custom'),
            AccordActivity(name: ' Deploying ', type: 'custom'),
          ],
        ),
      };
      expect(accordCustomStatus(map, 'alice'), 'Deploying');
    });
  });
}
