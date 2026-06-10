import '../endpoint_base.dart';
import '../rest_result.dart';

/// Audit log routes for a space.
class AuditLogsApi extends EndpointBase {
  AuditLogsApi(super.rest);

  /// Lists audit log entries. Supports `limit`/`before`/`user_id`/
  /// `action_type`.
  Future<RestResult> list(String spaceId,
      {Map<String, dynamic> query = const {}}) {
    return rest.makeRequest('GET', '/spaces/$spaceId/audit-log', query: query);
  }
}
