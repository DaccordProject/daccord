import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/models/accord_auth.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'voice.g.dart';

/// The local user's voice-connection state. Distinct from the per-user
/// [AccordVoiceState] cache ([VoiceStatesController]): this tracks *our* session
/// — which channel we're in, the LiveKit media state, and our self-flags.
@immutable
class VoiceConnection {
  const VoiceConnection({
    this.channelId,
    this.spaceId,
    this.sessionState = VoiceSessionState.disconnected,
    this.selfMute = false,
    this.selfDeaf = false,
    this.selfVideo = false,
    this.selfStream = false,
    this.speakingUserIds = const {},
    this.error,
    this.tick = 0,
  });

  final String? channelId;
  final String? spaceId;
  final VoiceSessionState sessionState;
  final bool selfMute;
  final bool selfDeaf;
  final bool selfVideo;

  /// Whether we're currently screen-sharing.
  final bool selfStream;
  final Set<String> speakingUserIds;

  /// Transient error message for the voice bar (auto-dismissed by the UI).
  final String? error;

  /// Bumped on every LiveKit room change (track published/subscribed, speaker
  /// changes). The video grid watches this to rebuild its tiles when the set of
  /// renderable tracks changes — the reference client's `_schedule_rebuild`.
  final int tick;

  bool get isConnected => channelId != null;

  VoiceConnection copyWith({
    String? channelId,
    String? spaceId,
    VoiceSessionState? sessionState,
    bool? selfMute,
    bool? selfDeaf,
    bool? selfVideo,
    bool? selfStream,
    Set<String>? speakingUserIds,
    String? error,
    bool clearError = false,
    int? tick,
  }) {
    return VoiceConnection(
      channelId: channelId ?? this.channelId,
      spaceId: spaceId ?? this.spaceId,
      sessionState: sessionState ?? this.sessionState,
      selfMute: selfMute ?? this.selfMute,
      selfDeaf: selfDeaf ?? this.selfDeaf,
      selfVideo: selfVideo ?? this.selfVideo,
      selfStream: selfStream ?? this.selfStream,
      speakingUserIds: speakingUserIds ?? this.speakingUserIds,
      error: clearError ? null : (error ?? this.error),
      tick: tick ?? this.tick,
    );
  }
}

/// Orchestrates voice channel join/leave and media toggles, the Dart port of
/// the reference `client_voice.gd` + the voice slice of its `AppState`. Owns a
/// single [VoiceSession] (the LiveKit transport) and pushes runtime self-state
/// to the server over the gateway via `updateVoiceState`.
@Riverpod(keepAlive: true)
class VoiceController extends _$VoiceController {
  VoiceSession? _session;

  /// The live LiveKit session, exposed so the video grid can render its room.
  /// Null whenever we're not connected.
  VoiceSession? get session => _session;

  /// The local microphone level (0–1), for the mic-activity meter.
  double get localAudioLevel => _session?.localAudioLevel ?? 0;

  /// Whether the local mic is currently registering as speaking.
  bool get localIsSpeaking => _session?.localIsSpeaking ?? false;

  @override
  VoiceConnection build() {
    // Push live audio device/volume changes to the active session so the voice
    // settings page takes effect without a reconnect.
    ref.listen(settingsControllerProvider, (prev, next) {
      final session = _session;
      if (session == null || !state.isConnected) return;
      if (prev?.audioInputDeviceId != next.audioInputDeviceId) {
        session.setAudioInputDevice(next.audioInputDeviceId);
      }
      if (prev?.audioOutputDeviceId != next.audioOutputDeviceId) {
        session.setAudioOutputDevice(next.audioOutputDeviceId);
      }
      if (prev?.outputVolume != next.outputVolume) {
        session.setOutputVolume(next.outputVolume);
      }
      if (prev?.inputVolume != next.inputVolume) {
        session.setInputVolume(next.inputVolume);
      }
    });
    ref.onDispose(() {
      _session?.dispose();
      _session = null;
    });
    return const VoiceConnection();
  }

  AccordClient? get _client => ref.read(
        accordAuthProvider
            .select((s) => s is AccordAuthLoggedIn ? s.client : null),
      );

