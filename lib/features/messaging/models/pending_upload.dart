import 'package:accordkit/accordkit.dart';

/// One of this account's attachments that AutoMod is holding (or has finally
/// refused): which message it belongs to and where the server's scan stands.
///
/// Created from a `202 Accepted` upload response's `pending_attachments` and
/// advanced by `automod.upload_status` events / `GET /automod/uploads/{id}`.
/// The upload [id] doubles as the attachment ID once the file is published.
class PendingUpload {
  const PendingUpload({
    required this.id,
    required this.messageId,
    required this.channelId,
    this.spaceId,
    this.status = AutomodUploadStatus.pending,
    this.reason,
  });

  final String id;
  final String messageId;
  final String channelId;

  /// Null for direct-message uploads.
  final String? spaceId;

  /// One of the [AutomodUploadStatus] constants. `published` uploads are
  /// dropped from the tracker rather than stored, so this is never that.
  final String status;

  /// The decision's stated reason, once fetched via `automod.getUpload` —
  /// only ever requested for this account's own uploads.
  final String? reason;

  /// True while the server may still publish or refuse the file.
  bool get isOutstanding => AutomodUploadStatus.isOutstanding(status);

  /// True once the file has been finally refused (rejected or withdrawn).
  bool get isRefused => AutomodUploadStatus.isRefused(status);

  PendingUpload copyWith({String? status, String? reason}) => PendingUpload(
    id: id,
    messageId: messageId,
    channelId: channelId,
    spaceId: spaceId,
    status: status ?? this.status,
    reason: reason ?? this.reason,
  );

  factory PendingUpload.fromJson(Map<String, dynamic> d) => PendingUpload(
    id: asString(d['id']),
    messageId: asString(d['message_id']),
    channelId: asString(d['channel_id']),
    spaceId: asStringOrNull(d['space_id']),
    status: asString(d['status'], AutomodUploadStatus.pending),
    reason: asStringOrNull(d['reason']),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'message_id': messageId,
    'channel_id': channelId,
    if (spaceId != null) 'space_id': spaceId,
    'status': status,
    if (reason != null) 'reason': reason,
  };

  @override
  bool operator ==(Object other) =>
      other is PendingUpload &&
      other.id == id &&
      other.messageId == messageId &&
      other.channelId == channelId &&
      other.spaceId == spaceId &&
      other.status == status &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(id, messageId, channelId, status, reason);
}
