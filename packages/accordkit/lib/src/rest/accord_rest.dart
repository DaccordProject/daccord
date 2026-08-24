import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/accord_config.dart';
import '../utils/transport_security.dart';
import 'accord_error.dart';
import 'multipart_form.dart';
import 'rest_result.dart';

/// Central HTTP client for AccordKit. Handles authentication, request
/// construction, response-envelope parsing, and automatic rate-limit retry.
///
/// The underlying [http.Client] is injectable for testing, as is the [sleep]
/// callback used between rate-limit retries.
class AccordRest {
  static const int maxRetries = 3;

  String token;
  String tokenType; // "Bot" or "Bearer"
  final String baseUrl;

  /// Invoked whenever an authenticated request comes back `401 Unauthorized`
  /// (an invalid, revoked, or expired token). Lets the owner react centrally —
  /// e.g. sign the session out — instead of every call site handling it. Not
  /// fired for the login/register routes on a throwaway unauthenticated client,
  /// which simply leave this null.
  void Function()? onUnauthorized;

  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  AccordRest(
    String baseUrl, {
    this.token = '',
    this.tokenType = 'Bot',
    this.onUnauthorized,
    http.Client? client,
    Future<void> Function(Duration)? sleep,
  })  : baseUrl = validateHttpEndpoint(
          baseUrl,
          label: 'Accord REST URL',
        ).toString(),
        _client = client ?? http.Client(),
        _sleep = sleep ?? _defaultSleep;

  static Future<void> _defaultSleep(Duration d) => Future.delayed(d);

  /// Releases the underlying HTTP client.
  void close() => _client.close();

