import 'dart:convert';
import 'dart:math';

import 'package:bonfire/shared/app_info.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Pure Dart error-reporting client for GlitchTip (Sentry-compatible).
///
/// Sends events via HTTP POST to the Sentry store API endpoint. Port of the
/// reference client's `glitchtip_client.gd`, which deliberately avoided the
/// native Sentry SDK — a plain HTTP client has no platform-specific failure
/// modes and works identically on web, mobile, and desktop.
class GlitchTipClient {
  GlitchTipClient({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static const int maxBreadcrumbs = 100;
  static const String clientName = 'daccord-flutter/1.0';

  final http.Client _http;
  final Random _random = Random.secure();

  String _dsnKey = '';
  String _storeUrl = '';
  bool _initialized = false;
  String _lastEventId = '';
  final Map<String, String> _tags = {};
  final List<Map<String, dynamic>> _breadcrumbs = [];

  bool get isInitialized => _initialized;

  /// The `event_id` of the most recently built event ('' before any capture).
  String get lastEventId => _lastEventId;

  /// The resolved Sentry store endpoint (exposed for tests).
  String get storeUrl => _storeUrl;

  /// Parses [dsn] and prepares default tags. Returns false (and stays
  /// uninitialized) when the DSN is blank or malformed.
  bool init(String dsn) {
    if (dsn.isEmpty) return false;
    if (!_parseDsn(dsn)) return false;
    _setDefaultTags();
    _initialized = true;
    return true;
  }

  /// Records a breadcrumb in the in-memory ring buffer (attached to every
  /// subsequent event). Oldest crumbs are dropped past [maxBreadcrumbs].
  void addBreadcrumb(
    String message,
    String category, {
    String type = 'default',
  }) {
    _breadcrumbs.add({
      'type': type,
      'category': category,
      'message': message,
      'timestamp': _isoTimestamp(),
    });
    if (_breadcrumbs.length > maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
  }

  void setTag(String key, String value) => _tags[key] = value;

  void removeTag(String key) => _tags.remove(key);

  void close() => _http.close();

  /// Sends a message-only event at [level] ('info' by default).
  Future<void> captureMessage(String message, {String level = 'info'}) {
    if (!_initialized) return Future.value();
    final event = _buildEvent(level);
    event['message'] = {'formatted': message};
    return _sendEvent(event);
  }

  /// Sends an error event, attaching parsed stack frames when [stack] is given.
  Future<void> captureError(String message, {String stack = ''}) {
    if (!_initialized) return Future.value();
    final event = _buildEvent('error');
    event['message'] = {'formatted': message};
    if (stack.isNotEmpty) {
      event['exception'] = {
        'values': [
          {
            'type': 'DartError',
            'value': message,
            'stacktrace': {'frames': parseStackFrames(stack)},
          },
        ],
      };
    }
    return _sendEvent(event);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  /// DSN format: `https://<key>@<host>[/<path>]/<project_id>`, e.g.
  /// `https://abc123@crash.daccord.gg/1`. The store endpoint becomes
  /// `<scheme>://<host>[/<path>]/api/<project_id>/store/`.
  bool _parseDsn(String dsn) {
    final uri = Uri.tryParse(dsn.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return false;
    }
    if (uri.userInfo.isEmpty || uri.host.isEmpty) return false;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;
    final projectId = segments.last;
    final prefix = segments.length > 1
        ? '/${segments.sublist(0, segments.length - 1).join('/')}'
        : '';
    final host = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    _dsnKey = uri.userInfo;
    _storeUrl = '${uri.scheme}://$host$prefix/api/$projectId/store/';
    return true;
  }

  void _setDefaultTags() {
    _tags['app_version'] = kAppVersion;
    _tags['os'] = kIsWeb ? 'web' : defaultTargetPlatform.name;
    _tags['build_mode'] = kReleaseMode
        ? 'release'
        : (kProfileMode ? 'profile' : 'debug');
  }

  Map<String, dynamic> _buildEvent(String level) {
    final eventId = _generateEventId();
    _lastEventId = eventId;
    return {
      'event_id': eventId,
      'timestamp': _isoTimestamp(),
      'platform': 'other',
      'level': level,
      'release': 'daccord@$kAppVersion',
      'environment': kReleaseMode ? 'production' : 'development',
      'sdk': {'name': clientName, 'version': '1.0.0'},
      'tags': Map<String, String>.of(_tags),
      'breadcrumbs': {'values': List<Map<String, dynamic>>.of(_breadcrumbs)},
    };
  }

  Future<void> _sendEvent(Map<String, dynamic> event) async {
    try {
      await _http.post(
        Uri.parse(_storeUrl),
        headers: {
          'Content-Type': 'application/json',
          'X-Sentry-Auth':
              'Sentry sentry_version=7, '
              'sentry_client=$clientName, '
              'sentry_key=$_dsnKey',
        },
        body: jsonEncode(event),
      );
    } catch (_) {
      // Error reporting must never throw back into the app.
    }
  }

  /// UUID v4 as 32 hex chars (no dashes), as the Sentry event API expects.
  String _generateEventId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _isoTimestamp() {
    final now = DateTime.now().toUtc();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${now.year.toString().padLeft(4, '0')}-${pad(now.month)}-'
        '${pad(now.day)}T${pad(now.hour)}:${pad(now.minute)}:'
        '${pad(now.second)}Z';
  }

  static final _frameRe = RegExp(r'^#\d+\s+(.+?)\s+\((.+?):(\d+)(?::\d+)?\)$');

  /// Parses a Dart [StackTrace.toString] into Sentry stack frames (oldest
  /// first). Lines that don't look like frames (e.g. `<asynchronous
  /// suspension>`) are kept as filename-only frames, like the reference
  /// client's lenient GDScript parser.
  static List<Map<String, dynamic>> parseStackFrames(String stackText) {
    final frames = <Map<String, dynamic>>[];
    for (final line in stackText.split('\n')) {
      final stripped = line.trim();
      if (stripped.isEmpty) continue;
      final match = _frameRe.firstMatch(stripped);
      if (match != null) {
        frames.add({
          'function': match.group(1),
          'filename': match.group(2),
          'lineno': int.tryParse(match.group(3)!) ?? 0,
        });
      } else {
        frames.add({'filename': stripped});
      }
    }
    return frames.reversed.toList();
  }
}
