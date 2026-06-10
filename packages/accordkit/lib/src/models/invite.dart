import '../utils/json_utils.dart';

/// An invite to a space or channel.
class AccordInvite {
  String code;
  String spaceId;
  String channelId;
  String? inviterId;
  Object? maxUses;
  int uses;
  Object? maxAge;
  bool temporary;
  String createdAt;
  Object? expiresAt;

  AccordInvite({
    this.code = '',
    this.spaceId = '',
    this.channelId = '',
    this.inviterId,
    this.maxUses,
    this.uses = 0,
    this.maxAge,
    this.temporary = false,
    this.createdAt = '',
    this.expiresAt,
  });

  factory AccordInvite.fromJson(Map<String, dynamic> d) {
    final i = AccordInvite(
      code: asString(d['code']),
      spaceId: asString(d['space_id'] ?? d['guild_id']),
      channelId: asString(d['channel_id']),
      maxUses: d['max_uses'],
      uses: asInt(d['uses']),
      maxAge: d['max_age'],
      temporary: asBool(d['temporary']),
      createdAt: asString(d['created_at']),
      expiresAt: d['expires_at'],
    );
    final rawInviter = asMap(d['inviter']);
    if (rawInviter != null) {
      i.inviterId = asString(rawInviter['id']);
    } else {
      i.inviterId = asStringOrNull(d['inviter_id']);
    }
    return i;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'code': code,
      'space_id': spaceId,
      'channel_id': channelId,
      'uses': uses,
      'temporary': temporary,
      'created_at': createdAt,
    };
    if (inviterId != null) d['inviter_id'] = inviterId;
    if (maxUses != null) d['max_uses'] = maxUses;
    if (maxAge != null) d['max_age'] = maxAge;
    if (expiresAt != null) d['expires_at'] = expiresAt;
    return d;
  }
}
