import 'dart:async';

import 'package:bonfire/features/voice/utils/voice_logic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as rtc;
import 'package:livekit_client/livekit_client.dart';

/// Lifecycle of the LiveKit media connection, mirroring the reference client's
/// `ClientModels.VoiceSessionState`.
enum VoiceSessionState {
  connecting,
  connected,
  reconnecting,
  failed,
  disconnected,
}

/// Thin wrapper around a LiveKit [Room] that exposes the control surface the
/// [VoiceController] needs. The Dart port of the reference `livekit_adapter.gd`
/// — but the `livekit_client` SDK already handles mic capture, audio playback,
/// device selection, and speaking detection, so the manual Godot audio pipeline
/// collapses into a handful of SDK calls here.
///
/// Participant identity equals the Accord user ID (the server sets it), so the
/// UI can match LiveKit participants to voice states directly.
class VoiceSession {
  Room? _room;
  EventsListener<RoomEvent>? _listener;
  VoiceSessionState _state = VoiceSessionState.disconnected;
  String? _lastError;
  bool _deafened = false;
  bool _intentionalDisconnect = false;

  /// Output (remote-audio) gain as a 0–2 multiplier; applied to every remote
  /// audio track. The reference dropped to -80 dB for deafen; here LiveKit has
  /// no per-track volume so we lean on the WebRTC track volume.
  double _outputGain = 1;

  /// Input (microphone) gain as a 0–2 multiplier; best-effort — not every
  /// platform honours setting volume on a capture track.
  double _inputGain = 1;

  /// Continuously-polled local mic level (0–1), read from the local audio
  /// track's WebRTC `media-source` stats. Unlike [Participant.audioLevel] —
  /// which LiveKit only updates from throttled server active-speaker reports —
  /// this is computed locally and updates every poll, so the meter reacts
  /// immediately to quiet input.
  double _localInputLevel = 0;
  Timer? _levelTimer;
  bool _pollingLevel = false;

  /// Fires on high-frequency room churn (active-speaker / audio-level reports).
  /// The controller uses this only to refresh the speaking set, so it must stay
  /// cheap — it can fire many times per second while anyone is talking.
  VoidCallback? onChanged;

  /// Fires only when the renderable track/participant set actually changes
  /// (track sub/unsub, local publish/unpublish, participant join/leave). The
  /// controller bumps its grid-rebuild `tick` from here, so the expensive video
  /// grid rebuilds on structural changes rather than on every speaker report.
  VoidCallback? onTracksChanged;

  /// Fires when the session transitions to a new lifecycle [state].
  void Function(VoiceSessionState state)? onStateChanged;

  /// Fires when the room disconnects. [intentional] is true for a local
  /// leave/teardown, false for a dropped connection (the controller may then
  /// attempt a credential refresh + reconnect, like the reference).
  void Function({required bool intentional})? onDisconnected;

  Room? get room => _room;
  VoiceSessionState get state => _state;
  String? get lastError => _lastError;
  bool get isDeafened => _deafened;

  LocalParticipant? get localParticipant => _room?.localParticipant;

  /// Our published camera track (null when the camera is off).
  VideoTrack? get localCameraTrack =>
      _videoTrackOf(_room?.localParticipant, TrackSource.camera);

  /// Our published screen-share track (null when not sharing).
  VideoTrack? get localScreenTrack =>
      _videoTrackOf(_room?.localParticipant, TrackSource.screenShareVideo);

  /// A remote participant's camera track, or null when they have none.
  VideoTrack? remoteCameraTrack(String userId) =>
      _videoTrackOf(_remoteByIdentity(userId), TrackSource.camera);

  /// A remote participant's screen-share track, or null when they aren't
  /// sharing (or it hasn't been subscribed yet).
  VideoTrack? remoteScreenTrack(String userId) =>
      _videoTrackOf(_remoteByIdentity(userId), TrackSource.screenShareVideo);

  Participant? _remoteByIdentity(String userId) {
    final room = _room;
    if (room == null || userId.isEmpty) return null;
    for (final p in room.remoteParticipants.values) {
      if (p.identity == userId) return p;
    }
    return null;
  }

  VideoTrack? _videoTrackOf(Participant? participant, TrackSource source) {
    if (participant == null) return null;
    for (final pub in participant.videoTrackPublications) {
      if (pub.source == source) {
        final track = pub.track;
        if (track is VideoTrack) return track;
      }
    }
    return null;
  }

