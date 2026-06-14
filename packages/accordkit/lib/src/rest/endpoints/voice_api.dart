import '../../models/voice_server_update.dart';
import '../../models/voice_state.dart';
import '../endpoint_base.dart';
import '../rest_result.dart';

/// Voice routes: backend info, join/leave, regions, and channel status.
class VoiceApi extends EndpointBase {
  VoiceApi(super.rest);

  /// Returns the server's voice backend configuration.
  Future<RestResult> getInfo() {
    return rest.makeRequest('GET', '/voice/info');
  }

  /// Joins a voice channel. On success [RestResult.data] is an
  /// [AccordVoiceServerUpdate] with backend connection details.
  Future<RestResult> join(String channelId,
      {bool selfMute = false, bool selfDeaf = false}) async {
    final result = await rest.makeRequest(
      'POST',
      '/channels/$channelId/voice/join',
      body: {'self_mute': selfMute, 'self_deaf': selfDeaf},
    );
    return result.deserialize(AccordVoiceServerUpdate.fromJson);
  }

  /// Leaves the current voice channel.
  Future<RestResult> leave(String channelId) {
    return rest.makeRequest('DELETE', '/channels/$channelId/voice/leave');
  }

  /// Starts ringing the other participant(s) of a DM/group-DM [channelId] with
  /// an incoming-call notification. The caller is expected to have already
  /// joined voice (or to join right after). [metadata] is echoed to recipients
  /// in the `call.ring` event. DM channels only.
  Future<RestResult> ring(String channelId,
      {Map<String, dynamic>? metadata}) {
    return rest.makeRequest(
      'POST',
      '/channels/$channelId/call/ring',
      body: {if (metadata != null) 'metadata': metadata},
    );
  }

  /// Declines an incoming DM call, broadcasting `call.decline` to participants.
  Future<RestResult> declineCall(String channelId) {
    return rest.makeRequest('POST', '/channels/$channelId/call/decline');
  }

  /// Cancels an outgoing DM call before the callee answers, broadcasting
  /// `call.cancel` to participants.
  Future<RestResult> cancelCall(String channelId) {
    return rest.makeRequest('POST', '/channels/$channelId/call/cancel');
  }

  /// Lists available voice regions for a space.
  Future<RestResult> listRegions(String spaceId) {
    return rest.makeRequest('GET', '/spaces/$spaceId/voice-regions');
  }

  /// Fetches the current voice status for a channel. On success
  /// [RestResult.data] is a `List<AccordVoiceState>`.
  Future<RestResult> getStatus(String channelId) async {
    final result =
        await rest.makeRequest('GET', '/channels/$channelId/voice-status');
    final d = result.data;
    if (result.ok && d is List) {
      result.data = [
        for (final item in d)
          if (item is Map<String, dynamic>) AccordVoiceState.fromJson(item),
      ];
    }
    return result;
  }
}
