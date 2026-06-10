import '../../models/role.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Role management within a space: list, create, update, delete, reorder.
class RolesApi extends EndpointBase {
  RolesApi(super.rest);

  /// Lists all roles in a space.
  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/roles');
    return result.deserializeArray(AccordRole.fromJson);
  }

  /// Creates a new role.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/roles', body: data);
    return result.deserialize(AccordRole.fromJson);
  }

  /// Updates an existing role.
  Future<RestResult> update(
      String spaceId, String roleId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/roles/$roleId', body: data);
    return result.deserialize(AccordRole.fromJson);
  }

  /// Permanently deletes a role.
  Future<RestResult> delete(String spaceId, String roleId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/roles/$roleId');
  }

  /// Reorders roles. [data] entries have `id` and `position` keys.
  Future<RestResult> reorder(String spaceId, List<dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/spaces/$spaceId/roles', body: data);
    return result.deserializeArray(AccordRole.fromJson);
  }
}
