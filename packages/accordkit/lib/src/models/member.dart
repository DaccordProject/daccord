import '../utils/json_utils.dart';
import 'user.dart';

/// A member of a space (a user plus space-scoped data).
class AccordMember {
  String userId;
  AccordUser? user;
  String spaceId;
  String? nickname;
  Object? avatar;
  List<String> roles;
  String joinedAt;
  Object? premiumSince;
  bool deaf;
  bool mute;
  Object? pending;
  Object? timedOutUntil;
  Object? permissions;

  AccordMember({
    this.userId = '',
    this.user,
    this.spaceId = '',
    this.nickname,
    this.avatar,
    List<String>? roles,
    this.joinedAt = '',
    this.premiumSince,
    this.deaf = false,
    this.mute = false,
    this.pending,
    this.timedOutUntil,
    this.permissions,
  }) : roles = roles ?? [];

  factory AccordMember.fromJson(Map<String, dynamic> d) {
    final m = AccordMember(
      spaceId: asString(d['space_id'] ?? d['guild_id']),
      nickname: (d['nick'] ?? d['nickname']) as String?,
      avatar: d['avatar'],
      joinedAt: asString(d['joined_at']),
      premiumSince: d['premium_since'],
      deaf: asBool(d['deaf']),
      mute: asBool(d['mute']),
      pending: d['pending'],
      timedOutUntil: d['communication_disabled_until'] ?? d['timed_out_until'],
      permissions: d['permissions'],
    );

    final rawUser = asMap(d['user']);
    if (rawUser != null) {
      m.userId = asString(rawUser['id']);
      m.user = AccordUser.fromJson(rawUser);
    } else {
      m.userId = asString(d['user_id']);
    }

    for (final r in asList(d['roles']) ?? const []) {
      m.roles.add(asString(r));
    }
    return m;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'user_id': userId,
      'space_id': spaceId,
      'roles': roles,
      'joined_at': joinedAt,
      'deaf': deaf,
      'mute': mute,
    };
    if (nickname != null) d['nickname'] = nickname;
    if (avatar != null) d['avatar'] = avatar;
    if (premiumSince != null) d['premium_since'] = premiumSince;
    if (pending != null) d['pending'] = pending;
    if (timedOutUntil != null) d['timed_out_until'] = timedOutUntil;
    if (permissions != null) d['permissions'] = permissions;
    return d;
  }
}
