import 'dart:convert';

import 'package:bonfire/features/server/models/accord_server.dart';

/// A persisted, restorable Accord login: which [server], the auth [token], and
/// who it belongs to. Stored in the `accord-session` Hive box so the app can
/// reconnect on launch without re-prompting for credentials.
class AccordSession {
  final AccordServer server;
  final String token;

  /// The HTTP auth scheme prefix: `'Bearer'` for human/guest logins, `'Bot'`
  /// for bot tokens. Sent verbatim as `Authorization: <tokenType> <token>` on
  /// REST headers and in the gateway IDENTIFY (accordkit interpolates it).
  final String tokenType;

  final String userId;
  final String username;
  final String? avatar;

  /// Whether the account is an instance administrator. Drives the global
  /// permission bypass (see `permissions.dart`); persisted so restored
  /// sessions keep moderation affordances without an extra round-trip.
  final bool isAdmin;

  /// Guest tokens are anonymous, read-only credentials that must never be
  /// written to Hive or restored after an app restart.
  final bool isGuest;

  /// Server/JWT expiry for a guest credential, when supplied. Ordinary user
  /// sessions generally leave this null.
  final DateTime? expiresAt;

  const AccordSession({
    required this.server,
    required this.token,
    this.tokenType = 'Bearer',
    required this.userId,
    required this.username,
    this.avatar,
    this.isAdmin = false,
    this.isGuest = false,
    this.expiresAt,
  });

  /// Stable identity: user + server. Matches `AccordConnection.key` so the auth
  /// layer and the rail registry agree on how to address a connection.
  String get key => '$userId@${server.baseUrl}';

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now.toUtc());

  bool get isExpired => isExpiredAt(DateTime.now().toUtc());

  Map<String, dynamic> toJson() => {
    'server': server.toJson(),
    'token': token,
    'tokenType': tokenType,
    'userId': userId,
    'username': username,
    if (avatar != null) 'avatar': avatar,
    'isAdmin': isAdmin,
    'isGuest': isGuest,
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  factory AccordSession.fromJson(Map<String, dynamic> json) => AccordSession(
    server: AccordServer.fromJson(
      Map<String, dynamic>.from(json['server'] as Map),
    ),
    token: json['token'] as String,
    tokenType: json['tokenType'] as String? ?? 'Bearer',
    userId: json['userId'] as String,
    username: json['username'] as String,
    avatar: json['avatar'] as String?,
    isAdmin: json['isAdmin'] as bool? ?? false,
    isGuest: json['isGuest'] as bool? ?? false,
    expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toUtc(),
  );
}

/// Reads the expiry formats used by guest-token endpoints, falling back to a
/// JWT `exp` claim. Null means the server did not disclose an expiry.
DateTime? guestSessionExpiry(
  Map<Object?, Object?> data,
  String token, {
  DateTime? now,
}) {
  final rawExpiry = data['expires_at'];
  if (rawExpiry is num) return _epoch(rawExpiry);
  if (rawExpiry is String) {
    final parsed = DateTime.tryParse(rawExpiry);
    if (parsed != null) return parsed.toUtc();
    final numeric = num.tryParse(rawExpiry);
    if (numeric != null) return _epoch(numeric);
  }

  final rawDuration = data['expires_in'];
  final seconds = rawDuration is num
      ? rawDuration.toInt()
      : int.tryParse(rawDuration?.toString() ?? '');
  if (seconds != null && seconds >= 0) {
    return (now ?? DateTime.now()).toUtc().add(Duration(seconds: seconds));
  }

  final parts = token.split('.');
  if (parts.length == 3) {
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is Map && payload['exp'] is num) {
        return _epoch(payload['exp'] as num);
      }
    } catch (_) {
      // Opaque and malformed tokens are valid possibilities; expiry stays
      // unknown rather than treating them as permanent.
    }
  }
  return null;
}

DateTime _epoch(num value) {
  final integer = value.toInt();
  final milliseconds = integer > 100000000000 ? integer : integer * 1000;
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}
