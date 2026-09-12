import '../../models/automod_upload.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// AutoMod APIs. Moderator/configuration methods require server authorization.
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

  String _scope(String scope) => '/automod/${Uri.encodeComponent(scope)}';
  Future<RestResult> getPolicy(String scope) =>
      rest.makeRequest('GET', '${_scope(scope)}/policy');
  Future<RestResult> setPolicy(String scope, Map<String, dynamic> policy) =>
      rest.makeRequest('PUT', '${_scope(scope)}/policy',
          body: policy, retryOnRateLimit: false);
  Future<RestResult> resetPolicy(String scope) =>
      rest.makeRequest('DELETE', '${_scope(scope)}/policy',
          retryOnRateLimit: false);
  Future<RestResult> health() => rest.makeRequest('GET', '/automod/health');
  Future<RestResult> listUploads(String scope,
          {String? status, String? before}) =>
      rest.makeRequest('GET', '${_scope(scope)}/uploads', query: {
        if (status != null) 'status': status,
        if (before != null) 'before': before,
      });
  Future<RestResult> review(String id, String action, String reason) =>
      rest.makeRequest('PATCH', '/automod/uploads/${Uri.encodeComponent(id)}',
          body: {'action': action, 'reason': reason}, retryOnRateLimit: false);
  Future<RestResult> getContent(String id) =>
      rest.makeRawRequest('/automod/uploads/${Uri.encodeComponent(id)}/content',
          maxBytes: 64 * 1024 * 1024);
  Future<RestResult> blockAttachment(String scope, String id, String reason) =>
      rest.makeRequest('POST',
          '${_scope(scope)}/attachments/${Uri.encodeComponent(id)}/block',
          body: {'reason': reason}, retryOnRateLimit: false);
  Future<RestResult> listHashes(String scope, {String? before}) =>
      rest.makeRequest('GET', '${_scope(scope)}/hashes',
          query: {if (before != null) 'before': before});
  Future<RestResult> blockHash(String scope, String hash, String reason) =>
      rest.makeRequest(
          'PUT', '${_scope(scope)}/hashes/${Uri.encodeComponent(hash)}',
          body: {'reason': reason}, retryOnRateLimit: false);
  Future<RestResult> unblockHash(String scope, String hash) => rest.makeRequest(
      'DELETE', '${_scope(scope)}/hashes/${Uri.encodeComponent(hash)}',
      retryOnRateLimit: false);
  Future<RestResult> events(String scope, {String? before}) =>
      rest.makeRequest('GET', '${_scope(scope)}/events',
          query: {if (before != null) 'before': before});
}
