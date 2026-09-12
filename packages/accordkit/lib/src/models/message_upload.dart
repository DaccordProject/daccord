import 'message.dart';

/// The outcome of a successful multipart message upload
/// (`MessagesApi.createWithAttachments`): the created [message] plus the IDs
/// of any attachments the server is still holding for AutoMod scanning.
///
/// An AutoMod-enabled server answers `202 Accepted` with the message text
/// published immediately and the held attachments listed in
/// [pendingAttachmentIds]; their bytes and URLs stay private until a later
/// `automod.upload_status` / `message.update` releases them. A server that
/// published everything at once (or predates AutoMod) answers `200` with an
/// empty list, so a client can treat both uniformly: exactly one message was
/// created, and [message] is it.
class AccordMessageUpload {
  final AccordMessage message;

  /// Upload IDs awaiting AutoMod. Each is also the attachment ID that upload
  /// gets once published.
  final List<String> pendingAttachmentIds;

  /// The HTTP status the server answered with — 200 or 202.
  final int statusCode;

  const AccordMessageUpload({
    required this.message,
    this.pendingAttachmentIds = const [],
    this.statusCode = 200,
  });

  /// Whether any attachment is still being held (a 202, or a server that
  /// listed pending IDs on a 200).
  bool get hasPendingAttachments => pendingAttachmentIds.isNotEmpty;
}
