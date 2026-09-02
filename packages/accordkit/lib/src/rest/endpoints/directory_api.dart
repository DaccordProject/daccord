import '../endpoint_base.dart';
import '../rest_result.dart';

/// Master-server directory routes. Unlike other endpoint groups this targets
/// the master server (not an instance) and requires no authentication.
///
/// Paths here are bare, exactly like every other endpoint group: the `/api/v1`
/// prefix belongs to the `AccordRest` base URL, never to the path. A caller
/// pointing this at a master server therefore builds its rest client with
/// `master + AccordConfig.apiBasePath`, the same shape `AccordClient` gives
/// `client.directory` for an instance.
class DirectoryApi extends EndpointBase {
  DirectoryApi(super.rest);

  /// Browses the public space directory with optional [query], [tag], and
  /// [page]. [RestResult.data] is the raw response map.
  Future<RestResult> browse({
    String query = '',
    String tag = '',
    int page = 1,
  }) {
    final params = <String, dynamic>{};
    if (query.isNotEmpty) params['q'] = query;
    if (tag.isNotEmpty) params['tag'] = tag;
    if (page > 1) params['page'] = page;
    return rest.makeRequest('GET', '/directory', query: params);
  }

  /// Fetches detail for a specific space listing in the directory.
  Future<RestResult> getSpace(String spaceId) {
    return rest.makeRequest('GET', '/directory/$spaceId');
  }
}