  /// User IDs (participant identities) currently speaking.
  Set<String> get speakingUserIds {
    final room = _room;
    if (room == null) return const {};
    final participants = <Participant>[
      if (room.localParticipant != null) room.localParticipant!,
      ...room.remoteParticipants.values,
    ];
    return {
      for (final p in participants)
        if (p.isSpeaking && p.identity.isNotEmpty) p.identity,
    };
  }

  /// Our local microphone audio level (0–1), polled continuously from the local
  /// track's WebRTC stats. Drives the mic-activity meter so the user can see
  /// their own input being picked up. Zero while silent/muted.
  double get localAudioLevel => _localInputLevel;

  /// Whether the local mic is currently over LiveKit's own speaking threshold
  /// (server active-speaker report). The meter prefers a locally-computed
  /// threshold comparison for responsiveness; this is the fallback.
  bool get localIsSpeaking => _room?.localParticipant?.isSpeaking ?? false;

  /// Connects to [url] with [token], reusing the single long-lived [Room].
  ///
  /// Crucially this does **not** recreate the [Room] per call: a fresh `Room`
  /// each connect (then disposing the old one) leaves the previous native
  /// WebRTC `PeerConnection` + mic capture half-released, so the next publish
  /// throws `TrackPublishException` / `No active stream to cancel` — exactly the
  /// channel-swap breakage. Instead we keep one `Room` for the session's life,
  /// soft-disconnect it before reconnecting, and only fully dispose in
  /// [dispose]. The initial mute/deafen are applied once connected.
  Future<void> connect(
    String url,
    String token, {
    bool selfMute = false,
    bool selfDeaf = false,
    String? audioInputDeviceId,
    String? audioOutputDeviceId,
    int outputVolume = 100,
    int inputVolume = 100,
  }) async {
    _deafened = selfDeaf;
    _outputGain = voiceGain(outputVolume);
    _inputGain = voiceGain(inputVolume);

    final captureDeviceId = normalizeDeviceId(audioInputDeviceId);
    final room = _ensureRoom();

    // Channel swap / reconnect: release the prior connection's media and drop
    // the socket first, but keep the *same* Room object. `_intentionalDisconnect`
    // stays set across the reconnect so the RoomDisconnectedEvent this triggers
    // is treated as intentional (no auto-reconnect) — it's reset only once the
    // new connection is up.
    _intentionalDisconnect = true;
    if (room.connectionState != ConnectionState.disconnected) {
      _stopLevelPolling();
      await _stopLocalMedia();
      try {
        await room.disconnect();
      } catch (e) {
        debugPrint('LiveKit pre-connect disconnect error: $e');
      }
    }

    _setState(VoiceSessionState.connecting);
    _lastError = null;
    try {
      await room.connect(url, token);
      // The new connection is live — genuine drops from here are unintentional.
      _intentionalDisconnect = false;
      // The SDK publishes the mic for us; honour the initial mute state and the
      // chosen capture device (we no longer bake it into RoomOptions, since the
      // Room outlives any single device selection).
      await _guardMedia(
        'mic',
        () => room.localParticipant?.setMicrophoneEnabled(
          !selfMute,
          audioCaptureOptions: AudioCaptureOptions(deviceId: captureDeviceId),
        ),
      );
      if (selfDeaf) await _applyDeafen(true);
      await _applyOutputDevice(audioOutputDeviceId);
      await _applyOutputGain();
      await _applyInputGain();
      _startLevelPolling();
      _setState(VoiceSessionState.connected);
    } catch (e) {
      _lastError = '$e';
      debugPrint('LiveKit connect failed: $e');
      _setState(VoiceSessionState.failed);
      // Soft cleanup — keep the Room so the next attempt can reuse it.
      await _softDisconnect();
    }
  }

  /// Lazily creates the one [Room] this session uses for its entire lifetime,
  /// wiring the change/event listeners exactly once. Subsequent connects reuse
  /// it; it's only torn down in [dispose].
  Room _ensureRoom() {
    var room = _room;
    if (room != null) return room;
    room = Room();
    _room = room;
    room.addListener(_onRoomChanged);
    final listener = room.createListener();
    _listener = listener;
    _wireListener(listener);
    return room;
  }

