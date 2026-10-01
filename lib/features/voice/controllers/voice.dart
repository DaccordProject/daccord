import 'dart:async';

import 'package:accordkit/accordkit.dart';
import 'package:bonfire/features/authentication/repositories/accord_auth.dart';
import 'package:bonfire/features/events/controllers/presence.dart';
import 'package:bonfire/features/notifications/services/sound.dart';
import 'package:bonfire/features/server/controllers/connections.dart';
import 'package:bonfire/features/settings/controllers/settings.dart';
import 'package:bonfire/features/voice/controllers/voice_states.dart';
import 'package:bonfire/features/voice/services/afk_monitor.dart';
import 'package:bonfire/features/voice/services/voice_session.dart';
import 'package:bonfire/features/voice/utils/afk_logic.dart';
import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:collection/collection.dart';
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
    this.serverKey,
    this.sessionState = VoiceSessionState.disconnected,
    this.selfMute = false,
    this.selfDeaf = false,
    this.selfVideo = false,
    this.selfStream = false,
    this.speakingUserIds = const {},
    this.isAfk = false,
    this.error,
    this.tick = 0,
  });

  final String? channelId;
  final String? spaceId;

  /// The connection (`userId@baseUrl`) the voice session is pinned to — *not*
  /// whichever server is active. Every voice REST/gateway call routes through
  /// this key's client so switching servers mid-call doesn't send our
  /// leave/state updates to the wrong server.
  final String? serverKey;
  final VoiceSessionState sessionState;
  final bool selfMute;
  final bool selfDeaf;
  final bool selfVideo;

  /// Whether we're currently screen-sharing.
  final bool selfStream;
  final Set<String> speakingUserIds;

  /// Whether *we* have been idle long enough to count as away (see
  /// `AfkMonitor`); surfaced to other members by flipping our presence to
  /// `idle`.
  final bool isAfk;

  /// Transient error message for the voice bar (auto-dismissed by the UI).
  final String? error;

  /// Bumped when the set of renderable LiveKit tracks/participants changes; the
  /// video grid watches it to rebuild its tiles.
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
    bool? isAfk,
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
      isAfk: isAfk ?? this.isAfk,
      error: clearError ? null : (error ?? this.error),
      tick: tick ?? this.tick,
    );
  }
}

/// Orchestrates voice channel join/leave and media toggles (reference:
/// `client_voice.gd`). Owns a single [VoiceSession] (the LiveKit transport) and
/// pushes runtime self-state to the server via `updateVoiceState`.
@Riverpod(keepAlive: true)
class VoiceController extends _$VoiceController {
  VoiceSession? _session;

  /// The LiveKit session, exposed so the video grid can render its tracks.
  VoiceSession? get session => _session;

  /// Installs a stand-in session so tests can exercise the media toggles
  /// (mute/camera/screen share) without a native LiveKit room.
  @visibleForTesting
  set debugSession(VoiceSession? session) => _session = session;

  /// The local microphone level (0–1), for the mic-activity meter.
  double get localAudioLevel => _session?.localAudioLevel ?? 0;

  /// Whether the local mic is currently registering as speaking.
  bool get localIsSpeaking => _session?.localIsSpeaking ?? false;

  /// Idle detection for the local user. Created lazily so tests that override
  /// [build] (and so never join) don't install global input hooks.
  AfkMonitor? _afkMonitor;

  AfkMonitor _ensureAfkMonitor() {
    final existing = _afkMonitor;
    if (existing != null) return existing;
    final monitor = AfkMonitor()
      ..onAfkChanged = _onAfkChanged
      ..micActive = _micActive;
    return _afkMonitor = monitor;
  }

  /// The presence status we had before AFK flipped us to `idle`, so returning
  /// restores exactly what the user chose. Null when we didn't touch it.
  String? _presenceBeforeAfk;

  /// The connection key we published the `idle` status on, so it can be undone
  /// even after the voice session (and its `serverKey`) has gone away.
  String? _afkPresenceKey;

  @override
  VoiceConnection build() {
    // Push live audio device/volume changes to the active session so the voice
    // settings page takes effect without a reconnect.
    ref.listen(
      settingsControllerProvider.select(
        (s) => (
          afkTimeoutMinutes: s.voiceAfkTimeoutMinutes,
          audioInputDeviceId: s.audioInputDeviceId,
          audioOutputDeviceId: s.audioOutputDeviceId,
          outputVolume: s.outputVolume,
          inputVolume: s.inputVolume,
        ),
      ),
      (prev, next) {
        if (prev?.afkTimeoutMinutes != next.afkTimeoutMinutes) {
          _syncAfk();
        }
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
      },
    );
    ref.onDispose(() {
      _afkMonitor?.dispose();
      _afkMonitor = null;
      _session?.dispose();
      _session = null;
      soundManager.voiceSessionActive = false;
    });
    return const VoiceConnection();
  }

