/// Desktop (`dart:io`) implementation of the local MCP server.
///
/// A JSON-RPC 2.0 / MCP adapter over [McpTools], ported from the reference
/// client's `ClientMcp` (`../daccord/scripts/client/client_mcp.gd`). It
/// preserves that file's security model verbatim:
///
/// * binds to `127.0.0.1` (loopback) only — never reachable off-host;
/// * bearer-token auth with a constant-time comparison;
/// * a 60-request / 1000ms token-bucket rate limit;
/// * a 1MB max request body, POST-only, to `/mcp` or `/mcp/`;
/// * tool-group permission filtering against the live allowed-groups list;
/// * MCP `content` wrapping of every tool result;
/// * a 100-entry in-memory activity ring buffer (surfaced via [onActivity]).
///
/// The token is generated locally and is never sent to the Accord server.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bonfire/features/developer/services/mcp_tools.dart';

class McpServer {
  McpServer({
    required this.tools,
    required String Function() tokenGetter,
    required List<String> Function() allowedGroupsGetter,
    required void Function(McpActivity) onActivity,
    this.appVersion = '0.0.0',
  })  : _tokenGetter = tokenGetter,
        _allowedGroupsGetter = allowedGroupsGetter,
        _onActivity = onActivity;

  static const String _protocolVersion = '2025-03-26';
  static const String _loopbackAddr = '127.0.0.1';
  static const int _maxContentLength = 1048576;
  static const int _rateLimitBurst = 60;
  static const int _rateLimitWindowMs = 1000;

  final McpTools tools;
  final String appVersion;
  final String Function() _tokenGetter;
  final List<String> Function() _allowedGroupsGetter;
  final void Function(McpActivity) _onActivity;

  HttpServer? _server;
  final List<int> _requestTimestamps = [];

  bool get isListening => _server != null;

  Future<bool> start(int port) async {
    if (_server != null) return true;
    try {
      _server = await HttpServer.bind(_loopbackAddr, port);
    } on SocketException catch (e) {
      // ignore: avoid_print
      print('McpServer: failed to bind $_loopbackAddr:$port — ${e.message}');
      return false;
    }
    _server!.listen(_handleRequest, onError: (_) {});
    // ignore: avoid_print
    print('McpServer: listening on $_loopbackAddr:$port');
    return true;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _requestTimestamps.clear();
    if (server != null) await server.close(force: true);
  }

