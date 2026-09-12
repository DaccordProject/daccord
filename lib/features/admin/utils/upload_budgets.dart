// Validation for the admin panel's per-user upload budget settings
// (`upload_requests_per_minute` / `upload_bytes_per_minute`, see accordserver
// `docs/automod.md`). Pure functions so the ranges are testable without the
// widget.

/// Accepted range of `upload_requests_per_minute`.
const int kMinUploadRequestsPerMinute = 1;
const int kMaxUploadRequestsPerMinute = 600;

/// Accepted range of `upload_bytes_per_minute` (1 byte – 1 TiB).
const int kMinUploadBytesPerMinute = 1;
const int kMaxUploadBytesPerMinute = 1099511627776;

const int _bytesPerMb = 1024 * 1024;

/// Parses the "uploads per minute" field: a whole number in
/// [kMinUploadRequestsPerMinute]–[kMaxUploadRequestsPerMinute]. Null when
/// blank, non-numeric or out of range.
int? parseUploadRequestsPerMinute(String text) {
  final value = int.tryParse(text.trim());
  if (value == null) return null;
  if (value < kMinUploadRequestsPerMinute ||
      value > kMaxUploadRequestsPerMinute) {
    return null;
  }
  return value;
}

/// Parses the "upload MB per minute" field into bytes. Decimals are accepted
/// ("0.5" is 512 KiB) and the result must land in
/// [kMinUploadBytesPerMinute]–[kMaxUploadBytesPerMinute]. Null when blank,
/// non-numeric or out of range.
int? parseUploadMbPerMinute(String text) {
  final mb = double.tryParse(text.trim());
  if (mb == null || mb.isNaN || mb.isInfinite || mb <= 0) return null;
  // Guard the multiplication: anything past the cap is rejected below anyway,
  // and a huge double would round to a garbage int.
  if (mb > kMaxUploadBytesPerMinute / _bytesPerMb) return null;
  final bytes = (mb * _bytesPerMb).round();
  if (bytes < kMinUploadBytesPerMinute || bytes > kMaxUploadBytesPerMinute) {
    return null;
  }
  return bytes;
}

/// Whether the admin panel should validate and send the upload-budget fields
/// on save. False when the server doesn't report the keys at all, or when
/// both fields are blank — the server reported the keys but nothing is
/// configured yet (e.g. it sent them as `null`) — so an admin saving an
/// unrelated change isn't forced to pick budget values first.
bool shouldSendUploadBudgets({
  required bool hasUploadBudgets,
  required String requestsText,
  required String mbText,
}) =>
    hasUploadBudgets &&
    (requestsText.trim().isNotEmpty || mbText.trim().isNotEmpty);

/// Renders `upload_bytes_per_minute` for the MB field: whole numbers stay
/// whole ("50"), fractions keep up to six decimals ("0.5", "12.25",
/// "0.000001" for a single byte) so every server value round-trips through
/// [parseUploadMbPerMinute].
String formatUploadMbPerMinute(int bytes) {
  final mb = bytes / _bytesPerMb;
  if (mb == mb.roundToDouble()) return mb.round().toString();
  var text = mb.toStringAsFixed(6);
  while (text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}
