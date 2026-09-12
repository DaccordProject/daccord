import 'dart:async';
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
/// A `429 Too Many Requests` is retried after the server's `Retry-After`
/// pause, up to [maxRetries] attempts, **unless** the caller passes
/// `retryOnRateLimit: false`. User-initiated sends (message create, multipart
/// upload) opt out: with enforced slowmode and upload budgets a 429 is an
/// actionable cooldown of up to hours, not a transient blip, so it comes
/// straight back as a [RestResult] failure carrying the server's own
/// [AccordError] — `rate_limited`, its message, and [AccordError.retryAfter] —
/// rather than silently retransmitting the whole payload and reporting a
/// generic "rate limited after N retries". When retry is on and every attempt
/// is rate-limited, the last server error (with its `retryAfter`) is preserved
/// too. Accepted responses (2xx) are never retried.
///
/// The underlying [http.Client] is injectable for testing, as is the [sleep]
/// callback used between rate-limit retries.
///
/// Every attempt is bounded by [timeout] (multipart uploads use the longer
/// [uploadTimeout] instead). A request that runs out of time comes back as an
/// ordinary [RestResult] failure (`INTERNAL`, "… timed out after …"), never as
/// a thrown [TimeoutException], so existing call sites report it on the error
/// path they already have.
class AccordRest {
  static const int maxRetries = 3;

  /// The pause assumed for a 429 that carries no usable `Retry-After`.
  static const Duration defaultRetryAfter = Duration(seconds: 1);

  String token;
  String tokenType; // "Bot" or "Bearer"
  final String baseUrl;

  /// Invoked whenever an authenticated request comes back `401 Unauthorized`
  /// (an invalid, revoked, or expired token). Lets the owner react centrally —
  /// e.g. sign the session out — instead of every call site handling it. Not
  /// fired for the login/register routes on a throwaway unauthenticated client,
  /// which simply leave this null.
  void Function()? onUnauthorized;

  /// The deadline applied to each individual HTTP attempt.
  ///
  /// Deliberately **per attempt** rather than one budget spanning the retry
  /// loop: a 429 retry spends most of its wall clock asleep in the
  /// server-dictated `Retry-After` pause, and a shared budget would turn a
  /// healthy rate-limit wait into a bogus timeout. Bounding each attempt still
  /// bounds the whole call (at most [maxRetries] attempts plus their
  /// `Retry-After` sleeps), which is all the UI needs to stop spinning forever.
  ///
  /// Defaults to [AccordConfig.defaultRequestTimeout].
  final Duration timeout;

  /// The deadline applied to each individual multipart (file upload) attempt.
  ///
  /// Separate from [timeout] — see [AccordConfig.defaultUploadTimeout].
  /// Defaults to [AccordConfig.defaultUploadTimeout].
  final Duration uploadTimeout;

  final http.Client _client;
  final Future<void> Function(Duration) _sleep;

