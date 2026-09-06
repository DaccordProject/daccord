import 'accord_error.dart';

/// The outcome of a REST call: either parsed [data] on success or an [error]
/// on failure.
class RestResult {
  bool ok;
  int statusCode;

  /// A typed model, a list of models, raw bytes, a Map, or null.
  Object? data;
  AccordError? error;

  RestResult({
    this.ok = false,
    this.statusCode = 0,
    this.data,
    this.error,
  });

  static RestResult success(int status, Object? data) {
    return RestResult(ok: true, statusCode: status, data: data);
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
