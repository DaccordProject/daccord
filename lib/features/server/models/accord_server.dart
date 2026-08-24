/// Connection details for a single Accord server.
///
/// Bonfire hard-coded `discord.com`; Daccord can point at any Accord instance,
/// so every connection carries its own base/gateway/CDN URLs. Gateway and CDN
/// URLs are normally derived from the base URL by convention
/// (`ws(s)://<host>/ws`, `<base>/cdn`) via [AccordServer.fromBaseUrl].
class AccordServer {
  final String baseUrl;
  final String gatewayUrl;
  final String cdnUrl;

  /// A human-friendly label (defaults to the host) for the account switcher.
  final String? name;

  const AccordServer({
    required this.baseUrl,
    required this.gatewayUrl,
    required this.cdnUrl,
    this.name,
  });

  /// Derives gateway/CDN URLs from a single [rawBaseUrl] using Accord
  /// conventions. Accepts bare hosts (`my.server`), assuming `https`.
  factory AccordServer.fromBaseUrl(String rawBaseUrl, {String? name}) {
    final base = normalizeBaseUrl(rawBaseUrl);
    final uri = Uri.parse(base);
    final wsScheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final gateway = uri.replace(scheme: wsScheme, path: '/ws').toString();
    return AccordServer(
      baseUrl: base,
      gatewayUrl: gateway,
      cdnUrl: '$base/cdn',
      name: name ?? uri.host,
    );
  }

  /// Trims whitespace, assumes `https://` when no scheme is given, and strips
  /// trailing slashes so URL building stays predictable.
  static String normalizeBaseUrl(String input) {
    var v = input.trim();
    if (v.isEmpty) return v;
    if (!v.contains('://')) v = 'https://$v';
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }
    return v;
  }

  /// The server's federation home domain — the base URL host (e.g.
  /// `a.example`). Qualified IDs minted by this server suffix `@<homeDomain>`,
  /// so this is what recognises the local user's own actions when they echo back
  /// qualified from a remote home. Mirrors the server's federation `domain`.
  String get homeDomain => Uri.parse(baseUrl).host;

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl,
    'gatewayUrl': gatewayUrl,
    'cdnUrl': cdnUrl,
    if (name != null) 'name': name,
  };

  factory AccordServer.fromJson(Map<String, dynamic> json) => AccordServer(
    baseUrl: json['baseUrl'] as String,
    gatewayUrl: json['gatewayUrl'] as String,
    cdnUrl: json['cdnUrl'] as String,
    name: json['name'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is AccordServer &&
      other.baseUrl == baseUrl &&
      other.gatewayUrl == gatewayUrl &&
      other.cdnUrl == cdnUrl;

  @override
  int get hashCode => Object.hash(baseUrl, gatewayUrl, cdnUrl);

  @override
  String toString() => 'AccordServer(${name ?? baseUrl})';
}
