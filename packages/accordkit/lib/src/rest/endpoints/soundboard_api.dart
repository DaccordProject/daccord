import '../../models/sound.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Soundboard management within a space: list, fetch, create, update, delete,
/// and trigger playback.
class SoundboardApi extends EndpointBase {
  SoundboardApi(super.rest);

  /// Lists all sounds in a space's soundboard.
  Future<RestResult> list(String spaceId) async {
    final result = await rest.makeRequest('GET', '/spaces/$spaceId/soundboard');
    return result.deserializeArray(AccordSound.fromJson);
  }

  /// Fetches a single sound by ID.
  Future<RestResult> fetch(String spaceId, String soundId) async {
    final result =
        await rest.makeRequest('GET', '/spaces/$spaceId/soundboard/$soundId');
    return result.deserialize(AccordSound.fromJson);
  }

  /// Creates a sound. [data] should include `name` and `audio` (data URI),
  /// optionally `volume`.
  Future<RestResult> create(String spaceId, Map<String, dynamic> data) async {
    final result = await rest.makeRequest('POST', '/spaces/$spaceId/soundboard',
        body: data);
    return result.deserialize(AccordSound.fromJson);
  }

  /// Updates a sound's name or volume.
  Future<RestResult> update(
      String spaceId, String soundId, Map<String, dynamic> data) async {
    final result = await rest.makeRequest(
        'PATCH', '/spaces/$spaceId/soundboard/$soundId',
        body: data);
    return result.deserialize(AccordSound.fromJson);
  }

  /// Deletes a sound.
  Future<RestResult> delete(String spaceId, String soundId) {
    return rest.makeRequest('DELETE', '/spaces/$spaceId/soundboard/$soundId');
  }

  /// Triggers playback of a sound.
  Future<RestResult> play(String spaceId, String soundId) {
    return rest.makeRequest(
        'POST', '/spaces/$spaceId/soundboard/$soundId/play');
  }
}
