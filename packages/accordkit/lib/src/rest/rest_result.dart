import 'accord_error.dart';

/// The outcome of a REST call: either parsed [data] on success or an [error]
/// on failure. [cursor] carries pagination state for cursor-based endpoints.
class RestResult {
  bool ok;
  int statusCode;

  /// A typed model, a list of models, raw bytes, a Map, or null.
  Object? data;
  AccordError? error;

  /// Pagination info, e.g. `{ "after": "id", "has_more": bool }`.
  Map<String, dynamic> cursor;

  RestResult({
    this.ok = false,
    this.statusCode = 0,
    this.data,
    this.error,
    Map<String, dynamic>? cursor,
  }) : cursor = cursor ?? {};

  /// Whether the endpoint reported another page is available.
  bool get hasMore => cursor['has_more'] == true;

  static RestResult success(
    int status,
    Object? data, [
    Map<String, dynamic> cursor = const {},
  ]) {
    return RestResult(
      ok: true,
      statusCode: status,
      data: data,
      cursor: Map<String, dynamic>.from(cursor),
    );
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
