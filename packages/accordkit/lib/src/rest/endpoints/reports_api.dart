import '../../models/report.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Report management within a space: create, list, fetch, resolve.
class ReportsApi extends EndpointBase {
  ReportsApi(super.rest);

  /// Lists the report categories this server accepts, as `{value, label}`
  /// entries in the order clients should offer them. Unauthenticated.
  Future<RestResult> categories() {
    return rest.makeRequest('GET', '/reports/categories');
  }

  /// Creates a report. [data] should include `target_type`, `target_id`,
  /// `category`, and optionally `channel_id`/`description`.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) {
    return rest
        .makeRequest('POST', '/spaces/$spaceId/reports', body: data)
        .then((r) => r.deserialize(AccordReport.fromJson));
  }

  /// Creates a report that isn't scoped to a space — a direct message, or a
  /// user reported from outside any space — by posting to the account-level
  /// `/reports` collection. [data] takes the same shape as [create].
  ///
  /// Not every server implements this route: an instance that predates it
  /// answers `404`/`405`, which callers should treat as "this server takes
  /// space reports only" rather than as a failed report. [reportRouteMissing]
  /// recognises those statuses.
  Future<RestResult> createDirect(Map<String, dynamic> data) {
    return rest
        .makeRequest('POST', '/reports', body: data)
        .then((r) => r.deserialize(AccordReport.fromJson));
  }

  /// Whether [result] failed because the server has no such report route,
  /// rather than because the report itself was rejected.
  static bool reportRouteMissing(RestResult result) =>
      !result.ok &&
      (result.statusCode == 404 ||
          result.statusCode == 405 ||
          result.statusCode == 501);

  /// Lists reports. Supports `status`/`limit`/`before`.
  Future<RestResult> list(String spaceId,
      {Map<String, dynamic> query = const {}}) {
    return rest
        .makeRequest('GET', '/spaces/$spaceId/reports', query: query)
        .then(_deserializeReportList);
  }

  /// Fetches a single report by ID.
  Future<RestResult> fetch(String spaceId, String reportId) {
    return rest
        .makeRequest('GET', '/spaces/$spaceId/reports/$reportId')
        .then((r) => r.deserialize(AccordReport.fromJson));
  }

  /// Resolves a report. [data] should include `status` and optionally
  /// `action_taken`.
  Future<RestResult> resolve(
      String spaceId, String reportId, Map<String, dynamic> data) {
    return rest
        .makeRequest('PATCH', '/spaces/$spaceId/reports/$reportId', body: data)
        .then((r) => r.deserialize(AccordReport.fromJson));
  }

  RestResult _deserializeReportList(RestResult result) {
    if (!result.ok) return result;
    final data = result.data;
    final raw = data is List
        ? data
        : data is Map && data['reports'] is List
            ? data['reports'] as List
            : null;
    if (raw != null) {
      result.data = [
        for (final item in raw)
          if (item is Map<String, dynamic>)
            AccordReport.fromJson(item)
          else if (item is Map)
            AccordReport.fromJson(item.cast<String, dynamic>()),
      ];
    }
    return result;
  }
}
