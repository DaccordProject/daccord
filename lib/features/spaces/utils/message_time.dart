const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
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
/// | This week| `Monday at 18:43`       |
/// | Last week| `Last Monday at 18:43`  |
/// | Older    | `12/06/2026 18:43`      |
///
/// Weekday-only labels are limited to the current Monday–Sunday calendar week.
/// Prefixing weekdays from the previous calendar week with `Last` prevents a
/// recent message across a week boundary from looking like it belongs to this
/// week. [now] is injected for testability; callers omit it and the current
/// wall-clock time is used.
String messageTimeString(DateTime local, {DateTime? now}) {
  final clock = messageClockString(local);
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  final thatDay = DateTime(local.year, local.month, local.day);
  // Compare calendar dates in UTC so a 23- or 25-hour daylight-saving day is
  // still exactly one day apart for display purposes.
  final daysAgo = DateTime.utc(
    today.year,
    today.month,
    today.day,
  ).difference(DateTime.utc(thatDay.year, thatDay.month, thatDay.day)).inDays;

  if (daysAgo <= 0) return clock;
  if (daysAgo == 1) return 'Yesterday at $clock';

  // DateTime's overflowing day constructor performs calendar arithmetic;
  // subtracting a Duration here would have the same DST problem as above.
  final startOfThisWeek = DateTime(
    today.year,
    today.month,
    today.day - (today.weekday - 1),
  );
  if (!thatDay.isBefore(startOfThisWeek)) {
    return '${_weekdays[local.weekday - 1]} at $clock';
  }

  final startOfLastWeek = DateTime(
    startOfThisWeek.year,
    startOfThisWeek.month,
    startOfThisWeek.day - 7,
  );
  if (!thatDay.isBefore(startOfLastWeek)) {
    return 'Last ${_weekdays[local.weekday - 1]} at $clock';
  }

  final dd = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$dd/$mo/${local.year} $clock';
}

/// [messageTimeString] for a raw ISO-8601 [iso] timestamp (the form carried on
/// `AccordMessage.timestamp`), converted to local time. Empty when [iso]
/// doesn't parse.
String messageTimeFromIso(String iso, {DateTime? now}) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return messageTimeString(dt.toLocal(), now: now);
}

/// [messageClockString] for a raw ISO-8601 [iso] timestamp, converted to local
/// time. Empty when [iso] doesn't parse.
String messageClockFromIso(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return messageClockString(dt.toLocal());
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

/// [messageTimestampString] for a raw ISO-8601 [iso] timestamp, converted to
/// local time. Empty when [iso] doesn't parse.
String messageTimestampFromIso(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  return messageTimestampString(dt.toLocal());
}
