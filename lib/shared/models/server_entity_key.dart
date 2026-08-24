import 'dart:convert';

/// Stable identity for an entity whose ID is unique only within one server.
///
/// The encoded form is used in persisted settings. A versioned, base64url JSON
/// payload avoids delimiter ambiguity when either component contains `@`, `/`,
/// or another character that is valid in a connection key.
class ServerEntityKey {
  const ServerEntityKey(this.serverKey, this.entityId);

  static const _prefix = 'server-entity-v1:';

  final String serverKey;
  final String entityId;

  String get encoded {
    final payload = jsonEncode([serverKey, entityId]);
    return '$_prefix${base64Url.encode(utf8.encode(payload)).replaceAll('=', '')}';
  }

  static ServerEntityKey? tryDecode(String value) {
    if (!value.startsWith(_prefix)) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(value.substring(_prefix.length))),
      );
      final decoded = jsonDecode(payload);
      if (decoded is! List || decoded.length != 2) return null;
      final serverKey = decoded[0];
      final entityId = decoded[1];
      if (serverKey is! String || entityId is! String) return null;
      return ServerEntityKey(serverKey, entityId);
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ServerEntityKey &&
      other.serverKey == serverKey &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(serverKey, entityId);
}
