import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/server/models/accord_server.dart';

/// A parsed "Add a Server" URL or `daccord://` deep link.
///
/// Ports the reference client's `parse_server_url` (Enter-URL field) and
/// `UriHandler.parse_uri` (deep links) so the Flutter client accepts the same
/// share/connect strings.
class ParsedServerUrl {
  /// The resolved server (base/gateway/CDN URLs). Null only for `navigate`
  /// links, which target an already-connected server by space id.
  final AccordServer? server;

  /// One of `connect`, `invite`, or `navigate` for deep links; `connect` for a
  /// plain Enter-URL string.
  final String route;

  /// An optional auth token carried in `?token=` (lets a link pre-authenticate).
  final String? token;

  /// An optional invite code carried in `?invite=` or an `invite/` deep link.
  final String? invite;

  /// A space slug/name from the `#space-name` fragment or `connect/<slug>`.
  final String? spaceName;

  /// A channel name carried by a connect link's `?channel=` parameter.
  /// Navigate links use [channelId] instead.
  final String? channelName;

  /// For `navigate` links: the target space id (and optional channel/message).
  final String? spaceId;
  final String? channelId;
  final String? messageId;

  /// For `federate` links: the remote home domain hosting the space to join.
  final String? domain;

  const ParsedServerUrl({
    this.server,
    this.route = 'connect',
    this.token,
    this.invite,
    this.spaceName,
    this.channelName,
    this.spaceId,
    this.channelId,
    this.messageId,
    this.domain,
  });

  bool get hasInvite => invite != null && invite!.isNotEmpty;
}

/// Parsing for "Add a Server" URLs and `daccord://` deep links.
class ServerUri {
  /// Parses the Enter-URL field's format:
  /// `[protocol://]host[:port][#space-name][?token=value&invite=code]`.
  ///
  /// Mirrors the reference `add_server_dialog.gd::parse_server_url`: query is
  /// stripped first (it can follow the fragment), then the `#space-name`
  /// fragment, then `https://` is assumed when no scheme is present.
  static ParsedServerUrl? parseServerUrl(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('daccord://')) return parseDeepLink(text);

    String? token;
    String? invite;
    String? spaceName;

    final qPos = text.indexOf('?');
    if (qPos != -1) {
      final query = text.substring(qPos + 1);
      text = text.substring(0, qPos);
      final params = _parseQuery(query);
      if (params == null) return null;
      token = params['token'];
      invite = params['invite'];
    }

    final hPos = text.indexOf('#');
    if (hPos != -1) {
      final namePart = text.substring(hPos + 1);
      if (namePart.isNotEmpty) spaceName = namePart;
      text = text.substring(0, hPos);
    }

    if (text.isEmpty) return null;

