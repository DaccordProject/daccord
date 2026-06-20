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

    final server = AccordServer.fromBaseUrl(text);
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
    final host = _hostFromAuthority(authority);
    if (host == null) return null;
    return ParsedServerUrl(
      route: 'federate',
      spaceId: spaceId,
      domain: authority,
    );
  }

  static ParsedServerUrl? _parseConnect(String payload) {
    String? token;
    String? invite;
    String? spaceSlug;

    final qPos = payload.indexOf('?');
    if (qPos != -1) {
      final params = _parseQuery(payload.substring(qPos + 1));
      payload = payload.substring(0, qPos);
      token = params['token'];
      invite = params['invite'];
    }

    final slugPos = payload.indexOf('/');
    if (slugPos != -1) {
      final slugPart = payload.substring(slugPos + 1);
      if (slugPart.isNotEmpty) spaceSlug = slugPart;
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
      payload = payload.substring(0, qPos);
      messageId = params['msg'];
    }
    final parts = payload.split('/');
    if (parts.isEmpty || parts.first.isEmpty) return null;
    return ParsedServerUrl(
      route: 'navigate',
      spaceId: parts[0],
      channelId: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
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

  static Map<String, String> _parseQuery(String query) {
    final out = <String, String>{};
    for (final pair in query.split('&')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      out[pair.substring(0, eq)] = pair.substring(eq + 1);
    }
    return out;
  }

  static bool _isAlphanumeric(String s) {
    if (s.isEmpty) return false;
    return RegExp(r'^[A-Za-z0-9]+$').hasMatch(s);
  }

  static bool _isValidHost(String host) {
    if (host.isEmpty || host.contains(' ')) return false;
    return !RegExp('''[<>;'"]''').hasMatch(host);
  }

  static String? _blankToNull(String? v) =>
      (v == null || v.isEmpty) ? null : v;
}
