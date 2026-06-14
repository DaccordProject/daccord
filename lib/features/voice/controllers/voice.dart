import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/notifications/controllers/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:flutter/foundation.dart';
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
    this.serverKey,
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

  /// The connection (`userId@baseUrl`) the voice session belongs to. Voice is a
  /// single global session pinned to the server we joined on — *not* whichever
  /// server is currently driving the panes. Every voice REST/gateway call routes
  /// through this key's client so switching the active server mid-call doesn't
  /// send our leave/state updates to the wrong server (the reference's
  /// `_client_for_space`).
  final String? serverKey;
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
    String? serverKey,
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
      serverKey: serverKey ?? this.serverKey,
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

  /// The client for the connection our voice session is pinned to. Resolved by
  /// [VoiceConnection.serverKey] rather than the active connection so a call
  /// survives the user switching the active server (the reference routes voice
  /// REST/gateway through `_client_for_space`, never the "current" client).
  AccordClient? get _client {
    final key = state.serverKey;
    if (key == null) return null;
    return ref.read(accordAuthProvider.notifier).clientForKey(key);
  }

  /// One-shot guard so a dropped connection triggers at most one proactive
  /// credential-refresh reconnect; reset whenever we (re)connect or leave.
  /// Mirrors the reference's `_auto_reconnect_attempted`.
  bool _reconnectAttempted = false;

  /// Serializes every session-mutating operation (join, leave, gateway-driven
  /// reconnect, and forced disconnect) onto a single chain so a LiveKit
  /// `connect()` and `disconnect()` can never run concurrently on the one reused
  /// [VoiceSession]. Without this, switching channels races the in-flight join
  /// against the server's gateway echoes (`voice.server_update` reconnect and
  /// the leave-channel state update), driving two overlapping connect/teardown
  /// cycles that wedge the WebRTC layer — the "works once, then hangs and never
  /// reconnects" failure.
  Future<void> _queue = Future<void>.value();

  Future<void> _serialize(Future<void> Function() op) {
    final next = _queue.then((_) => op());
    // Keep the chain alive even if one op throws; the caller still sees the
    // error via [next].
    _queue = next.catchError((_) {});
    return next;
  }

  /// Joins the voice [channelId] in [spaceId]. Leaves any current channel
  /// first, fetches LiveKit credentials over REST, then connects the session.
  /// [spaceId] is null for DM/group-DM calls, which have no parent space.
  Future<void> join(String channelId, String? spaceId) =>
      _serialize(() => _joinLocked(channelId, spaceId));

  Future<void> _joinLocked(String channelId, String? spaceId) async {
    if (state.channelId == channelId) return;
    if (state.isConnected) await _leaveLocked();

    // Pin to whichever connection is active *now* — that's the server whose
    // channel was tapped. Resolve its client by key so later voice calls keep
    // hitting it even after the user makes another server active.
    final serverKey = ref.read(connectionsControllerProvider).activeKey;
    final client = serverKey == null
        ? null
        : ref.read(accordAuthProvider.notifier).clientForKey(serverKey);
    if (client == null) {
      state = state.copyWith(error: 'No connection found');
      return;
    }

    _session ??= _buildSession();
    _reconnectAttempted = false;

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
      serverKey: serverKey,
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
  Future<void> leave() => _serialize(_leaveLocked);

  Future<void> _leaveLocked() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    _reconnectAttempted = false;
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

  /// Toggles screen sharing. When starting, [sourceId] selects a specific
  /// screen/window chosen from the desktop source picker (null = let the
  /// platform prompt). Capture quality follows the configured video settings.
  Future<void> toggleScreenShare({String? sourceId}) async {
    if (!state.isConnected) return;
    final enable = !state.selfStream;
    if (enable) {
      final settings = ref.read(settingsControllerProvider);
      final (width, height) = settings.videoDimensions;
      await _session?.setScreenShareEnabled(
        true,
        sourceId: sourceId,
        width: width,
        height: height,
        fps: settings.videoFps,
        bitrate: settings.videoBitrate,
      );
    } else {
      await _session?.setScreenShareEnabled(false);
    }
    state = state.copyWith(selfStream: enable);
    _sendVoiceStateUpdate();
  }

  /// Fresh LiveKit credentials arrived over the gateway. Reconnect the backend
  /// only when the session has actually dropped (token refresh / SFU move) so
  /// we don't churn a healthy initial connection that the join already wired.
  /// Serialized so it waits behind any in-flight join rather than firing a
  /// second concurrent connect on the shared session.
  void handleServerUpdate(AccordVoiceServerUpdate info) {
    _serialize(() => _serverUpdateLocked(info));
  }

  Future<void> _serverUpdateLocked(AccordVoiceServerUpdate info) async {
    if (!state.isConnected || state.channelId != info.channelId) return;
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    final sessionState = _session?.state;
    final needsReconnect = sessionState == VoiceSessionState.disconnected ||
        sessionState == VoiceSessionState.failed ||
        sessionState == VoiceSessionState.reconnecting;
    if (!needsReconnect) return;
    await _session?.connect(url, token,
        selfMute: state.selfMute, selfDeaf: state.selfDeaf);
  }

  /// The server removed us from voice (our gateway state's channel went null).
  /// [leftChannel] is the channel the null-echo reported leaving; the teardown
  /// only fires if we're *still* in it when this runs.
  void handleForcedDisconnect(String? leftChannel) {
    _serialize(() => _forcedDisconnectLocked(leftChannel));
  }

  Future<void> _forcedDisconnectLocked(String? leftChannel) async {
    if (!state.isConnected) return;
    // A channel switch leaves the old channel (server echoes our own
    // channel→null), which queues a forced-disconnect *behind* the in-flight
    // join to the new channel. By the time it runs we've already connected
    // elsewhere — that stale echo must not tear the new session down. Only
    // honour the kick if we're still in the channel it was for.
    if (leftChannel != null && state.channelId != leftChannel) return;
    _reconnectAttempted = false;
    await _session?.disconnect();
    state = const VoiceConnection();
  }

  VoiceSession _buildSession() {
    final session = VoiceSession()
      ..onChanged = _onSessionChanged
      ..onTracksChanged = _onSessionTracksChanged
      ..onStateChanged = _onSessionStateChanged
      ..onDisconnected = _onSessionDisconnected;
    return session;
  }

  /// High-frequency speaker churn: refresh the speaking set, but only push a new
  /// state (and rebuild) when it actually changed. LiveKit's `Room` notifies on
  /// every active-speaker/audio-level report — many times per second while
  /// anyone talks — so an unconditional update here pegs the UI thread.
  void _onSessionChanged() {
    final speaking = _session?.speakingUserIds ?? const {};
    if (setEquals(speaking, state.speakingUserIds)) return;
    state = state.copyWith(speakingUserIds: speaking);
  }

  /// Structural change (track sub/unsub, publish, participant join/leave): bump
  /// the grid-rebuild tick. These are comparatively rare, so rebuilding the
  /// video grid here is cheap.
  void _onSessionTracksChanged() {
    state = state.copyWith(tick: state.tick + 1);
  }

  /// Dismisses the transient voice error (the bar auto-clears it after a few
  /// seconds; mirrors the reference's 4s error tween).
  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  void _onSessionStateChanged(VoiceSessionState sessionState) {
    if (!state.isConnected) return;
    // A clean (re)connection re-arms the one-shot reconnect guard.
    if (sessionState == VoiceSessionState.connected) {
      _reconnectAttempted = false;
    }
    state = state.copyWith(sessionState: sessionState);
  }

  void _onSessionDisconnected({required bool intentional}) {
    if (intentional || !state.isConnected) return;
    // LiveKit gave up its own retries (terminal RoomDisconnected). Don't just
    // sit in "reconnecting" waiting for a gateway push that may never come —
    // proactively refresh credentials and reconnect, like the reference's
    // `_try_auto_reconnect`. A concurrent gateway voice.server_update is handled
    // because both reconnect paths run on the same serialized [_queue].
    state = state.copyWith(sessionState: VoiceSessionState.reconnecting);
    _serialize(_reconnectLocked);
  }

  /// Re-fetches LiveKit credentials over REST for the channel we're still in and
  /// reconnects the session. One attempt per drop (guarded by
  /// [_reconnectAttempted], re-armed on a successful connect).
  Future<void> _reconnectLocked() async {
    if (_reconnectAttempted || !state.isConnected) return;
    // A gateway server_update may have already reconnected us while this was
    // queued; don't tear a healthy session back down.
    if (_session?.state == VoiceSessionState.connected) return;
    final channelId = state.channelId!;
    final client = _client;
    if (client == null) return;
    _reconnectAttempted = true;

    final result = await client.voice
        .join(channelId, selfMute: state.selfMute, selfDeaf: state.selfDeaf);
    final info = result.data;
    if (!result.ok || info is! AccordVoiceServerUpdate) {
      state = state.copyWith(
        sessionState: VoiceSessionState.failed,
        error: 'Voice reconnect failed — could not refresh credentials',
      );
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      state = state.copyWith(
        sessionState: VoiceSessionState.failed,
        error: 'Voice reconnect failed',
      );
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    await _session?.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
    );
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
