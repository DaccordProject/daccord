/// Parses a timestamp from AccordServer as an instant in UTC.
///
/// Database timestamps are UTC text without a zone suffix (for example,
/// `2026-09-28 16:15:00`). Dart otherwise interprets those as device-local
/// time. Explicit `Z` and numeric offsets are also accepted.
DateTime? parseServerTimestamp(String value) {
  final timestamp = value.trim();
  final parsed = DateTime.tryParse(timestamp);
  if (parsed == null) return null;
  if (parsed.isUtc) return parsed;
  return DateTime.tryParse('${timestamp}Z');
}