    final AccordServer server;
    try {
      server = AccordServer.fromBaseUrl(text);
    } on FormatException {
      return null;
    }
    return ParsedServerUrl(
      server: server,
      route: 'connect',
      token: _blankToNull(token),
      invite: _blankToNull(invite),
      spaceName: spaceName,
    );
  }

  /// Parses a `daccord://` deep link. Supported routes (matching
  /// `uri_handler.gd`):
  ///   `daccord://connect/<host>[:<port>][/<space-slug>][?token=&invite=]`
  ///   `daccord://invite/<code>@<host>[:<port>]`
  ///   `daccord://navigate/<space-id>[/<channel-id>][?msg=<message-id>]`
  ///   `daccord://federate/<space-id>@<home-domain>`
  static ParsedServerUrl? parseDeepLink(String uri) {
    var text = uri.trim();
    const scheme = 'daccord://';
    if (!text.startsWith(scheme)) return null;
    text = text.substring(scheme.length);
    if (text.isEmpty) return null;

    final slash = text.indexOf('/');
    if (slash == -1) return null;
    final route = text.substring(0, slash);
    final payload = text.substring(slash + 1);
    if (payload.isEmpty) return null;

    switch (route) {
      case 'connect':
        return _parseConnect(payload);
      case 'invite':
        return _parseInvite(payload);
      case 'navigate':
        return _parseNavigate(payload);
      case 'federate':
        return _parseFederate(payload);
      default:
        return null;
    }
  }

  /// Parses `daccord://federate/<space-id>@<home-domain>` — join a space homed
  /// on a remote federated server. The current connection performs the join.
  static ParsedServerUrl? _parseFederate(String payload) {
    final at = payload.lastIndexOf('@');
    if (at <= 0 || at == payload.length - 1) return null;
    final spaceId = payload.substring(0, at);
    final authority = payload.substring(at + 1);
    if (_hostFromAuthority(authority) == null) return null;
    return ParsedServerUrl(
      route: 'federate',
      spaceId: spaceId,
      domain: authority,
    );
  }

  static ParsedServerUrl? _parseConnect(String payload) {
    String? token;
    String? invite;
    String? channelName;
    String? spaceSlug;

    final qPos = payload.indexOf('?');
    if (qPos != -1) {
      final params = _parseQuery(payload.substring(qPos + 1));
      if (params == null) return null;
      payload = payload.substring(0, qPos);
      token = params['token'];
      invite = params['invite'];
      channelName = params['channel'];
    }

    final slugPos = payload.indexOf('/');
    if (slugPos != -1) {
      final slugPart = payload.substring(slugPos + 1);
      if (slugPart.isNotEmpty) {
        spaceSlug = _decodeComponent(slugPart);
        if (spaceSlug == null) return null;
      }
      payload = payload.substring(0, slugPos);
    }
    if (payload.isEmpty) return null;

    final host = _hostFromAuthority(payload);
    if (host == null) return null;

    return ParsedServerUrl(
      server: AccordServer.fromBaseUrl(_baseUrlFor(payload)),
      route: 'connect',
      token: _blankToNull(token),
      invite: _blankToNull(invite),
      spaceName: spaceSlug,
      channelName: _blankToNull(channelName),
    );
  }

  static ParsedServerUrl? _parseInvite(String payload) {
    final at = payload.indexOf('@');
    if (at <= 0) return null;
    final code = payload.substring(0, at);
    final authority = payload.substring(at + 1);
    if (authority.isEmpty || !_isAlphanumeric(code)) return null;
    final host = _hostFromAuthority(authority);
    if (host == null) return null;
    return ParsedServerUrl(
      server: AccordServer.fromBaseUrl(_baseUrlFor(authority)),
      route: 'invite',
      invite: code,
    );
  }

  static ParsedServerUrl? _parseNavigate(String payload) {
    String? messageId;
    final qPos = payload.indexOf('?');
    if (qPos != -1) {
      final params = _parseQuery(payload.substring(qPos + 1));
      if (params == null) return null;
      payload = payload.substring(0, qPos);
      messageId = params['msg'];
    }
    final parts = payload.split('/');
    if (parts.isEmpty || parts.first.isEmpty || parts.length > 2) return null;
    final spaceId = _decodeComponent(parts[0]);
    final channelId = parts.length > 1 && parts[1].isNotEmpty
        ? _decodeComponent(parts[1])
        : null;
    if (spaceId == null ||
        channelId == null && parts.length > 1 && parts[1].isNotEmpty) {
      return null;
    }
    if (messageId != null && channelId == null) return null;
    return ParsedServerUrl(
      route: 'navigate',
      spaceId: spaceId,
      channelId: channelId,
      messageId: _blankToNull(messageId),
    );
  }

  /// Splits `host[:port]` and validates the host. Returns the host or null.
  static String? _hostFromAuthority(String authority) {
    var host = authority;
    final colon = authority.lastIndexOf(':');
    if (colon != -1) {
      final portStr = authority.substring(colon + 1);
      if (int.tryParse(portStr) != null) {
        host = authority.substring(0, colon);
      }
    }
    if (host.isEmpty || !_isValidHost(host)) return null;
    return host;
  }

  /// Builds an `https://host[:port]` base URL from a `host[:port]` authority.
  static String _baseUrlFor(String authority) => 'https://$authority';

  static Map<String, String>? _parseQuery(String query) {
    final out = <String, String>{};
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      final key = _decodeComponent(pair.substring(0, eq));
      final value = _decodeComponent(pair.substring(eq + 1));
      if (key == null || value == null) return null;
      out[key] = value;
    }
    return out;
  }

  static String? _decodeComponent(String value) {
    try {
      return Uri.decodeQueryComponent(value);
    } on ArgumentError {
      return null;
    }
  }

  static bool _isAlphanumeric(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(s);
  }

  /// Validates a bare host (port already split off). Uses a strict hostname
  /// allowlist rather than a denylist so userinfo (`@`), path separators
  /// (`/`, `\`) and other URL metacharacters can't smuggle the auth-bearing
  /// base URL onto a different host than the one shown. Loopback is allowed
  /// here — a user may legitimately point at a self-hosted dev server.
  static bool _isValidHost(String host) => isValidHost(host);

  static String? _blankToNull(String? v) =>
      (v == null || v.isEmpty) ? null : v;
}