  AccordRest(
    String baseUrl, {
    this.token = '',
    this.tokenType = 'Bot',
    this.onUnauthorized,
    Duration? timeout,
    Duration? uploadTimeout,
    http.Client? client,
    Future<void> Function(Duration)? sleep,
  })  : baseUrl = validateHttpEndpoint(
          baseUrl,
          label: 'Accord REST URL',
        ).toString(),
        timeout = timeout ?? AccordConfig.defaultRequestTimeout,
        uploadTimeout = uploadTimeout ?? AccordConfig.defaultUploadTimeout,
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
  ///
  /// [retryOnRateLimit] controls whether a 429 is waited out and retried
  /// (the default) or returned immediately as a failure — pass `false` for
  /// non-idempotent user sends whose cooldown the UI must show instead.
  Future<RestResult> makeRequest(
    String method,
    String path, {
    Object? body,
    Map<String, dynamic> query = const {},
    bool retryOnRateLimit = true,
  }) async {
    final uri = _buildUri(path, query);
    final headers = _buildHeaders();
    final bodyText = body != null ? jsonEncode(body) : '';

    return _executeWithRetry(
      retryOnRateLimit: retryOnRateLimit,
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
    int? maxBytes,
  }) async {
    final uri = _buildUri(path, query);
    final headers = <String, String>{
      'User-Agent': AccordConfig.userAgent,
    };
    if (token.isNotEmpty) {
      headers['Authorization'] = '$tokenType $token';
    }

    return _executeWithRetry(
      send: () async {
        if (maxBytes == null) return _client.get(uri, headers: headers);
        final request = http.Request('GET', uri)
          ..headers.addAll(headers)
          ..followRedirects = false;
        final streamed = await _client.send(request);
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw StateError('Private evidence exceeds the download limit');
          }
          bytes.add(chunk);
        }
        return http.Response.bytes(bytes.takeBytes(), streamed.statusCode,
            headers: streamed.headers);
      },
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
  ///
  /// [retryOnRateLimit] as for [makeRequest]. Uploads should normally pass
  /// `false`: a 429 here means a slowmode or upload-budget cooldown, and a
  /// blind retry would retransmit every file only to be refused again.
  Future<RestResult> makeMultipartRequest(
    String method,
    String path,
    MultipartForm form, {
    Map<String, dynamic> query = const {},
    bool retryOnRateLimit = true,
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
      attemptTimeout: uploadTimeout,
      retryOnRateLimit: retryOnRateLimit,
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
    Duration? attemptTimeout,
    bool retryOnRateLimit = true,
  }) async {
    final effectiveTimeout = attemptTimeout ?? timeout;
    var attempt = 0;
    while (attempt < maxRetries) {
      final http.Response response;
      try {
        response = await send().timeout(effectiveTimeout);
      } on TimeoutException {
        return RestResult.failure(
          0,
          _internalError(
            '$exhaustedLabel timed out after ${_timeoutLabel(effectiveTimeout)}',
          ),
        );
      } catch (error) {
        return RestResult.failure(
          0,
          _internalError('Failed to start $failureLabel: $error'),
        );
      }

      if (response.statusCode == 429) {
        // The server's own error (code/message) plus how long it asked us to
        // wait — kept whether we retry or not, so the caller can show a real
        // cooldown instead of a generic "rate limited" and is never left
        // guessing when to try again.
        final error = _rateLimitError(response);
        attempt += 1;
        if (retryOnRateLimit && attempt < maxRetries) {
          await _sleep(error.retryAfter ?? defaultRetryAfter);
          continue;
        }
        return RestResult.failure(429, error);
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

    // Success envelope with "data" key. Sibling keys (`pending_attachments`,
    // `cursor`, …) are kept on [RestResult.extras] rather than dropped.
    if (map.containsKey('data')) {
      final extras = <String, dynamic>{
        for (final entry in map.entries)
          if (entry.key != 'data') entry.key: entry.value,
      };
      return RestResult.success(status, map['data'], extras: extras);
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

  /// Builds the [AccordError] for a 429, preserving the server's code and
  /// message when the body is the standard error envelope
  /// (`{"error":{"code":"rate_limited","message":…,"retry_after":N}}`) and
  /// synthesising a `rate_limited` error otherwise.
  ///
  /// `retryAfter` is always set: the body's `error.retry_after` wins, then a
  /// top-level `retry_after`, then the `Retry-After` header (seconds), then
  /// [defaultRetryAfter]. Values are parsed tolerantly and clamped by
  /// [AccordError.parseRetryAfter].
  AccordError _rateLimitError(http.Response response) {
    AccordError? error;
    Duration? bodyRetryAfter;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final envelope = decoded['error'];
        if (envelope is Map) {
          error = AccordError.fromJson(envelope.cast<String, dynamic>());
        }
        bodyRetryAfter = AccordError.parseRetryAfter(decoded['retry_after']);
      }
    } catch (_) {
      // Empty or non-JSON body: fall through to the header.
    }
    error ??= AccordError(
      code: AccordError.rateLimitedCode,
      message: 'Rate limited',
    );
    if (error.code.isEmpty) error.code = AccordError.rateLimitedCode;
    if (error.message.isEmpty) error.message = 'Rate limited';
    error.retryAfter ??= bodyRetryAfter ??
        AccordError.parseRetryAfter(response.headers['retry-after']) ??
        defaultRetryAfter;
    return error;
  }

  /// Renders [timeout] for the timeout message — whole seconds normally,
  /// milliseconds for the sub-second deadlines tests use.
  static String _timeoutLabel(Duration timeout) =>
      timeout.inMilliseconds % 1000 == 0
          ? '${timeout.inSeconds}s'
          : '${timeout.inMilliseconds}ms';

  AccordError _internalError(String msg) {
    return AccordError(code: 'INTERNAL', message: msg);
  }
}
