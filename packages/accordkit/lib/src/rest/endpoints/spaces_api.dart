import '../../models/channel.dart';
import '../../models/space.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Space (guild) management routes.
class SpacesApi extends EndpointBase {
  SpacesApi(super.rest);

  /// Creates a new space.
  Future<RestResult> create(Map<String, dynamic> data) async {
    final result = await rest.makeRequest('POST', '/spaces', body: data);
    return result.deserialize(AccordSpace.fromJson);
  }

  /// Fetches a space by snowflake ID.
  Future<RestResult> fetch(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId');
    return result.deserialize(AccordSpace.fromJson);
  }

  /// Updates a space's settings.
  Future<RestResult> update(String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/spaces/$spaceId', body: data);
    return result.deserialize(AccordSpace.fromJson);
  }

  /// Permanently deletes a space (owner only).
  Future<RestResult> delete(String spaceId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId');
  }

  /// Lists all channels in a space.
  Future<RestResult> listChannels(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/channels');
    return result.deserializeArray(AccordChannel.fromJson);
  }

  /// Creates a new channel in a space.
  Future<RestResult> createChannel(
      String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/channels', body: data);
    return result.deserialize(AccordChannel.fromJson);
  }

  /// Reorders channels. [data] entries have `id` and `position` keys.
  Future<RestResult> reorderChannels(String spaceId, List<dynamic> data) {
    return rest.makeRequest('PATCH', '/spaces/$spaceId/channels', body: data);
  }

  /// Joins a public space without an invite.
  Future<RestResult> join(String spaceId) {
    return rest.makeRequest('POST', '/spaces/$spaceId/join');
  }

  /// Fetches the current anonymous (guest) viewer count for a space.
  Future<RestResult> anonymousCount(String spaceId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/anonymous-count');
  }
}
