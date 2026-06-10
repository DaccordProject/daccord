import '../../models/user.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Message reaction operations: add, remove, list, and clear.
class ReactionsApi extends EndpointBase {
  ReactionsApi(super.rest);

  String _encode(String emoji) => Uri.encodeComponent(emoji);

  /// Adds the current user's reaction. [emoji] is a unicode emoji or
  /// `name:id` for custom emoji.
  Future<RestResult> add(String channelId, String messageId, String emoji) {
    final e = _encode(emoji);
    return rest.makeRequest(
        'PUT', '/channels/$channelId/messages/$messageId/reactions/$e/@me');
  }

  /// Removes the current user's reaction.
  Future<RestResult> removeOwn(
      String channelId, String messageId, String emoji) {
    final e = _encode(emoji);
    return rest.makeRequest(
        'DELETE', '/channels/$channelId/messages/$messageId/reactions/$e/@me');
  }

  /// Removes another user's reaction (requires manage_messages).
  Future<RestResult> removeUser(
      String channelId, String messageId, String emoji, String userId) {
    final e = _encode(emoji);
    return rest.makeRequest('DELETE',
        '/channels/$channelId/messages/$messageId/reactions/$e/$userId');
  }

  /// Lists users who reacted with [emoji]. Supports `after`/`limit`.
  Future<RestResult> listUsers(String channelId, String messageId, String emoji,
      {Map<String, dynamic> query = const {}}) async {
    final e = _encode(emoji);
    final result = await rest.makeRequest(
      'GET',
      '/channels/$channelId/messages/$messageId/reactions/$e',
      query: query,
    );
    return result.deserializeArray(AccordUser.fromJson);
  }

  /// Removes all reactions (requires manage_messages).
  Future<RestResult> removeAll(String channelId, String messageId) {
    return rest.makeRequest(
        'DELETE', '/channels/$channelId/messages/$messageId/reactions');
  }

  /// Removes all reactions of a specific emoji (requires manage_messages).
  Future<RestResult> removeEmoji(
      String channelId, String messageId, String emoji) {
    final e = _encode(emoji);
    return rest.makeRequest(
        'DELETE', '/channels/$channelId/messages/$messageId/reactions/$e');
  }
}
