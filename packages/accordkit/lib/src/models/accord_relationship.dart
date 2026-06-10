import '../utils/json_utils.dart';
import 'user.dart';

/// A relationship between the current user and another user.
///
/// [type] mirrors the server enum: 1 = friend, 2 = blocked,
/// 3 = pending incoming, 4 = pending outgoing.
class AccordRelationship {
  String id;
  AccordUser? user;
  int type;
  String since;

  /// Presence status of the related user (online/idle/dnd/offline).
  String userStatus;

  /// Presence activities of the related user.
  List<dynamic> userActivities;

  AccordRelationship({
    this.id = '',
    this.user,
    this.type = 0,
    this.since = '',
    this.userStatus = '',
    List<dynamic>? userActivities,
  }) : userActivities = userActivities ?? [];

  factory AccordRelationship.fromJson(Map<String, dynamic> d) {
    final r = AccordRelationship(
      id: asString(d['id']),
      type: asInt(d['type']),
      since: asString(d['since']),
    );
    final rawUser = asMap(d['user']);
    if (rawUser != null) {
      r.user = AccordUser.fromJson(rawUser);
      r.userStatus = asString(rawUser['status']);
      r.userActivities = asList(rawUser['activities']) ?? [];
    }
    return r;
  }
}
