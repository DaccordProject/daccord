import 'package:bonfire/features/server/models/accord_server.dart';

/// A persisted, restorable Accord login: which [server], the auth [token], and
/// who it belongs to. Stored in the `accord-session` Hive box so the app can
/// reconnect on launch without re-prompting for credentials.
class AccordSession {
  final AccordServer server;
  final String token;

  /// `'User'` for human logins, `'Bot'` for bot tokens. Sent on REST headers
  /// and the gateway IDENTIFY.
  final String tokenType;

  final String userId;
  final String username;
  final String? avatar;

  const AccordSession({
    required this.server,
    required this.token,
    this.tokenType = 'User',
    required this.userId,
    required this.username,
    this.avatar,
  });

  Map<String, dynamic> toJson() => {
        'server': server.toJson(),
        'token': token,
        'tokenType': tokenType,
        'userId': userId,
        'username': username,
        if (avatar != null) 'avatar': avatar,
      };

  factory AccordSession.fromJson(Map<String, dynamic> json) => AccordSession(
        server: AccordServer.fromJson(
            Map<String, dynamic>.from(json['server'] as Map)),
        token: json['token'] as String,
        tokenType: json['tokenType'] as String? ?? 'User',
        userId: json['userId'] as String,
        username: json['username'] as String,
        avatar: json['avatar'] as String?,
      );
}
