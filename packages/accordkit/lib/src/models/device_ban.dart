import '../utils/json_utils.dart';

/// An instance-level ban on a device fingerprint. Created by an instance
/// admin from an account's recorded devices; it blocks registration and
/// sign-in from that device without disabling any account by itself.
class AccordDeviceBan {
  String id;

  /// The per-server device fingerprint (64 lowercase hex characters).
  String fingerprint;

  /// The account the device was recorded against, when known.
  String? userId;
  String? username;
  String? reason;
  String? bannedBy;
  String createdAt;

  AccordDeviceBan({
    this.id = '',
    this.fingerprint = '',
    this.userId,
    this.username,
    this.reason,
    this.bannedBy,
    this.createdAt = '',
  });

  factory AccordDeviceBan.fromJson(Map<String, dynamic> d) {
    return AccordDeviceBan(
      id: asString(d['id']),
      fingerprint: asString(d['fingerprint']),
      userId: asStringOrNull(d['user_id']),
      username: asStringOrNull(d['username']),
      reason: asStringOrNull(d['reason']),
      bannedBy: asStringOrNull(d['banned_by']),
      createdAt: asString(d['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fingerprint': fingerprint,
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (reason != null) 'reason': reason,
      if (bannedBy != null) 'banned_by': bannedBy,
      'created_at': createdAt,
    };
  }
}
