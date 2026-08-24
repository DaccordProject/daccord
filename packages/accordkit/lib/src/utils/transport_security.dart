/// Returns whether [host] is a genuine local loopback destination.
///
/// Cleartext transports are useful for a server running on the same machine,
/// but must not be enabled for wildcard, private-network, or link-local
/// addresses. Those destinations can still expose credentials on the wire.
bool isLoopbackHost(String host) {
  var normalized = host.trim().toLowerCase();
  if (normalized.startsWith('[') && normalized.endsWith(']')) {
    normalized = normalized.substring(1, normalized.length - 1);
  }
  if (normalized == 'localhost' ||
      normalized == '::1' ||
      normalized == '0:0:0:0:0:0:0:1') {
    return true;
  }

  final octets = normalized.split('.');
  if (octets.length != 4) return false;
  final values = octets.map(int.tryParse).toList();
  return values.every((value) => value != null && value >= 0 && value <= 255) &&
      values.first == 127;
}

/// Validates an Accord HTTP endpoint and returns its parsed URI.
///
/// Remote endpoints must use HTTPS. HTTP is accepted only for genuine
/// loopback development servers such as `localhost`, `127.0.0.1`, and `::1`.
Uri validateHttpEndpoint(String endpoint, {String label = 'HTTP endpoint'}) =>
    _validateEndpoint(
      endpoint,
      label: label,
      secureScheme: 'https',
      cleartextScheme: 'http',
    );

/// Validates an Accord WebSocket endpoint and returns its parsed URI.
///
/// Remote endpoints must use WSS. WS is accepted only for genuine loopback
/// development servers such as `localhost`, `127.0.0.1`, and `::1`.
Uri validateWebSocketEndpoint(
  String endpoint, {
  String label = 'WebSocket endpoint',
}) =>
    _validateEndpoint(
      endpoint,
      label: label,
      secureScheme: 'wss',
      cleartextScheme: 'ws',
    );

Uri _validateEndpoint(
  String endpoint, {
  required String label,
  required String secureScheme,
  required String cleartextScheme,
}) {
  final uri = Uri.tryParse(endpoint);
  if (uri == null || !uri.isAbsolute || uri.host.isEmpty) {
    throw FormatException('$label must be an absolute URL.');
  }

  final scheme = uri.scheme.toLowerCase();
  if (scheme == secureScheme) return uri;
  if (scheme == cleartextScheme && isLoopbackHost(uri.host)) return uri;

  final secureLabel = secureScheme.toUpperCase();
  final cleartextLabel = cleartextScheme.toUpperCase();
  throw FormatException(
    '$label must use $secureLabel. $cleartextLabel is allowed only for '
    'loopback development.',
  );
}