  /// Performs a JSON HTTP request and returns a parsed [RestResult].
  ///
  /// [method] is one of GET/POST/PUT/PATCH/DELETE. A non-null [body]
  /// (Map or List) is JSON-encoded for non-GET requests. [query] is
  /// URL-encoded and appended.
  Future<RestResult> makeRequest(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic> query = const {},
  }) async {
    final uri = _buildUri(path, query);
    final headers = _buildHeaders();
    final bodyText = body != null ? jsonEncode(body) : '';

    return _executeWithRetry(
      send: () => _send(method, uri, headers, bodyText),
      interpret: (response) => _parseResponse(
        response.statusCode,
        utf8.decode(response.bodyBytes),
      ),
    );
  }

  /// Performs a GET and returns the raw response bytes as [RestResult.data]
  /// instead of parsing JSON.
  Future<RestResult> makeRawRequest(
    String path, {
    Map<String, dynamic> query = const {},
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'User-Agent': AccordConfig.userAgent,
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = '$tokenType $token';
    }

    return _executeWithRetry(
      send: () => _client.get(uri, headers: headers),
      interpret: (response) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return RestResult.success(response.statusCode, response.bodyBytes);
        }
        return RestResult.failure(
          response.statusCode,
          _internalError('HTTP ${response.statusCode}'),
        );
      },
    );
  }

  /// Performs a `multipart/form-data` request (file uploads).
  Future<RestResult> makeMultipartRequest(
    String method,
    String path,
    MultipartForm form, {
    Map<String, dynamic> query = const {},
  }) async {
    final uri = _buildUri(path, query);
    final bodyBytes = form.build();
    final headers = <String, String>{
      'Content-Type': form.contentType(),
      'User-Agent': AccordConfig.userAgent,
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = '$tokenType $token';
    }

    return _executeWithRetry(
      failureLabel: 'multipart request',
      exhaustedLabel: 'Multipart request',
      send: () async {
        final request = http.Request(method, uri)
          ..headers.addAll(headers)
          ..bodyBytes = bodyBytes;
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      },
      interpret: (response) => _parseResponse(
        response.statusCode,
        utf8.decode(response.bodyBytes),
      ),
    );
  }

  Future<RestResult> _executeWithRetry({
    required Future<http.Response> Function() send,
    required RestResult Function(http.Response) interpret,
    String failureLabel = 'request',
    String exhaustedLabel = 'Request',
  }) async {
    var attempt = 0;
    while (attempt < maxRetries) {
      final http.Response response;
      try {
        response = await send();
      } catch (error) {
        return RestResult.failure(
          0,
          _internalError('Failed to start $failureLabel: $error'),
        );
      }

      if (response.statusCode == 429) {
        attempt += 1;
        if (attempt < maxRetries) {
          final retryAfter = _getRetryAfter(response);
          await _sleep(Duration(milliseconds: (retryAfter * 1000).round()));
          continue;
        }
        return RestResult.failure(
          429,
          _internalError('Rate limited after $maxRetries retries'),
        );
      }

      if (response.statusCode == 401) onUnauthorized?.call();
      return interpret(response);
    }

    return RestResult.failure(
      0,
      _internalError('$exhaustedLabel exhausted all retries'),
    );
  }

  Future<http.Response> _send(
    String method,
    Uri uri,
    Map<String, String> headers,
    String bodyText,
  ) {
    final hasBody = bodyText.isNotEmpty;
    switch (method.toUpperCase()) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri,
            headers: headers, body: hasBody ? bodyText : null);
      case 'PUT':
        return _client.put(uri,
            headers: headers, body: hasBody ? bodyText : null);
      case 'PATCH':
        return _client.patch(uri,
            headers: headers, body: hasBody ? bodyText : null);
      case 'DELETE':
        return _client.delete(uri,
            headers: headers, body: hasBody ? bodyText : null);
      default:
        return _client.get(uri, headers: headers);
    }
  }

  Uri _buildUri(String path, Map<String, dynamic> query) {
    final uri = Uri.parse(baseUrl + path);
    final encoded = _encodeQuery(query);
    if (encoded.isEmpty) return uri;
    final existing = uri.query;
    final combined = existing.isEmpty ? encoded : '$existing&$encoded';
    return uri.replace(query: combined);
  }

  Map<String, String> _buildHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': AccordConfig.userAgent,
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = '$tokenType $token';
    }
    return headers;
  }

  /// URL-encodes [params], skipping null values.
  String _encodeQuery(Map<String, dynamic> params) {
    if (params.isEmpty) return '';
    final parts = <String>[];
    params.forEach((key, value) {
      if (value == null) return;
      parts.add(
        '${Uri.encodeQueryComponent(key.toString())}='
        '${Uri.encodeQueryComponent(value.toString())}',
      );
    });
    return parts.join('&');
  }

  /// Parses a JSON response envelope into a [RestResult].
  RestResult _parseResponse(int status, String body) {
    final isSuccess = status >= 200 && status < 300;

    if (body.trim().isEmpty) {
      if (isSuccess) return RestResult.success(status, null);
      return RestResult.failure(
        status,
        _internalError('Empty response with status $status'),
      );
    }

    Object? parsed;
    try {
      parsed = jsonDecode(body);
    } catch (_) {
      if (isSuccess) return RestResult.success(status, null);
      return RestResult.failure(
        status,
        _internalError('Failed to parse JSON response'),
      );
    }

    return _interpretParsed(status, parsed, isSuccess);
  }

  RestResult _interpretParsed(int status, Object? parsed, bool isSuccess) {
    if (parsed is! Map) {
      if (isSuccess) return RestResult.success(status, parsed);
      return RestResult.failure(
        status,
        _internalError('Unexpected response format'),
      );
    }

    final map = parsed.cast<String, dynamic>();

    // Error envelope.
    if (map.containsKey('error')) {
      final errorData = map['error'];
      final AccordError accordError;
      if (errorData is Map) {
        accordError = AccordError.fromJson(errorData.cast<String, dynamic>());
      } else {
        accordError = AccordError(message: errorData.toString());
      }
      return RestResult.failure(status, accordError);
    }

    // Success envelope with "data" key.
    if (map.containsKey('data')) {
      var cursor = <String, dynamic>{};
      final rawCursor = map['cursor'];
      final rawPagination = map['pagination'];
      if (rawCursor is Map) {
        cursor = rawCursor.cast<String, dynamic>();
      } else if (rawPagination is Map) {
        cursor = rawPagination.cast<String, dynamic>();
      }
      // Normalise cursor to always carry has_more.
      if (cursor.isNotEmpty && !cursor.containsKey('has_more')) {
        cursor['has_more'] = (cursor['after'] ?? '') != '';
      }
      return RestResult.success(status, map['data'], cursor);
    }

    // Plain dictionary response (no envelope).
    if (isSuccess) return RestResult.success(status, map);

    return RestResult.failure(
      status,
      AccordError(
        code: (map['code'] ?? '').toString(),
        message: (map['message'] ?? 'Unknown error').toString(),
      ),
    );
  }

  /// Extracts a Retry-After value (seconds) from headers or body, defaulting
  /// to 1.0 second.
  double _getRetryAfter(http.Response response) {
    final header = response.headers['retry-after'];
    if (header != null) {
      final value = double.tryParse(header.trim());
      if (value != null) return value;
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['retry_after'] != null) {
        final v = decoded['retry_after'];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 1.0;
      }
    } catch (_) {
      // ignore
    }
    return 1.0;
  }

  AccordError _internalError(String msg) {
    return AccordError(code: 'INTERNAL', message: msg);
  }
}

/// Exposed for tests: convert raw bytes to a UTF-8 string.
String decodeBytes(Uint8List bytes) => utf8.decode(bytes);
