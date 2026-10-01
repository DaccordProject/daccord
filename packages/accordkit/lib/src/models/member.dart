import '../utils/json_utils.dart';
import '../utils/qualified_id.dart';
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

  /// Home domain for a federated (remote) member, or `null` when local. Falls
  /// back to the domain embedded in a qualified [userId] when not set
  /// explicitly. See [isRemote].
  String? origin;

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
    this.origin,
  }) : roles = roles ?? [];

  /// The member's home domain when remote: the explicit [origin], else the
  /// domain embedded in a qualified [userId] (or the user's own origin).
  String? get homeDomain =>
      origin ?? domainOf(userId) ?? user?.origin ?? domainOf(user?.id ?? '');

  /// Whether this member is homed on a remote (federated) server.
  bool get isRemote => homeDomain != null;

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
      origin: asStringOrNull(d['origin']),
    );

    final rawUser = asMap(d['user']);
    if (rawUser != null) {
      m.userId = asString(rawUser['id']);
      m.user = AccordUser.fromJson(rawUser);
    } else {
      m.userId = asString(d['user_id']);
    }
    // Inherit the home domain from the user object or a qualified id when the
    // member row didn't carry an explicit `origin`.
    m.origin ??= m.user?.origin ?? domainOf(m.userId);

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
    if (origin != null) d['origin'] = origin;
    return d;
  }
}
