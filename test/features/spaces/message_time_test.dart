import 'package:bonfire/features/spaces/utils/message_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('messageClockString', () {
    test('pads single-digit hour and minute', () {
      final dt = DateTime(2026, 6, 13, 9, 5);
      expect(messageClockString(dt), '09:05');
    });

    test('handles midnight', () {
      final dt = DateTime(2026, 6, 13, 0, 0);
      expect(messageClockString(dt), '00:00');
    });

    test('handles end of day', () {
      final dt = DateTime(2026, 6, 13, 23, 59);
      expect(messageClockString(dt), '23:59');
    });
  });

  group('messageTimeString', () {
    // Fix "now" to a known Saturday so weekday assertions are deterministic.
    // 2026-06-13 is a Saturday.
    final now = DateTime(2026, 6, 13, 12, 0);

    test('today shows bare clock', () {
      final local = DateTime(2026, 6, 13, 18, 43);
      expect(messageTimeString(local, now: now), '18:43');
    });

    test('yesterday shows "Yesterday at HH:MM"', () {
      final local = DateTime(2026, 6, 12, 9, 5);
      expect(messageTimeString(local, now: now), 'Yesterday at 09:05');
    });

    test('2 days ago shows weekday', () {
      final local = DateTime(2026, 6, 11, 14, 30); // Thursday
      expect(messageTimeString(local, now: now), 'Thursday at 14:30');
    });

    test('6 days ago shows weekday (boundary — still within week)', () {
      final local = DateTime(2026, 6, 7, 8, 0); // Sunday
      expect(messageTimeString(local, now: now), 'Sunday at 08:00');
    });

    test('7 days ago falls through to calendar date', () {
      final local = DateTime(2026, 6, 6, 8, 0); // Saturday — same weekday as now
      expect(messageTimeString(local, now: now), '06/06/2026 08:00');
    });

    test('older message shows DD/MM/YYYY HH:MM', () {
      final local = DateTime(2026, 1, 5, 7, 3);
      expect(messageTimeString(local, now: now), '05/01/2026 07:03');
    });

    test('future timestamp (negative daysAgo) shows bare clock', () {
      final local = DateTime(2026, 6, 14, 10, 0); // tomorrow
      expect(messageTimeString(local, now: now), '10:00');
    });

    test('weekday names cover full week', () {
      const expectedNames = [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ];
      // now is Saturday 2026-06-13; 6 days back lands on Sunday 2026-06-07.
      // Step through each day offset 2-6 from a known Monday anchor.
      // Monday 2026-06-08 is 5 days before our Saturday.
      for (var offset = 2; offset <= 6; offset++) {
        final local = now.subtract(Duration(days: offset));
        final result = messageTimeString(local, now: now);
        final day = local.weekday; // 1 = Monday … 7 = Sunday
        expect(result, contains(expectedNames[day - 1]));
      }
    });
  });
}
