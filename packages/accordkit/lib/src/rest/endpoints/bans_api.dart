import '../endpoint_base.dart';
import '../rest_result.dart';

/// Ban management within a space: list, fetch, create, remove.
class BansApi extends EndpointBase {
  BansApi(super.rest);

  /// Lists bans in a space. Supports `limit`/`before`/`after`.
  Future<RestResult> list(String spaceId,
      {Map<String, dynamic> query = const {}}) {
    return rest.makeRequest('GET', '/spaces/$spaceId/bans', query: query);
  }

  /// Fetches a single ban entry.
  Future<RestResult> fetch(String spaceId, String userId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/bans/$userId');
  }

  /// Creates a ban. [data] may include `delete_message_seconds`.
  Future<RestResult> create(String spaceId, String userId,
      {Map<String, dynamic> data = const {}}) {
    return rest.makeRequest('PUT', '/spaces/$spaceId/bans/$userId', body: data);
  }

  /// Removes a ban (unban).
  Future<RestResult> remove(String spaceId, String userId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/bans/$userId');
  }
}
