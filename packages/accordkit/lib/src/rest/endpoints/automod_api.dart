import '../../models/automod_upload.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// AutoMod attachment moderation: the uploader-facing status lookup.
///
/// The moderator queue, review, content download, policy and hash-denylist
/// routes are deliberately not wrapped here — an ordinary sender must never
/// call them, and the client's moderation UI is separate work.
class AutomodApi extends EndpointBase {
  AutomodApi(super.rest);

  /// Fetches the status, reason and matched rule of one held upload. Served to
  /// the uploader and to moderators of the owning space; never returns the
  /// file itself. On success [RestResult.data] is an [AccordAutomodUpload].
  Future<RestResult> getUpload(String uploadId) async {
    final result = await rest.makeRequest(
      'GET',
      '/automod/uploads/${Uri.encodeComponent(uploadId)}',
    );
    return result.deserialize(AccordAutomodUpload.fromJson);
  }
}
