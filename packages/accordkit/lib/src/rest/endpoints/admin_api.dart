import '../../models/space.dart';
import '../../models/user.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Instance-level admin routes (`/admin/*`).
class AdminApi extends EndpointBase {
  AdminApi(super.rest);

  /// Lists all spaces on the instance (admin view).
  Future<RestResult> listSpaces({Map<String, dynamic> query = const {}}) async {
    final result = await rest.makeRequest('GET', '/admin/spaces', query: query);
    return result.deserializeArray(AccordSpace.fromJson);
  }

  /// Updates a space via the admin endpoint (supports owner transfer).
  Future<RestResult> updateSpace(
      String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/admin/spaces/$spaceId', body: data);
    return result.deserialize(AccordSpace.fromJson);
  }

  /// Lists all users on the instance, paginated.
  Future<RestResult> listUsers({Map<String, dynamic> query = const {}}) async {
    final result = await rest.makeRequest('GET', '/admin/users', query: query);
    return result.deserializeArray(AccordUser.fromJson);
  }

  /// Updates a user via the admin endpoint (toggle is_admin, disable, etc.).
  Future<RestResult> updateUser(
      String userId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/admin/users/$userId', body: data);
    return result.deserialize(AccordUser.fromJson);
  }

  /// Deletes a user from the instance (cascades).
  Future<RestResult> deleteUser(String userId) {
    return rest.makeRequest('DELETE', '/admin/users/$userId');
  }

  /// Fetches server-wide settings.
  Future<RestResult> getSettings() {
    return rest.makeRequest('GET', '/admin/settings');
  }

  /// Updates server-wide settings.
  Future<RestResult> updateSettings(Map<String, dynamic> data) {
    return rest.makeRequest('PATCH', '/admin/settings', body: data);
  }

  /// Resets a user's password. [data] needs `new_password` (8–128 chars).
  Future<RestResult> resetUserPassword(
      String userId, Map<String, dynamic> data) {
    return rest.makeRequest('POST', '/admin/users/$userId/reset-password',
        body: data);
  }
}