  /// Joins the voice [channelId] in [spaceId]. Leaves any current channel
  /// first, fetches LiveKit credentials over REST, then connects the session.
  Future<void> join(String channelId, String spaceId) async {
    if (state.channelId == channelId) return;
    if (state.isConnected) await leave();

    final client = _client;
    if (client == null) {
      state = state.copyWith(error: 'No connection found');
      return;
    }

    _session ??= _buildSession();

    final result = await client.voice
        .join(channelId, selfMute: state.selfMute, selfDeaf: state.selfDeaf);
    final info = result.data;
    if (!result.ok || info is! AccordVoiceServerUpdate) {
      state = state.copyWith(
          error: result.error?.message ?? 'Failed to join voice channel');
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      await client.voice.leave(channelId);
      state = state.copyWith(
          error: 'Voice backend unavailable — server returned no credentials');
      return;
    }

    state = state.copyWith(
      channelId: channelId,
      spaceId: spaceId,
      sessionState: VoiceSessionState.connecting,
      clearError: true,
    );
    final settings = ref.read(settingsControllerProvider);
    await _session!.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
    );
    soundManager.play('voice_join');
    await _refreshVoiceStates(channelId);
  }

  /// Leaves the current voice channel and tears the session down.
  Future<void> leave() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    await _session?.disconnect();
    await _client?.voice.leave(channelId);
    soundManager.play('voice_leave');
    state = const VoiceConnection();
  }

  void toggleMute() => setMute(!state.selfMute);

  void setMute(bool muted) {
    if (!state.isConnected) return;
    _session?.setMicEnabled(!muted);
    state = state.copyWith(selfMute: muted);
    soundManager.play(muted ? 'mute' : 'unmute');
    _sendVoiceStateUpdate();
  }

  void toggleDeafen() => setDeafen(!state.selfDeaf);

  void setDeafen(bool deafened) {
    if (!state.isConnected) return;
    _session?.setDeafened(deafened);
    state = state.copyWith(selfDeaf: deafened);
    soundManager.play(deafened ? 'deafen' : 'undeafen');
    _sendVoiceStateUpdate();
  }

  Future<void> toggleVideo() async {
    if (!state.isConnected) return;
    final enable = !state.selfVideo;
    if (enable) {
      final settings = ref.read(settingsControllerProvider);
      final (width, height) = settings.videoDimensions;
      await _session?.setCameraEnabled(
        true,
        width: width,
        height: height,
        fps: settings.videoFps,
        bitrate: settings.videoBitrate,
        deviceId: settings.videoInputDeviceId,
      );
    } else {
      await _session?.setCameraEnabled(false);
    }
    state = state.copyWith(selfVideo: enable);
    _sendVoiceStateUpdate();
  }

  Future<void> toggleScreenShare() async {
    if (!state.isConnected) return;
    final enable = !state.selfStream;
    await _session?.setScreenShareEnabled(enable);
    state = state.copyWith(selfStream: enable);
    _sendVoiceStateUpdate();
  }

  /// Fresh LiveKit credentials arrived over the gateway. Reconnect the backend
  /// only when the session has actually dropped (token refresh / SFU move) so
  /// we don't churn a healthy initial connection that the join already wired.
  void handleServerUpdate(AccordVoiceServerUpdate info) {
    if (!state.isConnected || state.channelId != info.channelId) return;
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    final sessionState = _session?.state;
    final needsReconnect = sessionState == VoiceSessionState.disconnected ||
        sessionState == VoiceSessionState.failed ||
        sessionState == VoiceSessionState.reconnecting;
    if (!needsReconnect) return;
    _session?.connect(url, token,
        selfMute: state.selfMute, selfDeaf: state.selfDeaf);
  }

  /// The server removed us from voice (our gateway state's channel went null).
  void handleForcedDisconnect() {
    _session?.disconnect();
    state = const VoiceConnection();
  }

  VoiceSession _buildSession() {
    final session = VoiceSession()
      ..onChanged = _onSessionChanged
      ..onStateChanged = _onSessionStateChanged
      ..onDisconnected = _onSessionDisconnected;
    return session;
  }

  void _onSessionChanged() {
    final speaking = _session?.speakingUserIds ?? const {};
    state = state.copyWith(
      speakingUserIds:
          setEquals(speaking, state.speakingUserIds) ? null : speaking,
      tick: state.tick + 1,
    );
  }

  /// Dismisses the transient voice error (the bar auto-clears it after a few
  /// seconds; mirrors the reference's 4s error tween).
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  void _onSessionStateChanged(VoiceSessionState sessionState) {
    if (!state.isConnected) return;
    state = state.copyWith(sessionState: sessionState);
  }

  void _onSessionDisconnected({required bool intentional}) {
    // An unintentional drop just reflects the transient state; the gateway
    // voice.server_update (token refresh) drives the actual reconnect.
    if (intentional || !state.isConnected) return;
    state = state.copyWith(sessionState: VoiceSessionState.reconnecting);
  }

  Future<void> _refreshVoiceStates(String channelId) async {
    final client = _client;
    if (client == null) return;
    final result = await client.voice.getStatus(channelId);
    final data = result.data;
    if (!result.ok || data is! List<AccordVoiceState>) return;
    ref
        .read(voiceStatesControllerProvider.notifier)
        .seedChannel(channelId, data);
  }

  void _sendVoiceStateUpdate() {
    final channelId = state.channelId;
    final spaceId = state.spaceId;
    if (channelId == null || spaceId == null) return;
    _client?.updateVoiceState(
      spaceId,
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      selfVideo: state.selfVideo,
      selfStream: state.selfStream,
    );
  }
}
