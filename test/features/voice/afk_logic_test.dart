import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the voice AFK state machine (#112).
///
/// [AfkTracker] is clock-injected on purpose so idle timeouts can be stepped
/// instantly here rather than waited out; everything the monitor does with real
/// timers and input hooks is a thin wrapper over these transitions.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);
  const tenMinutes = Duration(minutes: 10);

  AfkTracker connectedTracker() => AfkTracker(now: t0);

  group('AfkTracker', () {
    test('starts active', () {
      expect(connectedTracker().isAfk, isFalse);
      expect(connectedTracker().lastActivityAt, t0);
    });

    test('goes AFK once the idle threshold is reached', () {
      final tracker = connectedTracker();

      // Just short of the timeout: still active.
      expect(
        tracker.tick(
          now: t0.add(const Duration(minutes: 9, seconds: 59)),
          connected: true,
          timeout: tenMinutes,
        ),
        isFalse,
      );
      expect(tracker.isAfk, isFalse);

      // Exactly at the timeout: AFK, and the change is reported.
      expect(
        tracker.tick(
          now: t0.add(tenMinutes),
          connected: true,
          timeout: tenMinutes,
        ),
        isTrue,
      );
      expect(tracker.isAfk, isTrue);
    });

    test('reports the flip only once while it stays AFK', () {
      final tracker = connectedTracker();
      tracker.tick(now: t0.add(tenMinutes), connected: true, timeout: tenMinutes);
      expect(tracker.isAfk, isTrue);

      expect(
        tracker.tick(
          now: t0.add(const Duration(minutes: 30)),
          connected: true,
          timeout: tenMinutes,
        ),
        isFalse,
        reason: 'no change → nothing to broadcast',
      );
      expect(tracker.isAfk, isTrue);
    });

    test('activity restores active and reports the change', () {
      final tracker = connectedTracker();
      tracker.tick(now: t0.add(tenMinutes), connected: true, timeout: tenMinutes);
      expect(tracker.isAfk, isTrue);

      final back = t0.add(const Duration(minutes: 11));
      expect(tracker.markActivity(back), isTrue);
      expect(tracker.isAfk, isFalse);
      expect(tracker.lastActivityAt, back);

      // A second activity while already active isn't a state change.
      expect(
        tracker.markActivity(back.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('activity restarts the countdown rather than shortening it', () {
      final tracker = connectedTracker();
      tracker.markActivity(t0.add(const Duration(minutes: 9)));

      // 10 minutes after t0, but only 1 minute since the last activity.
      tracker.tick(
        now: t0.add(tenMinutes),
        connected: true,
        timeout: tenMinutes,
      );
      expect(tracker.isAfk, isFalse);

      tracker.tick(
        now: t0.add(const Duration(minutes: 19)),
        connected: true,
        timeout: tenMinutes,
      );
      expect(tracker.isAfk, isTrue);
    });

    test('an out-of-order activity stamp never rewinds the idle clock', () {
      final tracker = connectedTracker();
      tracker.markActivity(t0.add(const Duration(minutes: 5)));
      tracker.markActivity(t0.add(const Duration(minutes: 1)));
      expect(tracker.lastActivityAt, t0.add(const Duration(minutes: 5)));
    });

    test('never goes AFK while disconnected, however long the idle', () {
      final tracker = connectedTracker();

      expect(
        tracker.tick(
          now: t0.add(const Duration(hours: 3)),
          connected: false,
          timeout: tenMinutes,
        ),
        isFalse,
      );
      expect(tracker.isAfk, isFalse);
    });

    test('a long idle before joining does not make the join instantly AFK', () {
      final tracker = connectedTracker();
      final joinAt = t0.add(const Duration(hours: 3));

      // Three idle hours pass while disconnected...
      tracker.tick(now: joinAt, connected: false, timeout: tenMinutes);
      // ...then we join. The countdown starts from the join, not from t0.
      tracker.tick(now: joinAt, connected: true, timeout: tenMinutes);
      expect(tracker.isAfk, isFalse);

      tracker.tick(
        now: joinAt.add(const Duration(minutes: 5)),
        connected: true,
        timeout: tenMinutes,
      );
      expect(tracker.isAfk, isFalse);

      tracker.tick(
        now: joinAt.add(tenMinutes),
        connected: true,
        timeout: tenMinutes,
      );
      expect(tracker.isAfk, isTrue);
    });

    test('disconnecting while AFK clears AFK and reports it', () {
      final tracker = connectedTracker();
      tracker.tick(now: t0.add(tenMinutes), connected: true, timeout: tenMinutes);
      expect(tracker.isAfk, isTrue);

      expect(
        tracker.tick(
          now: t0.add(const Duration(minutes: 11)),
          connected: false,
          timeout: tenMinutes,
        ),
        isTrue,
      );
      expect(tracker.isAfk, isFalse);
    });

    test('a null timeout (feature off) never goes AFK and clears it', () {
      final tracker = connectedTracker();
      tracker.tick(now: t0.add(tenMinutes), connected: true, timeout: tenMinutes);
      expect(tracker.isAfk, isTrue);

      expect(
        tracker.tick(
          now: t0.add(const Duration(hours: 1)),
          connected: true,
          timeout: null,
        ),
        isTrue,
      );
      expect(tracker.isAfk, isFalse);
    });

    test('the timeout is configurable — a 1-minute setting fires at 1 minute',
        () {
      final tracker = connectedTracker();
      const oneMinute = Duration(minutes: 1);

      tracker.tick(
        now: t0.add(const Duration(seconds: 59)),
        connected: true,
        timeout: oneMinute,
      );
      expect(tracker.isAfk, isFalse);

      tracker.tick(now: t0.add(oneMinute), connected: true, timeout: oneMinute);
      expect(tracker.isAfk, isTrue);
    });

    test('a longer configured timeout defers AFK accordingly', () {
      final tracker = connectedTracker();
      const thirty = Duration(minutes: 30);

      tracker.tick(now: t0.add(tenMinutes), connected: true, timeout: thirty);
      expect(tracker.isAfk, isFalse);

      tracker.tick(now: t0.add(thirty), connected: true, timeout: thirty);
      expect(tracker.isAfk, isTrue);
    });
  });

  group('effectiveAfkTimeout', () {
    test('0 (and anything below) means AFK detection is off', () {
      expect(effectiveAfkTimeout(0), isNull);
      expect(effectiveAfkTimeout(-5), isNull);
    });

    test('positive minutes map straight through', () {
      expect(effectiveAfkTimeout(1), const Duration(minutes: 1));
      expect(effectiveAfkTimeout(30), const Duration(minutes: 30));
    });
  });

  group('afkPollInterval', () {
    test('polls at a quarter of the timeout', () {
      expect(
        afkPollInterval(const Duration(minutes: 1)),
        const Duration(seconds: 15),
      );
    });

    test('clamps to 1–15s so short and long timeouts both stay sane', () {
      expect(
        afkPollInterval(const Duration(seconds: 2)),
        const Duration(seconds: 1),
      );
      expect(
        afkPollInterval(const Duration(minutes: 30)),
        const Duration(seconds: 15),
      );
    });
  });

  group('afkTimeoutLabel', () {
    test('0 reads as Off, 1 is singular', () {
      expect(afkTimeoutLabel(0), 'Off');
      expect(afkTimeoutLabel(1), '1 minute');
      expect(afkTimeoutLabel(10), '10 minutes');
    });

    test('the default is one of the offered options', () {
      expect(afkTimeoutOptionsMinutes, contains(defaultAfkTimeoutMinutes));
      expect(afkTimeoutOptionsMinutes.first, 0, reason: 'off is offered');
    });
  });
}
