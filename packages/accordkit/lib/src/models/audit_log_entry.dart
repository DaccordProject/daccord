import '../utils/json_utils.dart';

/// A single entry in a space's audit log.
class AccordAuditLogEntry {
  String id;
  String userId;
  String actionType;
  String targetId;
  String targetType;
  String reason;
  List<dynamic> changes;
  String createdAt;

  AccordAuditLogEntry({
    this.id = '',
    this.userId = '',
    this.actionType = '',
    this.targetId = '',
    this.targetType = '',
    this.reason = '',
    List<dynamic>? changes,
    this.createdAt = '',
  }) : changes = changes ?? [];

  factory AccordAuditLogEntry.fromJson(Map<String, dynamic> d) {
    return AccordAuditLogEntry(
      id: asString(d['id']),
      userId: asString(d['user_id']),
      actionType: asString(d['action_type']),
      targetId: asString(d['target_id']),
      targetType: asString(d['target_type']),
      reason: asString(d['reason']),
      changes: asList(d['changes']) ?? [],
      createdAt: asString(d['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'action_type': actionType,
      'target_id': targetId,
      'target_type': targetType,
      'reason': reason,
      'changes': changes,
      'created_at': createdAt,
    };
  }
}
