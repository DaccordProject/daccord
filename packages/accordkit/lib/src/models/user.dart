import '../utils/json_utils.dart';

/// A user account on an Accord instance.
class AccordUser {
  String id;
  String username;
  String? displayName;
  String? avatar;
  String? banner;
  Object? accentColor;
  String? bio;
  bool bot;
  bool system;
  int flags;
  int publicFlags;
  bool isAdmin;
  bool mfaEnabled;
  bool disabled;
  bool isGuest;
  String createdAt;

  AccordUser({
    this.id = '',
    this.username = '',
    this.displayName,
    this.avatar,
    this.banner,
    this.accentColor,
    this.bio,
    this.bot = false,
    this.system = false,
    this.flags = 0,
    this.publicFlags = 0,
    this.isAdmin = false,
    this.mfaEnabled = false,
    this.disabled = false,
    this.isGuest = false,
    this.createdAt = '',
  });

  factory AccordUser.fromJson(Map<String, dynamic> d) {
    return AccordUser(
      id: asString(d['id']),
      username: asString(d['username']),
      displayName: d['display_name'] as String?,
      avatar: d['avatar'] as String?,
      banner: d['banner'] as String?,
      accentColor: d['accent_color'],
      bio: d['bio'] as String?,
      bot: asBool(d['bot']),
      system: asBool(d['system']),
      flags: asInt(d['flags']),
      publicFlags: asInt(d['public_flags']),
      isAdmin: asBool(d['is_admin']),
      mfaEnabled: asBool(d['mfa_enabled']),
      disabled: asBool(d['disabled']),
      isGuest: asBool(d['is_guest']),
      createdAt: asString(d['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'username': username,
      'bot': bot,
      'system': system,
      'flags': flags,
      'public_flags': publicFlags,
      'is_admin': isAdmin,
      'mfa_enabled': mfaEnabled,
      'disabled': disabled,
      'is_guest': isGuest,
      'created_at': createdAt,
    };
    if (displayName != null) d['display_name'] = displayName;
    if (avatar != null) d['avatar'] = avatar;
    if (banner != null) d['banner'] = banner;
    if (accentColor != null) d['accent_color'] = accentColor;
    if (bio != null) d['bio'] = bio;
    return d;
  }
}
