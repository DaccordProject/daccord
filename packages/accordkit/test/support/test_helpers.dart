import 'dart:async';
import 'dart:convert';

import 'package:accordkit/accordkit.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A captured outbound HTTP request, for assertions.
class CapturedRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
  final List<int> bodyBytes;

  CapturedRequest(
      this.method, this.url, this.headers, this.body, this.bodyBytes);

  Map<String, dynamic>? get jsonBody {
    if (body.isEmpty) return null;
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  List<dynamic>? get jsonArrayBody {
    if (body.isEmpty) return null;
    final decoded = jsonDecode(body);
    return decoded is List ? decoded : null;
  }
}

/// Builds an [AccordRest] backed by a [MockClient]. Every request is recorded
/// into [log]; the [responder] decides each response. Rate-limit sleeps are
/// instant.
AccordRest mockRest({
  required List<CapturedRequest> log,
  required FutureOr<http.Response> Function(CapturedRequest req) responder,
  String token = 'test-token',
  String tokenType = 'Bot',
  String baseUrl = 'https://example.test/api/v1',
  void Function()? onUnauthorized,
}) {
  final client = MockClient((request) async {
    final captured = CapturedRequest(
      request.method,
      request.url,
      request.headers,
      request.body,
      request.bodyBytes,
    );
    log.add(captured);
    return responder(captured);
  });
  return AccordRest(
    baseUrl,
    token: token,
    tokenType: tokenType,
    onUnauthorized: onUnauthorized,
    client: client,
    sleep: (_) async {},
  );
}

/// A JSON `{ "data": ... }` success envelope response.
http.Response jsonData(Object? data, {int status = 200}) {
  return http.Response(jsonEncode({'data': data}), status,
      headers: {'content-type': 'application/json'});
}

/// A raw JSON body response (no envelope).
http.Response jsonRaw(Object? body, {int status = 200}) {
  return http.Response(jsonEncode(body), status,
      headers: {'content-type': 'application/json'});
}

/// A JSON `{ "error": {...} }` failure envelope response.
http.Response jsonError(
  String code,
  String message, {
  int status = 400,
}) {
  return http.Response(
    jsonEncode({
      'error': {'code': code, 'message': message}
    }),
    status,
    headers: {'content-type': 'application/json'},
  );
}
