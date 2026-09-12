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
    // Fix "now" to a known Thursday so current- and previous-week assertions
    // are deterministic. 2026-06-11 is a Thursday.
    final now = DateTime(2026, 6, 11, 12, 0);

    test('today shows bare clock', () {
      final local = DateTime(2026, 6, 11, 18, 43);
      expect(messageTimeString(local, now: now), '18:43');
    });

    test('yesterday shows "Yesterday at HH:MM"', () {
      final local = DateTime(2026, 6, 10, 9, 5);
      expect(messageTimeString(local, now: now), 'Yesterday at 09:05');
    });

    test('earlier in the current calendar week shows weekday', () {
      final local = DateTime(2026, 6, 8, 14, 30); // Monday
      expect(messageTimeString(local, now: now), 'Monday at 14:30');
    });

    test('previous calendar week prefixes weekday with "Last"', () {
      final local = DateTime(2026, 6, 7, 8, 0); // Sunday
      expect(messageTimeString(local, now: now), 'Last Sunday at 08:00');
    });

    test('previous Tuesday is clearly distinguished from this week', () {
      final local = DateTime(2026, 6, 2, 2, 47);
      expect(messageTimeString(local, now: now), 'Last Tuesday at 02:47');
    });

    test('message before the previous calendar week uses calendar date', () {
      final local = DateTime(2026, 5, 31, 8, 0); // Sunday
      expect(messageTimeString(local, now: now), '31/05/2026 08:00');
    });

    test('older message shows DD/MM/YYYY HH:MM', () {
      final local = DateTime(2026, 1, 5, 7, 3);
      expect(messageTimeString(local, now: now), '05/01/2026 07:03');
    });

    test('future timestamp (negative daysAgo) shows bare clock', () {
      final local = DateTime(2026, 6, 12, 10, 0); // tomorrow
      expect(messageTimeString(local, now: now), '10:00');
    });

    test('weekday names cover the previous week', () {
      const expectedNames = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      // The previous calendar week runs from 1–7 June.
      for (var day = 1; day <= 7; day++) {
        final local = DateTime(2026, 6, day, 12, 0);
        final result = messageTimeString(local, now: now);
        expect(result, 'Last ${expectedNames[local.weekday - 1]} at 12:00');
      }
    });

    test('calendar-week labels work across a year boundary', () {
      final januaryNow = DateTime(2027, 1, 4, 12, 0); // Monday
      final local = DateTime(2026, 12, 29, 8, 0); // Tuesday
      expect(
        messageTimeString(local, now: januaryNow),
        'Last Tuesday at 08:00',
      );
    });

    test('yesterday is based on calendar dates across DST changes', () {
      // In Europe/London, these midnights are only 23 hours apart because the
      // clocks advance on 29 March 2026.
      final afterDstChange = DateTime(2026, 3, 30, 12, 0);
      final local = DateTime(2026, 3, 29, 8, 0);
      expect(
        messageTimeString(local, now: afterDstChange),
        'Yesterday at 08:00',
      );
    });
  });

  group('messageTimestampString', () {
    test('formats a known date with weekday, day, month, year and time', () {
      // 2026-06-05 is a Friday.
      final dt = DateTime(2026, 6, 5, 14, 30);
      expect(messageTimestampString(dt), 'Friday, 5 June 2026 at 14:30');
    });

    test('pads single-digit minutes', () {
      final dt = DateTime(2026, 3, 2, 9, 5); // Monday 2 March 2026
      expect(messageTimestampString(dt), 'Monday, 2 March 2026 at 09:05');
    });

    test('uses correct month names for all 12 months', () {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      for (var m = 1; m <= 12; m++) {
        final dt = DateTime(2026, m, 1, 0, 0);
        expect(messageTimestampString(dt), contains(months[m - 1]));
      }
    });

    test('uses correct weekday names for all 7 days', () {
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      // 2026-06-01 is a Monday; iterate through the full week.
      for (var d = 0; d < 7; d++) {
        final dt = DateTime(2026, 6, 1 + d, 12, 0);
        expect(messageTimestampString(dt), contains(weekdays[d]));
      }
    });
  });
}