  // ── HTTP handling ─────────────────────────────────────────────────────────

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      await _route(request);
    } catch (_) {
      _send(request, 500, _jsonRpcError(-32603, 'Internal error', null));
    }
  }

  Future<void> _route(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method != 'POST') {
      _send(request, 405, _jsonRpcError(-32600, 'Method not allowed', null));
      return;
    }
    if (path != '/mcp' && path != '/mcp/') {
      _send(request, 404, _jsonRpcError(-32600, 'Not found', null));
      return;
    }

    final contentLength = request.contentLength;
    if (contentLength > _maxContentLength) {
      _send(request, 413, _jsonRpcError(-32600, 'Request body too large', null));
      return;
    }

    if (!_checkAuth(request.headers.value(HttpHeaders.authorizationHeader))) {
      _send(request, 401, _jsonRpcError(-32600, 'Unauthorized', null));
      return;
    }
    if (_isRateLimited()) {
      _send(request, 429, _jsonRpcError(-32600, 'Too many requests', null));
      return;
    }

    final bodyBytes = await _readBody(request);
    if (bodyBytes == null) {
      _send(request, 413, _jsonRpcError(-32600, 'Request body too large', null));
      return;
    }

    Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(bodyBytes));
    } catch (_) {
      _send(request, 400, _jsonRpcError(-32700, 'Parse error', null));
      return;
    }
    if (parsed is! Map) {
      _send(request, 400, _jsonRpcError(-32700, 'Parse error', null));
      return;
    }

    final result = await _dispatch(Map<String, dynamic>.from(parsed));
    _send(request, 200, result);
  }

  Future<List<int>?> _readBody(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > _maxContentLength) return null;
    }
    return bytes;
  }

  // ── JSON-RPC dispatch ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> _dispatch(Map<String, dynamic> request) async {
    final id = request['id'];
    final method = request['method'];
    if (method is! String || method.isEmpty) {
      return _jsonRpcError(-32600, 'Missing method', id);
    }
    switch (method) {
      case 'initialize':
        return _jsonRpcResult(id, {
          'protocolVersion': _protocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {'name': 'daccord', 'version': appVersion},
        });
      case 'notifications/initialized':
        return id != null ? _jsonRpcResult(id, <String, dynamic>{}) : {};
      case 'tools/list':
        return _handleToolsList(id);
      case 'tools/call':
        final params = request['params'];
        return _handleToolsCall(
            id, params is Map ? Map<String, dynamic>.from(params) : {});
      default:
        return _jsonRpcError(-32601, 'Method not found: $method', id);
    }
  }

  Map<String, dynamic> _handleToolsList(Object? id) {
    final allowed = _allowedGroupsGetter();
    final list = [
      for (final tool in tools.tools.values)
        if (allowed.contains(tool.group))
          {
            'name': tool.name,
            'description': tool.description,
            'inputSchema': tool.inputSchema,
          },
    ];
    return _jsonRpcResult(id, {'tools': list});
  }

  Future<Map<String, dynamic>> _handleToolsCall(
      Object? id, Map<String, dynamic> params) async {
    final name = params['name'];
    if (name is! String || name.isEmpty) {
      return _jsonRpcError(-32602, 'Missing tool name', id);
    }
    final args = params['arguments'];
    final arguments = args is Map ? Map<String, dynamic>.from(args) : {};

    final tool = tools.tools[name];
    if (tool == null) {
      _logActivity(name, false);
      return _jsonRpcError(-32601, 'Unknown tool: $name', id);
    }
    if (!_allowedGroupsGetter().contains(tool.group)) {
      _logActivity(name, false);
      return _jsonRpcError(
          -32600, "Tool group '${tool.group}' is not enabled", id);
    }

    final result =
        await tool.handler(Map<String, dynamic>.from(arguments));
    _logActivity(name, !result.containsKey('error'));
    return _jsonRpcResult(id, {
      'content': [
        {'type': 'text', 'text': jsonEncode(result)},
      ],
    });
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  bool _checkAuth(String? authHeader) {
    final token = _tokenGetter();
    if (token.isEmpty) return true;
    if (authHeader == null || !authHeader.startsWith('Bearer ')) return false;
    return _constantTimeCompare(authHeader.substring(7), token);
  }

  bool _constantTimeCompare(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    if (aBytes.length != bBytes.length) return false;
    var result = 0;
    for (var i = 0; i < aBytes.length; i++) {
      result |= aBytes[i] ^ bBytes[i];
    }
    return result == 0;
  }

  // ── Rate limiting ────────────────────────────────────────────────────────

  bool _isRateLimited() {
    final now = DateTime.now().millisecondsSinceEpoch;
    while (_requestTimestamps.isNotEmpty &&
        now - _requestTimestamps.first > _rateLimitWindowMs) {
      _requestTimestamps.removeAt(0);
    }
    if (_requestTimestamps.length >= _rateLimitBurst) return true;
    _requestTimestamps.add(now);
    return false;
  }

  // ── Activity log ─────────────────────────────────────────────────────────

  void _logActivity(String tool, bool ok) => _onActivity(McpActivity(tool, ok));

  // ── JSON-RPC + HTTP helpers ──────────────────────────────────────────────

  Map<String, dynamic> _jsonRpcResult(Object? id, Object? result) =>
      {'jsonrpc': '2.0', 'result': result, 'id': id};

  Map<String, dynamic> _jsonRpcError(int code, String message, Object? id) => {
        'jsonrpc': '2.0',
        'error': {'code': code, 'message': message},
        'id': id,
      };

  void _send(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.connectionHeader, 'close')
      ..write(jsonEncode(body));
    request.response.close();
  }
}
