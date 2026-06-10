import '../../models/member.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Space member management: list, search, fetch, update, kick, roles, leave.
class MembersApi extends EndpointBase {
  MembersApi(super.rest);

  /// Lists members of a space. Supports `limit`/`after`.
  Future<RestResult> list(String spaceId,
      {Map<String, dynamic> query = const {}}) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/members', query: query);
    return result.deserializeArray(AccordMember.fromJson);
  }

  /// Searches members by username or nickname.
  Future<RestResult> search(String spaceId, String queryStr,
      {Map<String, dynamic> query = const {}}) async {
    final q = Map<String, dynamic>.from(query)..['query'] = queryStr;
    final result = await rest
        .makeRequest('GET', '/spaces/$spaceId/members/search', query: q);
    return result.deserializeArray(AccordMember.fromJson);
  }

  /// Fetches a single member by user ID.
  Future<RestResult> fetch(String spaceId, String userId) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/members/$userId');
    return result.deserialize(AccordMember.fromJson);
  }

  /// Updates a member (nickname, roles, mute, deaf, etc.).
  Future<RestResult> update(
      String spaceId, String userId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/members/$userId', body: data);
    return result.deserialize(AccordMember.fromJson);
  }

  /// Removes a member from a space (kick).
  Future<RestResult> kick(String spaceId, String userId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/members/$userId');
  }

  /// Updates the current bot's own member profile in a space.
  Future<RestResult> updateMe(String spaceId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/members/@me', body: data);
    return result.deserialize(AccordMember.fromJson);
  }

  /// Leaves a space. When [deleteData] is true, the user's per-space data is
  /// also erased (GDPR).
  Future<RestResult> leaveMe(String spaceId, {bool deleteData = false}) {
    final query = <String, dynamic>{};
    if (deleteData) query['delete_data'] = 'true';
    return rest.makeRequest('DELETE', '/spaces/$spaceId/members/@me',
        query: query);
  }

  /// Adds a role to a member.
  Future<RestResult> addRole(String spaceId, String userId, String roleId) {
    return rest.makeRequest(
        'PUT', '/spaces/$spaceId/members/$userId/roles/$roleId');
  }

  /// Removes a role from a member.
  Future<RestResult> removeRole(String spaceId, String userId, String roleId) {
    return rest.makeRequest(
        'DELETE', '/spaces/$spaceId/members/$userId/roles/$roleId');
  }
}
