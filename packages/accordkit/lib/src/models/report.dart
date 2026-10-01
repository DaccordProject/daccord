import '../utils/json_utils.dart';

/// A moderation report filed against a message or user in a space.
class AccordReport {
  String id;
  String spaceId;
  String reporterId;
  String targetType;
  String targetId;
  String? channelId;
  String category;
  String? description;
  String status;
  String? actionedBy;
  String? actionTaken;
  String createdAt;
  String? resolvedAt;

  final String? _reportedUserId;

  AccordReport({
    this.id = '',
    this.spaceId = '',
    this.reporterId = '',
    this.targetType = '',
    this.targetId = '',
    this.channelId,
    this.category = '',
    this.description,
    this.status = '',
    this.actionedBy,
    this.actionTaken,
    this.createdAt = '',
    this.resolvedAt,
    String? reportedUserId,
  }) : _reportedUserId = reportedUserId;

  factory AccordReport.fromJson(Map<String, dynamic> d) {
    String? reportedUserId;
    for (final key in ['reported_user_id', 'target_user_id', 'author_id']) {
      final value = asStringOrNull(d[key]);
      if (value != null && value.isNotEmpty) {
        reportedUserId = value;
        break;
      }
    }

    return AccordReport(
      id: asString(d['id']),
      spaceId: asString(d['space_id'] ?? d['guild_id']),
      reporterId: asString(d['reporter_id']),
      targetType: asString(d['target_type']),
      targetId: asString(d['target_id']),
      channelId: asStringOrNull(d['channel_id']),
      category: asString(d['category']),
      description: asStringOrNull(d['description']),
      status: asString(d['status']),
      actionedBy: asStringOrNull(d['actioned_by']),
      actionTaken: asStringOrNull(d['action_taken']),
      createdAt: asString(d['created_at']),
      resolvedAt: asStringOrNull(d['resolved_at']),
      reportedUserId: reportedUserId,
    );
  }

  /// The user affected by member moderation actions, when the report identifies
  /// one directly or through a legacy report payload.
  String? get reportedUserId {
    if ((targetType == 'user' || targetType == 'member') &&
        targetId.isNotEmpty) {
      return targetId;
    }
    return _reportedUserId;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'id': id,
      'space_id': spaceId,
      'reporter_id': reporterId,
      'target_type': targetType,
      'target_id': targetId,
      'category': category,
      'status': status,
      'created_at': createdAt,
    };
    if (channelId != null) d['channel_id'] = channelId;
    if (description != null) d['description'] = description;
    if (actionedBy != null) d['actioned_by'] = actionedBy;
    if (actionTaken != null) d['action_taken'] = actionTaken;
    if (resolvedAt != null) d['resolved_at'] = resolvedAt;
    if (_reportedUserId != null) d['reported_user_id'] = _reportedUserId;
    return d;
  }
}
