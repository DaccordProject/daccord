import 'dart:async';

import '../gateway/gateway_socket.dart';
import '../models/voice_server_update.dart';
import '../models/voice_state.dart';
import '../rest/endpoints/voice_api.dart';
import '../rest/rest_result.dart';

/// High-level voice helper that ties the voice REST endpoints to gateway voice
/// events, tracking the currently-joined channel and surfacing connect,
/// disconnect, and error events as streams.
class VoiceManager {
  final VoiceApi _voiceApi;
  String _currentChannelId = '';
  AccordVoiceState? _currentVoiceState;

  late final StreamSubscription<AccordVoiceState> _stateSub;
  late final StreamSubscription<AccordVoiceServerUpdate> _serverSub;

  final _connected = StreamController<AccordVoiceServerUpdate>.broadcast();
  final _disconnected = StreamController<String>.broadcast();
  final _stateChanged = StreamController<AccordVoiceState>.broadcast();
  final _serverUpdated = StreamController<AccordVoiceServerUpdate>.broadcast();
  final _error = StreamController<String>.broadcast();

  /// Fires when a voice channel has been joined.
  Stream<AccordVoiceServerUpdate> get onVoiceConnected => _connected.stream;

  /// Fires with the channel ID when voice is left or force-disconnected.
  Stream<String> get onVoiceDisconnected => _disconnected.stream;

  /// Fires on any voice state update relayed by the gateway.
  Stream<AccordVoiceState> get onVoiceStateChanged => _stateChanged.stream;

  /// Fires on a voice server update relayed by the gateway.
  Stream<AccordVoiceServerUpdate> get onVoiceServerUpdated =>
      _serverUpdated.stream;

  /// Fires with a message when a voice operation fails.
  Stream<String> get onVoiceError => _error.stream;

  VoiceManager(this._voiceApi, GatewaySocket gateway) {
    _stateSub = gateway.onVoiceStateUpdate.listen(_onVoiceStateUpdate);
    _serverSub = gateway.onVoiceServerUpdate.listen(_onVoiceServerUpdate);
  }

  /// Joins [channelId]. On success emits [onVoiceConnected]; on failure emits
  /// [onVoiceError]. Returns the underlying [RestResult].
  Future<RestResult> join(String channelId,
      {bool selfMute = false, bool selfDeaf = false}) async {
    final result =
        await _voiceApi.join(channelId, selfMute: selfMute, selfDeaf: selfDeaf);
    final data = result.data;
    if (result.ok && data is AccordVoiceServerUpdate) {
      _currentChannelId = channelId;
      _currentVoiceState = data.voiceState;
      _connected.add(data);
    } else {
      _error.add(result.error?.message ?? 'Failed to join voice channel');
    }
    return result;
  }

  /// Leaves the current voice channel, if any.
  Future<RestResult> leave() async {
    final channelId = _currentChannelId;
    if (channelId.isEmpty) {
      return RestResult.failure(0, null);
    }
    final result = await _voiceApi.leave(channelId);
    if (result.ok) {
      _currentChannelId = '';
      _currentVoiceState = null;
      _disconnected.add(channelId);
    }
    return result;
  }

  /// Whether currently connected to a voice channel.
  bool isConnectedToVoice() => _currentChannelId.isNotEmpty;

  /// The current voice channel ID, or empty when not connected.
  String getCurrentChannel() => _currentChannelId;

  /// The current voice state, or null when not connected.
  AccordVoiceState? getCurrentVoiceState() => _currentVoiceState;

  /// Cancels gateway subscriptions and closes streams.
  Future<void> dispose() async {
    await _stateSub.cancel();
    await _serverSub.cancel();
    await _connected.close();
    await _disconnected.close();
    await _stateChanged.close();
    await _serverUpdated.close();
    await _error.close();
  }

  void _onVoiceStateUpdate(AccordVoiceState state) {
    _stateChanged.add(state);
    // Detect a forced disconnection: our user's channel_id became null.
    final current = _currentVoiceState;
    if (current != null && state.userId == current.userId) {
      _currentVoiceState = state;
      if (state.channelId == null && _currentChannelId.isNotEmpty) {
        final oldChannel = _currentChannelId;
        _currentChannelId = '';
        _currentVoiceState = null;
        _disconnected.add(oldChannel);
      }
    }
  }

  void _onVoiceServerUpdate(AccordVoiceServerUpdate info) {
    _serverUpdated.add(info);
  }
}
