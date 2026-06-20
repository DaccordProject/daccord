import 'dart:math';

import 'qualified_id.dart';

/// Helpers for decoding and generating Accord snowflake IDs. Snowflakes embed
/// a millisecond timestamp (relative to the Accord epoch) in their high bits.
class AccordSnowflake {
  /// Accord epoch: 2024-01-01T00:00:00Z in milliseconds.
  static const int epochMs = 1704067200000;

  static final Random _random = Random();

  /// Decodes the embedded creation timestamp (ms since Unix epoch). Returns 0
  /// for an empty or non-numeric snowflake. Tolerates qualified federation IDs
  /// (`<snowflake>@<domain>`) by decoding the bare snowflake part.
  static int decodeTimestampMs(String snowflake) {
    if (snowflake.isEmpty) return 0;
    final id = int.tryParse(localPart(snowflake)) ?? 0;
    return (id >> 22) + epochMs;
  }

  /// Decodes the embedded creation timestamp in seconds (fractional).
  static double decodeTimestamp(String snowflake) {
    return decodeTimestampMs(snowflake) / 1000.0;
  }

  /// Decodes the snowflake to a UTC [DateTime].
  static DateTime decodeToDateTime(String snowflake) {
    return DateTime.fromMillisecondsSinceEpoch(
      decodeTimestampMs(snowflake),
      isUtc: true,
    );
  }

  /// Builds a snowflake whose timestamp component matches [timestampMs].
  /// The lower 22 bits are zero.
  static String fromTimestampMs(int timestampMs) {
    final id = (timestampMs - epochMs) << 22;
    return id.toString();
  }

  /// Generates a unique-enough nonce snowflake for the current time, with the
  /// low 22 bits randomised. Suitable for optimistic message nonces.
  static String generateNonce() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id =
        ((nowMs - epochMs) << 22) | (_random.nextInt(0x400000) & 0x3FFFFF);
    return id.toString();
  }
}
