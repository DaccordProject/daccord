import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/events/services/accord_ready_sync.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exposes a real [Ref] to the test so the READY seeding helper (which takes
/// the same `Ref` the gateway handler holds) can be driven directly.
final _refProvider = Provider<Ref>((ref) => ref);

const _keyA = 'u1@https://a.example';
const _keyB = 'u2@https://b.example';
const _domainA = 'a.example';

/// A grace window short enough to wait out in a test but long enough that the
/// "still held" assertions aren't racing it.
const _grace = Duration(milliseconds: 30);

/// Waits past [PresenceController.offlineGrace] so held transitions land.
Future<void> pastGrace() =>
    Future<void>.delayed(PresenceController.offlineGrace * 3);

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
  setUp(() => PresenceController.offlineGrace = _grace);
  tearDown(() =>
      PresenceController.offlineGrace = const Duration(seconds: 8));

  ProviderContainer makeContainer() {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    return c;
  }

  PresenceController ctl(ProviderContainer c, String serverKey) =>
      c.read(presenceControllerProvider(serverKey).notifier);
  PresenceMap stateOf(ProviderContainer c, String serverKey) =>
      c.read(presenceControllerProvider(serverKey));

  void setActive(ProviderContainer c, String? key) =>
      c.read(connectionsControllerProvider.notifier).setActive(key);

  group('PresenceController (per-connection)', () {
    test('starts empty', () {
      final c = makeContainer();
      expect(stateOf(c, _keyA).byUser, isEmpty);
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
      expect(stateOf(c, _keyA).byUser, isEmpty);
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

    test('seed replaces this server\'s map (a dropped user goes offline)',
        () async {
      final c = makeContainer();
      ctl(c, _keyA)
        ..seed([presence('alice', 'online'), presence('bob', 'idle')])
        ..seed([presence('alice', 'idle')]);
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'idle');
      // Bob is absent from the re-seed, but the roster isn't blanked on the
      // spot — the implied offline waits out the grace window like any other
      // (#210).
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'idle');
      await pastGrace();
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'offline');
    });

    test('a user re-seeded inside the grace window never goes offline',
        () async {
      final c = makeContainer();
      ctl(c, _keyA)
        ..seed([presence('alice', 'online'), presence('bob', 'idle')])
        // Our own reconnect: a first READY that hasn't caught up with bob yet…
        ..seed([presence('alice', 'online')])
        // …then a live update putting him back before the window elapses.
        ..upsert(presence('bob', 'idle'));
      await pastGrace();
      expect(accordPresenceStatus(stateOf(c, _keyA), 'bob'), 'idle');
    });

    test('clear empties only that server', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      ctl(c, _keyB).seed([presence('carol', 'dnd')]);
      ctl(c, _keyA).clear();
      expect(stateOf(c, _keyA).byUser, isEmpty);
      expect(accordPresenceStatus(stateOf(c, _keyB), 'carol'), 'dnd');
    });
  });

  group('offline smoothing (#210)', () {
    test('an offline update is held for the grace window', () async {
      final c = makeContainer();
      ctl(c, _keyA)
        ..upsert(presence('alice', 'online'))
        ..upsert(presence('alice', 'offline'));

      // A peer's socket blip must not re-bucket them into "Offline" instantly.
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      await pastGrace();
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'offline');
    });

    test('a reconnect inside the window renders as no change at all', () async {
      final c = makeContainer();
      final seen = <String>[];
      c.listen(
        presenceControllerProvider(_keyA),
        (_, next) => seen.add(accordPresenceStatus(next, 'alice')),
      );

      ctl(c, _keyA).upsert(presence('alice', 'online'));
      ctl(c, _keyA).upsert(presence('alice', 'offline'));
      ctl(c, _keyA).upsert(presence('alice', 'online'));
      await pastGrace();

      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
      expect(seen, everyElement('online'),
          reason: 'the offline flip should never have reached a listener');
    });

    test('coming online is never delayed', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('alice', 'online'));
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'online');
    });

    test('a repeated offline does not push the transition further out',
        () async {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('alice', 'online'));
      ctl(c, _keyA).upsert(presence('alice', 'offline'));
      await Future<void>.delayed(_grace ~/ 2);
      ctl(c, _keyA).upsert(presence('alice', 'offline'));
      await pastGrace();
      expect(accordPresenceStatus(stateOf(c, _keyA), 'alice'), 'offline');
    });

    test('an offline for someone already offline applies immediately', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('alice', 'offline', custom: 'Away'));
      expect(accordCustomStatus(stateOf(c, _keyA), 'alice'), 'Away');
    });

    test('disposing the connection cancels pending holds', () async {
      final c = makeContainer();
      ctl(c, _keyA)
        ..upsert(presence('alice', 'online'))
        ..upsert(presence('alice', 'offline'));
      c.invalidate(presenceControllerProvider(_keyA));
      await pastGrace();
      // No lingering timer wrote into a disposed notifier.
      expect(stateOf(c, _keyA).byUser, isEmpty);
    });
  });

  group('federated IDs (#209)', () {
    test('a bare broadcast matches a member qualified to our own domain', () {
      final c = makeContainer();
      // accordserver broadcasts presence with a bare user_id…
      ctl(c, _keyA).upsert(presence('123', 'online'), homeDomain: _domainA);
      // …while a member seen through a federated space carries `id@domain`.
      expect(accordPresenceStatus(stateOf(c, _keyA), '123@$_domainA'), 'online');
      expect(accordPresenceStatus(stateOf(c, _keyA), '123'), 'online');
    });

    test('the same snowflake on another home server does not collide', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('123', 'online'), homeDomain: _domainA);
      // Snowflakes are only unique per home server — a `localPart` fallback
      // would report this remote user as online off our own user's presence.
      expect(accordPresenceStatus(stateOf(c, _keyA), '123@b.example'),
          'offline');
    });

    test('a qualified broadcast is stored under the same key', () {
      final c = makeContainer();
      ctl(c, _keyA)
          .upsert(presence('123@b.example', 'dnd'), homeDomain: _domainA);
      expect(
          accordPresenceStatus(stateOf(c, _keyA), '123@b.example'), 'dnd');
      expect(accordPresenceStatus(stateOf(c, _keyA), '123'), 'offline');
    });

    test('entries written before the domain was known are re-keyed', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('123', 'idle'));
      ctl(c, _keyA).upsert(presence('456', 'online'), homeDomain: _domainA);
      expect(accordPresenceStatus(stateOf(c, _keyA), '123@$_domainA'), 'idle');
    });

    test('a write without a domain leaves qualified keys alone', () {
      final c = makeContainer();
      ctl(c, _keyA).upsert(presence('123', 'online'), homeDomain: _domainA);
      // The self status picker and the AFK monitor write without a domain in
      // hand; that must not un-qualify the map.
      ctl(c, _keyA).upsert(presence('456', 'idle'));
      final map = stateOf(c, _keyA);
      expect(map.homeDomain, _domainA);
      expect(accordPresenceStatus(map, '123@$_domainA'), 'online');
      expect(accordPresenceStatus(map, '456@$_domainA'), 'idle');
    });

    test('seed qualifies too', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('123', 'online')], homeDomain: _domainA);
      expect(accordPresenceStatus(stateOf(c, _keyA), '123@$_domainA'), 'online');
    });
  });

  group('activePresencesProvider', () {
    test('is empty when no connection is active', () {
      final c = makeContainer();
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      expect(c.read(activePresencesProvider).byUser, isEmpty);
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
      expect(stateOf(c, _keyB).byUser, isEmpty);
    });

    test('qualifies the seeded IDs with the connection home domain', () {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      seedPresencesFromReady(
        ref,
        ready([readyEntry('123', 'online')]),
        serverKey: _keyA,
        homeDomain: _domainA,
      );
      expect(accordPresenceStatus(stateOf(c, _keyA), '123@$_domainA'), 'online');
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

    test('an empty presences array clears the server (everyone offline)',
        () async {
      final c = makeContainer();
      final ref = c.read(_refProvider);
      ctl(c, _keyA).seed([presence('alice', 'online')]);
      seedPresencesFromReady(ref, ready(const []), serverKey: _keyA);
      await pastGrace();
      expect(stateOf(c, _keyA).byUser, isEmpty);
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
      expect(accordPresenceStatus(const PresenceMap(), 'nobody'), 'offline');
      expect(accordCustomStatus(const PresenceMap(), 'nobody'), isNull);
    });

    test('custom status returns the first non-blank activity name', () {
      final map = PresenceMap(byUser: {
        'alice': AccordPresence(
          userId: 'alice',
          status: 'online',
          activities: [
            AccordActivity(name: '  ', type: 'custom'),
            AccordActivity(name: ' Deploying ', type: 'custom'),
          ],
        ),
      });
      expect(accordCustomStatus(map, 'alice'), 'Deploying');
    });
  });
}
