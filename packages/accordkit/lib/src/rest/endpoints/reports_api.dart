import '../endpoint_base.dart';
import '../rest_result.dart';

/// Report management within a space: create, list, fetch, resolve.
class ReportsApi extends EndpointBase {
  ReportsApi(super.rest);

  /// Creates a report. [data] should include `target_type`, `target_id`,
  /// `category`, and optionally `channel_id`/`description`.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/spaces/$spaceId/reports', body: data);
  }

  /// Lists reports. Supports `status`/`limit`/`before`.
  Future<RestResult> list(String spaceId,
      {Map<String, dynamic> query = const {}}) {
    return rest.makeRequest('GET', '/spaces/$spaceId/reports', query: query);
  }

  /// Fetches a single report by ID.
  Future<RestResult> fetch(String spaceId, String reportId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/reports/$reportId');
  }

  /// Resolves a report. [data] should include `status` and optionally
  /// `action_taken`.
  Future<RestResult> resolve(
      String spaceId, String reportId, Map<String, dynamic> data) {
    return rest.makeRequest('PATCH', '/spaces/$spaceId/reports/$reportId',
        body: data);
  }
}
