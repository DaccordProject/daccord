/// Host validation for federation domains and server authorities.
///
/// Federated entities carry an `origin`/`@domain` minted by a *peer* server, and
/// the client turns that into URLs it then fetches — CDN media for any remote
/// origin, and (for pasted server URLs / deep links) the auth-bearing base URL.
/// Validate the host here before interpolating it into a URL so a peer can't
/// smuggle userinfo/path into the authority or point the client at a loopback /
/// link-local address (client-side SSRF, cloud-metadata at 169.254.169.254).
library;

/// Whether [host] is a syntactically valid DNS hostname or IPv4 literal — only
/// ASCII letters, digits, dots and hyphens, with no empty or edge labels. Does
/// not accept a port, scheme, userinfo, or path; split those off first. IPv6
/// literals (which need bracketing and contain colons) are intentionally not
/// accepted.
bool isValidHost(String host) {
  if (host.isEmpty || host.length > 253) return false;
  if (!RegExp(r'^[A-Za-z0-9.-]+$').hasMatch(host)) return false;
  if (host.startsWith('.') ||
      host.endsWith('.') ||
      host.startsWith('-') ||
      host.endsWith('-') ||
      host.contains('..')) {
    return false;
  }
  return true;
}

/// Whether [host] denotes a loopback or link-local address (or `localhost`). A
/// federated peer must never be allowed to point the client at one: it would
/// turn the client into an SSRF probe against its own host or cloud metadata
/// (`169.254.169.254`). [host] must be bare (no port). This is *not* applied to
/// user-entered server URLs, where loopback is a legitimate self-host target.
bool isLoopbackOrLinkLocalHost(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  if (h == '0.0.0.0' || h == '::1' || h == '[::1]') return true;
  final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.\d{1,3}\.\d{1,3}$').firstMatch(h);
  if (v4 != null) {
    final a = int.parse(v4.group(1)!);
    final b = int.parse(v4.group(2)!);
    if (a == 127) return true; // 127.0.0.0/8 loopback
    if (a == 169 && b == 254) return true; // 169.254.0.0/16 link-local (metadata)
  }
  return false;
}
