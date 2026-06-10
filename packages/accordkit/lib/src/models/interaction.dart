import '../utils/json_utils.dart';
import 'message.dart';

/// An interaction (slash command invocation, component use, etc.).
class AccordInteraction {
  String id;
  String applicationId;
  String type;
  Object? data;
  String? spaceId;
  String? channelId;
  String? memberId;
  String? userId;
  String token;
  AccordMessage? message;
  Object? locale;

  AccordInteraction({
    this.id = '',
    this.applicationId = '',
    this.type = 'command',
    this.data,
    this.spaceId,
    this.channelId,
    this.memberId,
    this.userId,
    this.token = '',
    this.message,
    this.locale,
  });

  factory AccordInteraction.fromJson(Map<String, dynamic> d) {
    final i = AccordInteraction(
      id: asString(d['id']),
      applicationId: asString(d['application_id']),
      type: asString(d['type'], 'command'),
      data: d['data'],
      spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
      channelId: asStringOrNull(d['channel_id']),
      token: asString(d['token']),
      locale: d['locale'],
    );

    final rawMember = asMap(d['member']);
    if (rawMember != null) {
      final memberUser = asMap(rawMember['user']);
      if (memberUser != null) i.memberId = asString(memberUser['id']);
    } else {
      i.memberId = asStringOrNull(d['member_id']);
    }

    final rawUser = asMap(d['user']);
    if (rawUser != null) {
      i.userId = asString(rawUser['id']);
    } else {
      i.userId = asStringOrNull(d['user_id']);
    }

    final rawMessage = asMap(d['message']);
    if (rawMessage != null) i.message = AccordMessage.fromJson(rawMessage);

    return i;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'application_id': applicationId,
      'type': type,
      'token': token,
    };
    if (data != null) d['data'] = data;
    if (spaceId != null) d['space_id'] = spaceId;
    if (channelId != null) d['channel_id'] = channelId;
    if (memberId != null) d['member_id'] = memberId;
    if (userId != null) d['user_id'] = userId;
    if (message != null) d['message'] = message!.toJson();
    if (locale != null) d['locale'] = locale;
    return d;
  }
}
