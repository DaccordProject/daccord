import 'accord_error.dart';

/// The outcome of a REST call: either parsed [data] on success or an [error]
/// on failure.
class RestResult {
  bool ok;
  int statusCode;

  /// A typed model, a list of models, raw bytes, a Map, or null.
  Object? data;
  AccordError? error;

  /// Top-level keys of a `{"data": …}` success envelope other than `data`
  /// itself — e.g. the `pending_attachments` list an AutoMod-enabled server
  /// adds to a 202 multipart response, or a paging `cursor`. Empty for plain
  /// (non-envelope) bodies and for failures. [data] is unaffected, so callers
  /// that only ever read it see no change.
  final Map<String, dynamic> extras;

  RestResult({
    this.ok = false,
    this.statusCode = 0,
    this.data,
    this.error,
    Map<String, dynamic>? extras,
  }) : extras = extras ?? const {};

  static RestResult success(
    int status,
    Object? data, {
    Map<String, dynamic>? extras,
  }) {
    return RestResult(ok: true, statusCode: status, data: data, extras: extras);
  }

  /// Whether the server answered `202 Accepted` — the request was recorded
  /// but part of it (an attachment awaiting AutoMod) is not yet published.
  bool get accepted => ok && statusCode == 202;

  /// Upload IDs from the envelope's `pending_attachments` list: attachments
  /// the server is still scanning before it publishes them. Empty when the
  /// server published everything immediately (or predates AutoMod).
  List<String> get pendingAttachments {
    final raw = extras['pending_attachments'];
    if (raw is! List) return const [];
    return [
      for (final id in raw)
        if (id != null && id.toString().isNotEmpty) id.toString(),
    ];
  }

  static RestResult failure(int status, AccordError? err) {
    return RestResult(ok: false, statusCode: status, error: err);
  }

  /// Deserializes a successful Map response using [fromJson], replacing [data]
  /// with the model. No-op for non-Map or failed results.
  RestResult deserialize(Object Function(Map<String, dynamic>) fromJson) {
    final d = data;
    if (ok && d is Map<String, dynamic>) {
      data = fromJson(d);
    }
    return this;
  }

  /// Deserializes a successful List response, mapping each Map element through
  /// [fromJson]. No-op for non-List or failed results.
  RestResult deserializeArray(Object Function(Map<String, dynamic>) fromJson) {
    final d = data;
    if (ok && d is List) {
      data = [
        for (final item in d)
          if (item is Map<String, dynamic>) fromJson(item) else item,
      ];
    }
    return this;
  }
}
