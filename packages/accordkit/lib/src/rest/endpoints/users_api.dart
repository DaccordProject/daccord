import '../../models/accord_relationship.dart';
import '../../models/channel.dart';
import '../../models/space.dart';
import '../../models/user.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// User-related routes: the current user, lookups, DMs, relationships, and
/// GDPR data export.
class UsersApi extends EndpointBase {
  UsersApi(super.rest);

  /// Fetches the currently authenticated user.
  Future<RestResult> getMe() async {
    final result = await rest.makeRequest('GET', '/users/@me');
    return result.deserialize(AccordUser.fromJson);
  }

  /// Updates the current user's profile.
  Future<RestResult> updateMe(Map<String, dynamic> data) async {
    final result = await rest.makeRequest('PATCH', '/users/@me', body: data);
    return result.deserialize(AccordUser.fromJson);
  }

  /// Fetches a user by snowflake ID.
  Future<RestResult> fetch(String userId) async {
    final result = await rest.makeRequest('GET', '/users/$userId');
    return result.deserialize(AccordUser.fromJson);
  }

  /// Lists all spaces the current user belongs to.
  Future<RestResult> listSpaces() async {
    final result = await rest.makeRequest('GET', '/users/@me/spaces');
    return result.deserializeArray(AccordSpace.fromJson);
  }

  /// Lists all DM channels for the current user.
  Future<RestResult> listChannels() async {
    final result = await rest.makeRequest('GET', '/users/@me/channels');
    return result.deserializeArray(AccordChannel.fromJson);
  }

  /// Creates a DM channel with the specified user(s).
  Future<RestResult> createDm(Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/users/@me/channels', body: data);
    return result.deserialize(AccordChannel.fromJson);
  }

  /// Deletes the current user's account.
  Future<RestResult> deleteMe([Map<String, dynamic> data = const {}]) {
    return rest.makeRequest('DELETE', '/users/@me', body: data);
  }

  /// Lists all connections linked to the current user's account.
  Future<RestResult> listConnections() {
    return rest.makeRequest('GET', '/users/@me/connections');
  }

  /// Lists all muted channel IDs for the current user.
  Future<RestResult> listMutes() {
    return rest.makeRequest('GET', '/users/@me/mutes');
  }

  /// Lists channels with unread messages for the current user.
  Future<RestResult> listUnread() {
    return rest.makeRequest('GET', '/users/@me/read-states');
  }

  /// Returns mutual friends between the current user and [userId].
  Future<RestResult> getMutualFriends(String userId) async {
    final result =
        await rest.makeRequest('GET', '/users/$userId/mutual-friends');
    return result.deserializeArray(AccordUser.fromJson);
  }

  /// Searches for users by username or display name.
  Future<RestResult> searchUsers(String query, {int limit = 25}) async {
    final result = await rest.makeRequest(
      'GET',
      '/users/search',
      query: {'query': query, 'limit': limit},
    );
    return result.deserializeArray(AccordUser.fromJson);
  }

  /// Lists all relationships for the current user.
  Future<RestResult> listRelationships() async {
    final result = await rest.makeRequest('GET', '/users/@me/relationships');
    return result.deserializeArray(AccordRelationship.fromJson);
  }

  /// Creates or updates a relationship with another user.
  /// [data] should contain `{"type": int}` (1 = friend request, 2 = block).
  Future<RestResult> putRelationship(String userId, Map<String, dynamic> data) {
    return rest.makeRequest('PUT', '/users/@me/relationships/$userId',
        body: data);
  }

  /// Removes a relationship (unfriend, decline, cancel, or unblock).
  Future<RestResult> deleteRelationship(String userId) {
    return rest.makeRequest('DELETE', '/users/@me/relationships/$userId');
  }

  /// Requests a full export of the current user's personal data (GDPR).
  Future<RestResult> requestDataExport() {
    return rest.makeRequest('GET', '/users/@me/data-export');
  }
}
