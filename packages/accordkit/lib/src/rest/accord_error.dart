import '../utils/json_utils.dart';

/// An error returned by the Accord API (or generated client-side for transport
/// failures, where [code] is "INTERNAL").
class AccordError {
  /// The server's error code for a rate-limit rejection (HTTP 429): slowmode,
  /// the per-user upload budgets, or the general request limiter. The code
  /// does not say which bucket fired; [retryAfter] says how long to wait.
  static const String rateLimitedCode = 'rate_limited';

  /// The longest `retry_after` honoured, matching the server's maximum
  /// slowmode (`rate_limit`, 21600 s). Anything larger is clamped so a
  /// malformed or hostile header can't park a client for days.
  static const Duration maxRetryAfter = Duration(seconds: 21600);

  String code;
  String message;

  /// How long the server asked us to wait before retrying, when it told us
  /// (`error.retry_after` in the body, else the `Retry-After` header). Set on
  /// every 429 [AccordRest] hands back; null for every other error.
  Duration? retryAfter;

  AccordError({this.code = '', this.message = '', this.retryAfter});

  factory AccordError.fromJson(Map<String, dynamic> d) {
    return AccordError(
      code: asString(d['code']),
      message: asString(d['message']),
      retryAfter: parseRetryAfter(d['retry_after']),
    );
  }

  /// Whether this is the server's rate-limit rejection (see [rateLimitedCode]).
  bool get isRateLimited => code == rateLimitedCode;

  /// Parses a `retry_after` / `Retry-After` value in **seconds** — a number, or
  /// a string holding one — into a [Duration], tolerantly.
  ///
  /// Returns null for anything missing, unparseable, non-finite or negative;
  /// callers pick their own fallback. Sub-second values are kept to the
  /// millisecond; the result is clamped to [maxRetryAfter].
  static Duration? parseRetryAfter(Object? value) {
    final double? seconds = switch (value) {
      final num v => v.toDouble(),
      final String v => double.tryParse(v.trim()),
      _ => null,
    };
    if (seconds == null || seconds.isNaN || seconds.isInfinite) return null;
    if (seconds < 0) return null;
    final parsed = Duration(milliseconds: (seconds * 1000).round());
    return parsed > maxRetryAfter ? maxRetryAfter : parsed;
  }

  @override
  String toString() => retryAfter == null
      ? 'AccordError(code: $code, message: $message)'
      : 'AccordError(code: $code, message: $message, '
            'retryAfter: ${retryAfter!.inSeconds}s)';
}
