import '../utils/json_utils.dart';

/// The lifecycle states of an attachment held by AutoMod. The server reports
/// them as bare strings; these constants are the vocabulary.
abstract final class AutomodUploadStatus {
  /// Queued for scanning (or waiting on a scanner/retry).
  static const String pending = 'pending';

  /// Withheld for a human decision.
  static const String quarantined = 'quarantined';

  /// Released: the attachment now appears on the message.
  static const String published = 'published';

  /// Rejected for now; a moderator may release it before retention expires.
  static const String rejected = 'rejected';

  /// Withdrawn after publication, or expired from the held queue.
  static const String removed = 'removed';

  /// True while the server may still change its mind: the attachment is
  /// not published or permanently removed.
  static bool isOutstanding(String status) =>
      status == pending || status == quarantined || status == rejected;

  /// True when the attachment currently has a refusal/removal decision.
  static bool isRefused(String status) =>
      status == rejected || status == removed;
}

/// The IDs-and-status payload of the `automod.upload_status` (uploader) and
/// `automod.upload_update` (moderator) gateway events. Carries no reason or
/// rule — fetch those via `AutomodApi.getUpload`.
class AccordAutomodUploadStatus {
  /// The upload ID — also the attachment ID once published.
  String id;
  String messageId;
  String channelId;

  /// Null for direct-message uploads.
  String? spaceId;

  /// One of the [AutomodUploadStatus] constants.
  String status;

  AccordAutomodUploadStatus({
    this.id = '',
    this.messageId = '',
    this.channelId = '',
    this.spaceId,
    this.status = AutomodUploadStatus.pending,
  });

  factory AccordAutomodUploadStatus.fromJson(Map<String, dynamic> d) {
    return AccordAutomodUploadStatus(
      id: asString(d['id'] ?? d['upload_id']),
      messageId: asString(d['message_id']),
      channelId: asString(d['channel_id']),
      spaceId: asStringOrNull(d['space_id']),
      status: asString(d['status'], AutomodUploadStatus.pending),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'message_id': messageId,
        'channel_id': channelId,
        if (spaceId != null) 'space_id': spaceId,
        'status': status,
      };
}

/// The authorized view of one held upload from `GET /automod/uploads/{id}`:
/// its status plus the decision's reason and matched rule (which the gateway
/// events deliberately omit). Served to the uploader and to moderators; the
/// file's bytes are never included.
class AccordAutomodUpload {
  String id;
  String messageId;

  /// One of the [AutomodUploadStatus] constants.
  String status;

  /// The moderator's or rule's stated reason, when the decision has one.
  String? reason;

  /// The policy rule that decided the upload, when one did.
  String? ruleId;

  /// Unix seconds at which a held original is discarded, when known.
  int? expiresAt;

  AccordAutomodUpload({
    this.id = '',
    this.messageId = '',
    this.status = AutomodUploadStatus.pending,
    this.reason,
    this.ruleId,
    this.expiresAt,
  });

  factory AccordAutomodUpload.fromJson(Map<String, dynamic> d) {
    final expires = d['expires_at'];
    return AccordAutomodUpload(
      id: asString(d['id']),
      messageId: asString(d['message_id']),
      status: asString(d['status'], AutomodUploadStatus.pending),
      reason: _nonEmpty(d['reason']),
      ruleId: _nonEmpty(d['rule_id'] ?? d['rule']),
      expiresAt: expires == null ? null : asInt(expires),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'message_id': messageId,
        'status': status,
        if (reason != null) 'reason': reason,
        if (ruleId != null) 'rule_id': ruleId,
        if (expiresAt != null) 'expires_at': expiresAt,
      };

  static String? _nonEmpty(Object? value) {
    final s = asStringOrNull(value);
    return s == null || s.isEmpty ? null : s;
  }
}
