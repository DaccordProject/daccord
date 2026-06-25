const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday',
  'Friday', 'Saturday', 'Sunday',
];

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December',
];

/// Bare `HH:MM` string for a local [DateTime].
String messageClockString(DateTime local) {
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Date-aware label for a message timestamp shown in the message header.
///
/// | Age      | Result                  |
/// |----------|-------------------------|
/// | Today    | `18:43`                 |
/// | Yesterday| `Yesterday at 18:43`    |
/// | 2–6 days | `Monday at 18:43`       |
/// | Older    | `12/06/2026 18:43`      |
///
/// The 6-day ceiling keeps weekday names unambiguous (a 7-day-old message
/// would repeat today's weekday). [now] is injected for testability; callers
/// omit it and the current wall-clock time is used.
String messageTimeString(DateTime local, {DateTime? now}) {
  final clock = messageClockString(local);
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(thatDay).inDays;

  if (daysAgo <= 0) return clock;
  if (daysAgo == 1) return 'Yesterday at $clock';
  if (daysAgo <= 6) return '${_weekdays[local.weekday - 1]} at $clock';

  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo/${local.year} $clock';
}

/// Full, unabbreviated timestamp for tooltips, e.g.
/// `Monday, 5 June 2026 at 14:30`. `intl` isn't a dependency, so the weekday and
/// month names are spelled out by hand here rather than re-inlined per caller.
String messageTimestampString(DateTime local) {
  final weekday = _weekdays[local.weekday - 1];
  final month = _months[local.month - 1];
  return '$weekday, ${local.day} $month ${local.year} at '
      '${messageClockString(local)}';
}
