import '../../models/channel.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Channel-level routes (get, update, delete, overwrites, recipients, mute).
class ChannelsApi extends EndpointBase {
  ChannelsApi(super.rest);

  /// Fetches a channel by snowflake ID.
  Future<RestResult> fetch(String channelId) async {
    final result = await rest.makeRequest('GET', '/channels/$channelId');
    return result.deserialize(AccordChannel.fromJson);
  }

  /// Updates a channel's settings.
  Future<RestResult> update(String channelId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('PATCH', '/channels/$channelId', body: data);
    return result.deserialize(AccordChannel.fromJson);
  }

  /// Deletes or closes a channel.
  Future<RestResult> delete(String channelId) async {
    final result = await rest.makeRequest('DELETE', '/channels/$channelId');
    return result.deserialize(AccordChannel.fromJson);
  }

  /// Lists all permission overwrites for a channel.
  Future<RestResult> listOverwrites(String channelId) {
    return rest.makeRequest('GET', '/channels/$channelId/permissions');
  }

  /// Creates or updates a permission overwrite for a role or member.
  Future<RestResult> upsertOverwrite(
      String channelId, String overwriteId, Map<String, dynamic> data) {
    return rest.makeRequest(
      'PUT',
      '/channels/$channelId/permissions/$overwriteId',
      body: data,
    );
  }

  /// Deletes a permission overwrite from a channel.
  Future<RestResult> deleteOverwrite(String channelId, String overwriteId) {
    return rest.makeRequest(
      'DELETE',
      '/channels/$channelId/permissions/$overwriteId',
    );
  }

  /// Adds a user to a group DM channel.
  Future<RestResult> addRecipient(String channelId, String userId) {
    return rest.makeRequest('PUT', '/channels/$channelId/recipients/$userId');
  }

  /// Removes a user from a group DM channel.
  Future<RestResult> removeRecipient(String channelId, String userId) {
    return rest.makeRequest(
        'DELETE', '/channels/$channelId/recipients/$userId');
  }

  /// Mutes a channel or category for the current user.
  Future<RestResult> mute(String channelId) {
    return rest.makeRequest('PUT', '/channels/$channelId/mute');
  }

  /// Unmutes a channel or category for the current user.
  Future<RestResult> unmute(String channelId) {
    return rest.makeRequest('DELETE', '/channels/$channelId/mute');
  }

  /// Acknowledges (marks read) a channel up to [messageId].
  Future<RestResult> ack(String channelId, String messageId) {
    return rest.makeRequest(
      'POST',
      '/channels/$channelId/ack',
      body: {'message_id': messageId},
    );
  }
}