  /// Stops any local capture (screen-share, camera, mic) so the native devices
  /// are released before we drop the socket. Each toggle is guarded — stopping
  /// an already-gone track throws "No active stream to cancel" on some
  /// platforms, which must not abort the disconnect.
  Future<void> _stopLocalMedia() async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    await _guardMedia(
      'stop screen share',
      () => participant.setScreenShareEnabled(false),
    );
    await _guardMedia('stop camera', () => participant.setCameraEnabled(false));
    await _guardMedia(
      'stop mic',
      () => participant.setMicrophoneEnabled(false),
    );
  }

  /// Drops the live connection but keeps the [Room] object alive for reuse.
  Future<void> _softDisconnect() async {
    final room = _room;
    if (room == null) return;
    _intentionalDisconnect = true;
    _stopLevelPolling();
    await _stopLocalMedia();
    try {
      await room.disconnect();
    } catch (e) {
      debugPrint('LiveKit disconnect error: $e');
    }
  }

  /// Leaves the channel but keeps the reusable [Room] (local intent — no
  /// auto-reconnect). The Room is only fully released in [dispose].
  Future<void> disconnect() => _softDisconnect();

  Future<void> setMicEnabled(bool enabled) async {
    await _guardMedia(
      'mic',
      () => _room?.localParticipant?.setMicrophoneEnabled(enabled),
    );
  }

  /// Silences (or restores) every remote participant's audio locally. LiveKit
  /// has no per-track volume, so we toggle the audio subscriptions — the
  /// reference dropped remote playback to -80 dB for the same effect.
  Future<void> setDeafened(bool deafened) async {
    _deafened = deafened;
    await _applyDeafen(deafened);
  }

  /// Enables (or disables) the camera. When enabling, [width]/[height]/[fps]/
  /// [bitrate] shape the capture via [CameraCaptureOptions] so the configured
  /// video-quality settings take effect, and [deviceId] selects the camera.
  Future<void> setCameraEnabled(
    bool enabled, {
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    String? deviceId,
  }) async {
    CameraCaptureOptions? options;
    if (enabled && width != null && height != null) {
      options = CameraCaptureOptions(
        deviceId: normalizeDeviceId(deviceId),
        params: VideoParameters(
          dimensions: VideoDimensions(width, height),
          encoding: VideoEncoding(
            maxBitrate: bitrate ?? 1700000,
            maxFramerate: fps ?? 30,
          ),
        ),
      );
    }
    await _guardMedia(
      'camera',
      () => _room?.localParticipant?.setCameraEnabled(
        enabled,
        cameraCaptureOptions: options,
      ),
    );
  }

  /// Enables (or disables) screen sharing. When enabling, [sourceId] selects a
  /// specific screen or window (from the desktop source picker); a null/empty
  /// id falls back to the platform's own capture prompt (web `getDisplayMedia`,
  /// mobile system capture). [width]/[height]/[fps]/[bitrate] shape both the
  /// capture and the *published encoding* from the screen-share quality
  /// settings; [motionPriority] decides what the encoder sacrifices first when
  /// it runs short of CPU/bandwidth.
  ///
  /// Capture options alone are not enough: LiveKit computes the send encoding
  /// from `VideoPublishOptions`, and when we leave that unset it falls back to
  /// its own screen-share presets, which are picked for slides — 720p caps at
  /// 800 kbps @ 5 fps, 1080p at 2.5 Mbps @ 15 fps — no matter what we asked the
  /// capturer for. That mismatch is why shared gameplay ran at a fraction of
  /// the configured frame rate (issue #151), so we publish the track ourselves
  /// with an explicit `screenShareEncoding`.
  Future<void> setScreenShareEnabled(
    bool enabled, {
    String? sourceId,
    int? width,
    int? height,
    int? fps,
    int? bitrate,
    bool motionPriority = true,
  }) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;

    if (!enabled) {
      await _guardMedia(
        'screen share',
        () => participant.setScreenShareEnabled(false),
      );
      return;
    }

    // No more hardcoded 15 fps fallback: an unspecified size/rate means the
    // screen-share defaults (720p60), not a slideshow.
    final resolvedFps = fps ?? defaultScreenShareFps;
    final resolvedBitrate = bitrate ?? defaultScreenShareBitrate;
    final dimensions = (width != null && height != null)
        ? VideoDimensions(width, height)
        : const VideoDimensions(1280, 720);
    final encoding = VideoEncoding(
      maxBitrate: resolvedBitrate,
      maxFramerate: resolvedFps,
    );
    final options = ScreenShareCaptureOptions(
      sourceId: (sourceId != null && sourceId.isNotEmpty) ? sourceId : null,
      maxFrameRate: resolvedFps.toDouble(),
      params: VideoParameters(dimensions: dimensions, encoding: encoding),
    );

    await _guardMedia(
      'screen share',
      () => _publishScreenShare(
        participant,
        options: options,
        encoding: encoding,
        motionPriority: motionPriority,
      ),
    );
  }

  /// Publishes the screen-share track with an explicit encoding.
  ///
  /// `LocalParticipant.setScreenShareEnabled` takes no publish options, so we
  /// create and publish the track directly to pass them. Two exceptions fall
  /// back to the SDK helper:
  ///  * iOS, where starting a share means activating the broadcast extension
  ///    (`BroadcastManager`) — logic that only lives inside the helper;
  ///  * an already-published share, where the helper's unmute path is correct.
  ///
  /// On the fallback paths we still tune the live sender afterwards, which is
  /// the one knob reachable post-publish.
  Future<void> _publishScreenShare(
    LocalParticipant participant, {
    required ScreenShareCaptureOptions options,
    required VideoEncoding encoding,
    required bool motionPriority,
  }) async {
    // Games want frames; slides/code want pixels. LiveKit's own default for a
    // screen-share track is `maintainResolution`, i.e. exactly the wrong half
    // of that trade for the case this setting exists to fix.
    final degradation = motionPriority
        ? DegradationPreference.maintainFramerate
        : DegradationPreference.maintainResolution;

    final existing = participant.getTrackPublicationBySource(
      TrackSource.screenShareVideo,
    );
    final isIOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (existing != null || isIOS) {
      await participant.setScreenShareEnabled(
        true,
        screenShareCaptureOptions: options,
      );
      await _applyScreenShareDegradation(participant, degradation);
      return;
    }

    final track = await LocalVideoTrack.createScreenShareTrack(options);
    await participant.publishVideoTrack(
      track,
      publishOptions: VideoPublishOptions(
        screenShareEncoding: encoding,
        // One layer, all of the budget. Simulcast would split the bitrate
        // across a half-resolution duplicate and double the encode cost — a
        // bad trade when the whole point is sustaining 60 fps at full detail.
        simulcast: false,
        degradationPreference: degradation,
      ),
    );
  }

  /// Applies [preference] to the published screen-share sender, for the paths
  /// where the track was published by the SDK helper rather than by us.
  Future<void> _applyScreenShareDegradation(
    LocalParticipant participant,
    DegradationPreference preference,
  ) async {
    final track = participant
        .getTrackPublicationBySource(TrackSource.screenShareVideo)
        ?.track;
    if (track is LocalVideoTrack) {
      await track.setDegradationPreference(preference);
    }
  }

  /// Switches the active microphone to [deviceId] (empty = system default).
  /// Republishes the mic track so the new device takes effect mid-call.
  Future<void> setAudioInputDevice(String deviceId) async {
    final participant = _room?.localParticipant;
    if (participant == null) return;
    await _guardMedia('input device', () async {
      if (deviceId.isNotEmpty) await rtc.Helper.selectAudioInput(deviceId);
      // Re-publish with the new capture device so it applies immediately.
      final wasEnabled = participant.isMicrophoneEnabled();
      await participant.setMicrophoneEnabled(false);
      await participant.setMicrophoneEnabled(
        wasEnabled,
        audioCaptureOptions: AudioCaptureOptions(
          deviceId: normalizeDeviceId(deviceId),
        ),
      );
      await _applyInputGain();
    });
  }

  /// Switches the speaker/output device (empty = default). Only meaningful
  /// where `canPickAudioOutputDevice` is true — i.e. everywhere but iOS and
  /// web, which is where the settings page offers the picker.
  Future<void> setAudioOutputDevice(String deviceId) =>
      _applyOutputDevice(deviceId);

  /// Sets the remote-audio output volume from a 0–200 percentage.
  Future<void> setOutputVolume(int percent) async {
    _outputGain = voiceGain(percent);
    await _applyOutputGain();
  }

  /// Sets the microphone input volume from a 0–200 percentage (best-effort).
  Future<void> setInputVolume(int percent) async {
    _inputGain = voiceGain(percent);
    await _applyInputGain();
  }

  Future<void> _applyOutputDevice(String? deviceId) async {
    if (deviceId == null || deviceId.isEmpty) return;
    await _guardMedia(
      'output device',
      () => rtc.Helper.selectAudioOutput(deviceId),
    );
  }

  Future<void> _applyOutputGain() async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        final track = pub.track;
        if (track != null) {
          await _setTrackVolume(track.mediaStreamTrack, _outputGain);
        }
      }
    }
  }

  Future<void> _applyInputGain() async {
    final track = _localMicTrack;
    if (track != null) {
      await _setTrackVolume(track.mediaStreamTrack, _inputGain);
    }
  }

  /// Polls the local mic track's WebRTC stats so [localAudioLevel] tracks input
  /// continuously, independent of the throttled server speaker reports.
  void _startLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _pollInputLevel(),
    );
  }

  void _stopLevelPolling() {
    _levelTimer?.cancel();
    _levelTimer = null;
    _localInputLevel = 0;
  }

  Future<void> _pollInputLevel() async {
    if (_pollingLevel) return; // a previous getStats call is still in flight
    _pollingLevel = true;
    try {
      final track = _localMicTrack;
      if (track is LocalAudioTrack) {
        final stats = await track.getSenderStats();
        _localInputLevel = (stats?.audioSourceStats?.audioLevel ?? 0)
            .toDouble();
      } else {
        _localInputLevel = 0; // muted/unpublished — nothing to measure
      }
    } catch (_) {
      // Transient stats failures shouldn't disturb the meter.
    } finally {
      _pollingLevel = false;
    }
  }

  AudioTrack? get _localMicTrack {
    final participant = _room?.localParticipant;
    if (participant == null) return null;
    for (final pub in participant.audioTrackPublications) {
      if (pub.source == TrackSource.microphone) {
        final track = pub.track;
        if (track is AudioTrack) return track;
      }
    }
    return null;
  }

  Future<void> _setTrackVolume(rtc.MediaStreamTrack track, double gain) async {
    await _guardMedia('volume', () => rtc.Helper.setVolume(gain, track));
  }

  /// Runs a LiveKit media toggle, swallowing platform/plugin errors. Stopping a
  /// camera/screen-share track can throw (e.g. "No active stream to cancel" when
  /// the OS already tore the capture down); an uncaught error here would crash
  /// the app, so we log and move on — the controller still updates its state.
  Future<void> _guardMedia(String what, Future<void>? Function() op) async {
    try {
      await op();
    } catch (e) {
      debugPrint('LiveKit $what toggle failed: $e');
    }
  }

  Future<void> _applyDeafen(bool deafened) async {
    final room = _room;
    if (room == null) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.audioTrackPublications) {
        if (deafened) {
          await pub.disable();
        } else {
          await pub.enable();
        }
      }
    }
  }

  void _wireListener(EventsListener<RoomEvent> listener) {
    listener
      ..on<TrackSubscribedEvent>((e) async {
        if (e.publication.kind == TrackType.AUDIO) {
          // Keep new remote audio muted while deafened, else apply our gain.
          if (_deafened) {
            await e.publication.disable();
          } else {
            final track = e.track;
            if (track is AudioTrack) {
              await _setTrackVolume(track.mediaStreamTrack, _outputGain);
            }
          }
        }
        _onTracksChanged();
      })
      ..on<TrackUnsubscribedEvent>((_) => _onTracksChanged())
      ..on<LocalTrackPublishedEvent>((_) => _onTracksChanged())
      ..on<LocalTrackUnpublishedEvent>((_) => _onTracksChanged())
      ..on<ParticipantConnectedEvent>((_) => _onTracksChanged())
      ..on<ParticipantDisconnectedEvent>((_) => _onTracksChanged())
      ..on<RoomDisconnectedEvent>((e) {
        final intentional = !isUnintentionalDisconnect(
          intentional: _intentionalDisconnect,
          clientInitiated: e.reason == DisconnectReason.clientInitiated,
        );
        _setState(VoiceSessionState.disconnected);
        onDisconnected?.call(intentional: intentional);
      })
      ..on<RoomReconnectingEvent>((_) {
        _setState(VoiceSessionState.reconnecting);
      })
      ..on<RoomReconnectedEvent>((_) {
        _setState(VoiceSessionState.connected);
      });
  }

  void _onRoomChanged() => onChanged?.call();

  void _onTracksChanged() => onTracksChanged?.call();

  void _setState(VoiceSessionState next) {
    if (!shouldEmitStateChange(_state, next)) return;
    _state = next;
    onStateChanged?.call(next);
  }

  /// Fully releases the room and listeners. Called only from [dispose] — a
  /// channel swap goes through [_softDisconnect] instead, which keeps the Room.
  Future<void> _teardownRoom() async {
    final room = _room;
    if (room == null) return;
    _intentionalDisconnect = true;
    _stopLevelPolling();
    await _stopLocalMedia();
    room.removeListener(_onRoomChanged);
    await _listener?.dispose();
    _listener = null;
    _room = null;
    try {
      await room.disconnect();
      await room.dispose();
    } catch (e) {
      debugPrint('LiveKit teardown error: $e');
    }
  }

  /// Releases the room and listeners for good.
  Future<void> dispose() => _teardownRoom();
}
