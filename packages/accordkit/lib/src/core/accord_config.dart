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

  String baseUrl;
  String gatewayUrl;
  String cdnUrl;

  AccordConfig({
    this.baseUrl = defaultBaseUrl,
    this.gatewayUrl = defaultGatewayUrl,
    this.cdnUrl = defaultCdnUrl,
  });

  /// The fully-qualified REST API root (base URL + versioned API path).
  String apiUrl() => baseUrl + apiBasePath;

  /// The gateway WebSocket URL including the version/encoding query string.
  String gatewayConnectUrl() => '$gatewayUrl?v=1&encoding=json';
}
