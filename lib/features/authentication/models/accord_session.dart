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

  const AccordSession({
    required this.server,
    required this.token,
    this.tokenType = 'Bearer',
    required this.userId,
    required this.username,
    this.avatar,
    this.isAdmin = false,
  });

  Map<String, dynamic> toJson() => {
        'server': server.toJson(),
        'token': token,
        'tokenType': tokenType,
        'userId': userId,
        'username': username,
        if (avatar != null) 'avatar': avatar,
        'isAdmin': isAdmin,
      };

  factory AccordSession.fromJson(Map<String, dynamic> json) => AccordSession(
        server: AccordServer.fromJson(
            Map<String, dynamic>.from(json['server'] as Map)),
        token: json['token'] as String,
        tokenType: json['tokenType'] as String? ?? 'Bearer',
        userId: json['userId'] as String,
        username: json['username'] as String,
        avatar: json['avatar'] as String?,
        isAdmin: json['isAdmin'] as bool? ?? false,
      );
}