  /// The client for the connection our voice session is pinned to
  /// ([VoiceConnection.serverKey]), not the active one.
  AccordClient? get _client {
    final key = state.serverKey;
    if (key == null) return null;
    return ref.read(accordAuthProvider.notifier).clientForKey(key);
  }

  /// One-shot guard so a dropped connection triggers at most one proactive
  /// credential-refresh reconnect; reset whenever we (re)connect or leave.
  bool _reconnectAttempted = false;

  /// Serializes every session-mutating operation (join, leave, gateway-driven
  /// reconnect, forced disconnect) so a LiveKit `connect()` and `disconnect()`
  /// never overlap on the one reused [VoiceSession]. Otherwise a channel switch
  /// races the in-flight join against the server's gateway echoes, and the
  /// overlapping connect/teardown cycles wedge the WebRTC layer.
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
  Future<void> join(String channelId, String? spaceId) async {
    // Joining is itself activity — never land in a channel already AFK.
    _ensureAfkMonitor().markActivity();
    await _serialize(() => _joinLocked(channelId, spaceId));
    _syncAfk();
  }

  Future<void> _joinLocked(String channelId, String? spaceId) async {
    if (state.channelId == channelId) return;
    if (state.isConnected) await _leaveLocked();

    // Pin to whichever connection is active *now* — the server whose channel
    // was tapped.
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

    final result = await client.voice.join(
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
    );
    final info = result.data;
    if (!result.ok || info is! AccordVoiceServerUpdate) {
      state = state.copyWith(
        error: result.error?.message ?? 'Failed to join voice channel',
      );
      return;
    }
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      await client.voice.leave(channelId);
      state = state.copyWith(
        error: 'Voice backend unavailable — server returned no credentials',
      );
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
    // Flag the live call *before* the media session comes up, so no chime can
    // reconfigure the platform audio session underneath it.
    soundManager.voiceSessionActive = true;
    await _session!.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
    );
    _applyMicOutcome();
    soundManager.play('voice_join');
    await _refreshVoiceStates(channelId);
  }

  /// After a (re)connect whose mic could not be captured or published: stay in
  /// the channel but as *muted*, tell the server so, and surface the reason
  /// rather than showing a live mic that sends nothing.
  void _applyMicOutcome() {
    final micError = _session?.micError;
    if (micError == null || !state.isConnected || state.selfMute) return;
    state = state.copyWith(selfMute: true, error: micError);
    _sendVoiceStateUpdate();
  }

  /// Leaves the current voice channel and tears the session down.
  Future<void> leave() async {
    await _serialize(_leaveLocked);
    _syncAfk();
  }

  Future<void> _leaveLocked() async {
    final channelId = state.channelId;
    if (channelId == null) return;
    _reconnectAttempted = false;
    await _session?.disconnect();
    soundManager.voiceSessionActive = false;
    await _client?.voice.leave(channelId);
    soundManager.play('voice_leave');
    state = const VoiceConnection();
  }

  void toggleMute() => setMute(!state.selfMute);

  void setMute(bool muted) {
    _afkMonitor?.markActivity();
    if (!state.isConnected) return;
    state = state.copyWith(selfMute: muted);
    soundManager.play(muted ? 'mute' : 'unmute');
    _sendVoiceStateUpdate();
    final session = _session;
    if (session != null) unawaited(_applyMic(session, enabled: !muted));
  }

  /// Applies a mute toggle to the media session. An *unmute* that fails (the
  /// OS denied the mic, no capture device) is reverted so the bar doesn't show
  /// a live mic that isn't, and the reason is surfaced.
  Future<void> _applyMic(VoiceSession session, {required bool enabled}) async {
    final error = await session.setMicEnabled(enabled);
    if (error == null || !enabled || !state.isConnected || state.selfMute) {
      return;
    }
    state = state.copyWith(selfMute: true, error: error);
    _sendVoiceStateUpdate();
  }

  void toggleDeafen() => setDeafen(!state.selfDeaf);

  void setDeafen(bool deafened) {
    _afkMonitor?.markActivity();
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
  /// platform prompt). Quality comes from the *screen-share* settings, not the
  /// camera ones.
  Future<void> toggleScreenShare({String? sourceId}) async {
    if (!state.isConnected) return;
    final enable = !state.selfStream;
    if (enable) {
      final settings = ref.read(settingsControllerProvider);
      final (width, height) = settings.screenShareDimensions;
      await _session?.setScreenShareEnabled(
        true,
        sourceId: sourceId,
        width: width,
        height: height,
        fps: settings.screenShareFps,
        bitrate: settings.screenShareBitrate,
        motionPriority: settings.screenShareMotionPriority,
      );
    } else {
      await _session?.setScreenShareEnabled(false);
    }
    state = state.copyWith(selfStream: enable);
    _sendVoiceStateUpdate();
  }

  /// Fresh LiveKit credentials arrived over the gateway. Reconnects only when
  /// the session has actually dropped ([needsReconnect]); serialized behind any
  /// in-flight join.
  void handleServerUpdate(AccordVoiceServerUpdate info) {
    _serialize(() => _serverUpdateLocked(info));
  }

  Future<void> _serverUpdateLocked(AccordVoiceServerUpdate info) async {
    if (!state.isConnected || state.channelId != info.channelId) return;
    final url = info.livekitUrl;
    final token = info.token;
    if (url == null || url.isEmpty || token == null || token.isEmpty) return;
    final sessionState = _session?.state;
    if (sessionState == null || !needsReconnect(sessionState)) return;
    await _session?.connect(
      url,
      token,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      relayOnly: ref.read(settingsControllerProvider).voiceRelayOnly,
    );
    _applyMicOutcome();
  }

  /// The server removed us from voice (our gateway state's channel went null).
  /// [leftChannel] is the channel the null-echo reported leaving; the teardown
  /// only fires if we're *still* in it when this runs, since a channel switch's
  /// own echo queues behind the join to the new channel.
  void handleForcedDisconnect(String? leftChannel) {
    _serialize(() => _forcedDisconnectLocked(leftChannel));
  }

  Future<void> _forcedDisconnectLocked(String? leftChannel) async {
    if (!state.isConnected) return;
    if (leftChannel != null && state.channelId != leftChannel) return;
    _reconnectAttempted = false;
    await _session?.disconnect();
    soundManager.voiceSessionActive = false;
    state = const VoiceConnection();
    _syncAfk();
  }

  VoiceSession _buildSession() => VoiceSession()
    ..onChanged = _onSessionChanged
    ..onTracksChanged = _onSessionTracksChanged
    ..onStateChanged = _onSessionStateChanged
    ..onDisconnected = _onSessionDisconnected;

  /// High-frequency speaker churn (many times per second while anyone talks):
  /// only push a new state when the speaking set actually changed.
  void _onSessionChanged() {
    final speaking = _session?.speakingUserIds ?? const {};
    if (setEquals(speaking, state.speakingUserIds)) return;
    state = state.copyWith(speakingUserIds: speaking);
  }

  void _onSessionTracksChanged() {
    state = state.copyWith(tick: state.tick + 1);
  }

  /// Dismisses the transient voice error.
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
    if (!shouldAutoReconnect(
      intentional: intentional,
      stillConnected: state.isConnected,
      alreadyAttempted: _reconnectAttempted,
    )) {
      return;
    }
    // LiveKit gave up its own retries. Rather than wait on a gateway push that
    // may never come, refresh credentials and reconnect; a concurrent
    // voice.server_update is safe because both paths share [_queue].
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

    final result = await client.voice.join(
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
    );
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
      relayOnly: settings.voiceRelayOnly,
      audioInputDeviceId: settings.audioInputDeviceId,
      audioOutputDeviceId: settings.audioOutputDeviceId,
      outputVolume: settings.outputVolume,
      inputVolume: settings.inputVolume,
    );
    _applyMicOutcome();
  }

  Future<void> _refreshVoiceStates(String channelId) async {
    final client = _client;
    final serverKey = state.serverKey;
    if (client == null || serverKey == null) return;
    final result = await client.voice.getStatus(channelId);
    final data = result.data;
    if (_client != client ||
        state.serverKey != serverKey ||
        !result.ok ||
        data is! List<AccordVoiceState>) {
      return;
    }
    ref
        .read(voiceStatesControllerProvider(serverKey).notifier)
        .seedChannel(channelId, data);
  }

  // ── AFK ──
  //
  // Detection is client-side: `AccordVoiceState` has no `afk` field and
  // `updateVoiceState` accepts only the self_* flags, so AFK is published to
  // other members by flipping our presence to `idle`.

  /// Re-points the idle monitor at the current connection + timeout setting.
  void _syncAfk() {
    final minutes = ref.read(settingsControllerProvider).voiceAfkTimeoutMinutes;
    _ensureAfkMonitor().update(
      connected: state.isConnected,
      timeout: effectiveAfkTimeout(minutes),
    );
  }

  /// Whether the mic is picking us up right now — talking counts as activity
  /// even with no keyboard/mouse input. Muted means no input by definition.
  bool _micActive() {
    final session = _session;
    if (session == null || state.selfMute) return false;
    if (session.localIsSpeaking) return true;
    final threshold = ref.read(settingsControllerProvider).speakingThreshold;
    return session.localAudioLevel >= threshold;
  }

  void _onAfkChanged(bool afk) {
    if (state.isAfk == afk) return;
    state = state.copyWith(isAfk: afk);
    _publishAfkPresence(afk);
    if (afk) unawaited(_moveToAfkChannel());
  }

  /// Mirrors AFK onto our presence so *other* members can see it. Only ever
  /// touches a plain `online` status: a user who deliberately picked DND or
  /// Invisible keeps it, and we restore whatever they had on return.
  void _publishAfkPresence(bool afk) {
    // On the way back, use the connection we *published on* rather than the
    // current one: leaving voice clears `serverKey` before the AFK flag is
    // cleared, and a stranded `idle` status would never be restored.
    final key = afk ? state.serverKey : _afkPresenceKey;
    if (key == null) return;
    final client = ref.read(accordAuthProvider.notifier).clientForKey(key);
    final userId = ref
        .read(connectionsControllerProvider)
        .connectionFor(key)
        ?.session
        .userId;
    if (client == null || userId == null) return;
    final presences = ref.read(presenceControllerProvider(key));
    final current = accordPresenceStatus(presences, userId);

    if (afk) {
      if (current != 'online') return;
      _presenceBeforeAfk = current;
      _afkPresenceKey = key;
      _setPresence(client, key, userId, 'idle', presences);
    } else {
      final restore = _presenceBeforeAfk;
      _presenceBeforeAfk = null;
      _afkPresenceKey = null;
      // Don't stomp a status the user changed by hand while away.
      if (restore == null || current != 'idle') return;
      _setPresence(client, key, userId, restore, presences);
    }
  }

  void _setPresence(
    AccordClient client,
    String serverKey,
    String userId,
    String status,
    PresenceMap presences,
  ) {
    final custom = accordCustomStatus(presences, userId);
    client.gateway.updatePresence(
      status,
      activity: custom == null ? const {} : {'name': custom, 'type': 'custom'},
    );
    ref
        .read(presenceControllerProvider(serverKey).notifier)
        .upsert(
          AccordPresence(
            userId: userId,
            status: status,
            activities: custom == null
                ? []
                : [AccordActivity(name: custom, type: 'custom')],
          ),
        );
  }

  /// Moves us into the space's designated AFK channel, when it has one. Accord
  /// has no server-side move, so this is a plain re-join of the local user.
  Future<void> _moveToAfkChannel() async {
    if (!ref.read(settingsControllerProvider).voiceAfkAutoMove) return;
    final spaceId = state.spaceId;
    final serverKey = state.serverKey;
    if (spaceId == null || serverKey == null) return;
    // `_joinLocked` pins to whichever connection is *active*, so only auto-move
    // when the call is on that connection — otherwise we'd rejoin on the wrong
    // server.
    final connections = ref.read(connectionsControllerProvider);
    if (connections.activeKey != serverKey) return;
    final space = connections
        .connectionFor(serverKey)
        ?.spaces
        .firstWhereOrNull((s) => s.id == spaceId);
    final afkChannelId = space?.afkChannelId;
    if (afkChannelId == null ||
        afkChannelId.isEmpty ||
        afkChannelId == state.channelId) {
      return;
    }

    // Deliberately the private join: the public one marks activity and
    // re-syncs, which would immediately un-AFK us again.
    await _serialize(() => _joinLocked(afkChannelId, spaceId));
    if (state.isConnected && (_afkMonitor?.isAfk ?? false)) {
      state = state.copyWith(isAfk: true);
    }
  }

  void _sendVoiceStateUpdate() {
    final channelId = state.channelId;
    if (channelId == null) return;
    // `spaceId` is null during a DM call; the server resolves the scope from
    // the channel.
    _client?.updateVoiceState(
      state.spaceId,
      channelId,
      selfMute: state.selfMute,
      selfDeaf: state.selfDeaf,
      selfVideo: state.selfVideo,
      selfStream: state.selfStream,
    );
  }
}
