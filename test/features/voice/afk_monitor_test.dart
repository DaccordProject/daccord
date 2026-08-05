import 'package:bonfire/features/voice/services/afk_monitor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests the timer/hook wrapper around the AFK state machine (#112): that the
/// poll timer actually flips us to AFK, that mic activity and pointer input
/// hold it off, and that nothing is armed while disconnected.
///
/// These run under `testWidgets` purely for its fake clock — `tester.pump(d)`
/// advances both the monitor's periodic timer and `binding.clock`, so a
/// 10-minute timeout is exercised without a 10-minute test.
void main() {
  const timeout = Duration(minutes: 10);

  /// Runs [body] with a monitor wired to the test binding's fake clock.
  void monitorTest(
    String description,
    Future<void> Function(
      WidgetTester tester,
      AfkMonitor monitor,
      List<bool> changes,
    ) body,
  ) {
    testWidgets(description, (tester) async {
      final changes = <bool>[];
      final monitor = AfkMonitor(clock: () => tester.binding.clock.now())
        ..onAfkChanged = changes.add;
      try {
        await body(tester, monitor, changes);
      } finally {
        // Must happen inside the test body: the binding asserts no timers are
        // still pending when it returns, and the monitor owns a periodic one.
        monitor.dispose();
      }
    });
  }

  monitorTest('goes AFK when the timeout elapses with no activity', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);
    expect(monitor.isAfk, isFalse);

    await tester.pump(const Duration(minutes: 9));
    expect(monitor.isAfk, isFalse, reason: 'not yet past the timeout');
    expect(changes, isEmpty);

    await tester.pump(const Duration(minutes: 2));
    expect(monitor.isAfk, isTrue);
    expect(changes, [true]);
  });

  monitorTest('explicit activity brings us back and restarts the countdown', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);
    await tester.pump(const Duration(minutes: 11));
    expect(monitor.isAfk, isTrue);

    monitor.markActivity();
    expect(monitor.isAfk, isFalse);
    expect(changes, [true, false]);

    await tester.pump(const Duration(minutes: 9));
    expect(monitor.isAfk, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(monitor.isAfk, isTrue);
    expect(changes, [true, false, true]);
  });

  monitorTest('mic activity alone keeps us active with no input at all', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.micActive = () => true;
    monitor.update(connected: true, timeout: timeout);

    await tester.pump(const Duration(hours: 1));
    expect(monitor.isAfk, isFalse);
    expect(changes, isEmpty);
  });

  monitorTest('pointer input counts as activity', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);

    // Nudge the mouse every few minutes; never idle long enough to go away.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(minutes: 5));
      GestureBinding.instance.pointerRouter.route(
        const PointerDownEvent(position: Offset(1, 1)),
      );
    }
    await tester.pump(const Duration(minutes: 5));
    expect(monitor.isAfk, isFalse);
    expect(changes, isEmpty);
  });

  monitorTest('never goes AFK while disconnected', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: false, timeout: timeout);
    await tester.pump(const Duration(hours: 3));
    expect(monitor.isAfk, isFalse);
    expect(changes, isEmpty);
  });

  monitorTest('disconnecting while AFK reports the return to active', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);
    await tester.pump(const Duration(minutes: 11));
    expect(changes, [true]);

    monitor.update(connected: false, timeout: timeout);
    expect(monitor.isAfk, isFalse);
    expect(changes, [true, false]);
  });

  monitorTest('a null timeout (AFK off) never arms the monitor', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: null);
    await tester.pump(const Duration(hours: 3));
    expect(monitor.isAfk, isFalse);
    expect(changes, isEmpty);
  });

  monitorTest('turning the timeout off mid-call clears an active AFK', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);
    await tester.pump(const Duration(minutes: 11));
    expect(monitor.isAfk, isTrue);

    monitor.update(connected: true, timeout: null);
    expect(monitor.isAfk, isFalse);
    expect(changes, [true, false]);
  });

  monitorTest('a shorter configured timeout fires sooner', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: const Duration(minutes: 1));
    await tester.pump(const Duration(seconds: 30));
    expect(monitor.isAfk, isFalse);
    await tester.pump(const Duration(seconds: 45));
    expect(monitor.isAfk, isTrue);
  });

  monitorTest('dispose stops the timer and unhooks the global input routes', (
    tester,
    monitor,
    changes,
  ) async {
    monitor.update(connected: true, timeout: timeout);
    monitor.dispose();

    await tester.pump(const Duration(hours: 1));
    expect(changes, isEmpty);

    // The global pointer route is gone: routing an event must not throw or
    // reach the disposed monitor.
    GestureBinding.instance.pointerRouter.route(
      const PointerDownEvent(position: Offset(1, 1)),
    );
    expect(changes, isEmpty);
  });
}
