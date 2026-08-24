import '../utils/transport_security.dart';

/// Connection configuration for an [AccordClient]: base, gateway, and CDN
/// URLs plus protocol-level constants shared across the REST and gateway
/// layers.
class AccordConfig {
  static const String apiVersion = 'v1';
  static const String apiBasePath = '/api/$apiVersion';
  static const String defaultBaseUrl = 'http://localhost:3000';
  static const String defaultGatewayUrl = 'ws://localhost:3000/ws';
  static const String defaultCdnUrl = 'http://localhost:3000/cdn';

  static const String userAgent = 'AccordKit (Dart, 2.0.0)';
  static const String clientVersion = '2.0.0';

  static const int heartbeatIntervalDefault = 45000;

  /// Lower bound applied to the server-advertised `heartbeat_interval`.
  ///
  /// A zero or negative interval makes the periodic heartbeat timer fire as
  /// quickly as the event loop allows, creating a CPU and network hot loop.
  /// One second still tolerates an unusually aggressive server while bounding
  /// the work a misconfigured or malicious server can trigger.
  static const int heartbeatIntervalMin = 1000;

  /// Upper bound applied to the server-advertised `heartbeat_interval`.
  ///
  /// The heartbeat doubles as the only keepalive traffic on an otherwise-idle
  /// gateway socket. Many network intermediaries (home NATs, VPNs, corporate
  /// firewalls, some CDN edges) silently drop idle WebSockets after ~30s — and
  /// the server's default 45s interval is longer than that, so the socket is
  /// culled (close 1006) before the first heartbeat ever fires, causing an
  /// endless connect→drop flap. Capping the effective interval keeps a beat on
  /// the wire well inside a 30s idle timeout so the connection survives.
  static const int heartbeatIntervalMax = 15000;

  final String baseUrl;
  final String gatewayUrl;
  final String cdnUrl;

  AccordConfig({
    this.baseUrl = defaultBaseUrl,
    this.gatewayUrl = defaultGatewayUrl,
    this.cdnUrl = defaultCdnUrl,
  }) {
    validateHttpEndpoint(baseUrl, label: 'Accord server URL');
    validateWebSocketEndpoint(gatewayUrl, label: 'Accord gateway URL');
    validateHttpEndpoint(cdnUrl, label: 'Accord CDN URL');
  }

  /// The fully-qualified REST API root (base URL + versioned API path).
  String apiUrl() => baseUrl + apiBasePath;

  /// The gateway WebSocket URL including the version/encoding query string.
  String gatewayConnectUrl() => '$gatewayUrl?v=1&encoding=json';
}
