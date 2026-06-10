import '../utils/json_utils.dart';
import 'voice_state.dart';

/// Voice backend connection info returned by the REST join endpoint or the
/// gateway `voice.server_update` event. Carries the backend type and the
/// credentials needed to connect to LiveKit or the custom SFU.
class AccordVoiceServerUpdate {
  String spaceId;
  String channelId;
  String backend;
  String? livekitUrl;
  String? token;
  String? sfuEndpoint;

  /// Present in the REST join response, absent in the gateway event.
  AccordVoiceState? voiceState;

  AccordVoiceServerUpdate({
    this.spaceId = '',
    this.channelId = '',
    this.backend = '',
    this.livekitUrl,
    this.token,
    this.sfuEndpoint,
    this.voiceState,
  });

  factory AccordVoiceServerUpdate.fromJson(Map<String, dynamic> d) {
    final v = AccordVoiceServerUpdate(
      spaceId: asString(d['space_id']),
      channelId: asString(d['channel_id']),
      backend: asString(d['backend']),
      // REST uses livekit_url / sfu_endpoint; gateway uses url / endpoint.
      livekitUrl: asStringOrNull(d['livekit_url'] ?? d['url']),
      token: asStringOrNull(d['token']),
      sfuEndpoint: asStringOrNull(d['sfu_endpoint'] ?? d['endpoint']),
    );
    final rawVs = asMap(d['voice_state']);
    if (rawVs != null) v.voiceState = AccordVoiceState.fromJson(rawVs);
    return v;
  }

  Map<String, dynamic> toJson() {
    final d = <String, dynamic>{
      'space_id': spaceId,
      'channel_id': channelId,
      'backend': backend,
    };
    if (livekitUrl != null) d['livekit_url'] = livekitUrl;
    if (token != null) d['token'] = token;
    if (sfuEndpoint != null) d['sfu_endpoint'] = sfuEndpoint;
    if (voiceState != null) d['voice_state'] = voiceState!.toJson();
    return d;
  }
}
