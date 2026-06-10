import '../utils/json_utils.dart';
import 'activity.dart';

/// A presence update describing a user's status and activities.
class AccordPresence {
  String userId;
  String status;
  Map<String, dynamic> clientStatus;
  List<AccordActivity> activities;
  String? spaceId;

  AccordPresence({
    this.userId = '',
    this.status = 'offline',
    Map<String, dynamic>? clientStatus,
    List<AccordActivity>? activities,
    this.spaceId,
  })  : clientStatus = clientStatus ?? {},
        activities = activities ?? [];

  factory AccordPresence.fromJson(Map<String, dynamic> d) {
    final p = AccordPresence(
      status: asString(d['status'], 'offline'),
      clientStatus: asMap(d['client_status']) ?? {},
      spaceId: asStringOrNull(d['space_id'] ?? d['guild_id']),
    );

    final rawUser = asMap(d['user']);
    p.userId =
        rawUser != null ? asString(rawUser['id']) : asString(d['user_id']);

    for (final a in asList(d['activities']) ?? const []) {
      final am = asMap(a);
      if (am != null) p.activities.add(AccordActivity.fromJson(am));
    }
    return p;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'user_id': userId,
      'status': status,
      'client_status': clientStatus,
      'activities': toJsonList(activities),
    };
    if (spaceId != null) d['space_id'] = spaceId;
    return d;
  }
}
