import '../../models/emoji.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Custom emoji management within a space.
class EmojisApi extends EndpointBase {
  EmojisApi(super.rest);

  /// Lists all custom emojis in a space.
  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/emojis');
    return result.deserializeArray(AccordEmoji.fromJson);
  }

  /// Fetches a single emoji by ID.
  Future<RestResult> fetch(String spaceId, String emojiId) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/emojis/$emojiId');
    return result.deserialize(AccordEmoji.fromJson);
  }

  /// Creates an emoji. [data] should include `name` and `image` (data URI),
  /// optionally `roles`.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) async {
    final result =
        await rest.makeRequest('POST', '/spaces/$spaceId/emojis', body: data);
    return result.deserialize(AccordEmoji.fromJson);
  }

  /// Updates an emoji's name or role restrictions.
  Future<RestResult> update(
      String spaceId, String emojiId, Map<String, dynamic> data) async {
    final result = await rest
        .makeRequest('PATCH', '/spaces/$spaceId/emojis/$emojiId', body: data);
    return result.deserialize(AccordEmoji.fromJson);
  }

  /// Deletes an emoji from a space.
  Future<RestResult> delete(String spaceId, String emojiId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/emojis/$emojiId');
  }
}
