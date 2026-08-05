/// Pure decision logic for the voice stack, extracted so it can be unit-tested
/// without a native LiveKit `Room`. `VoiceSession`/`VoiceController` call these
/// directly, and the tests in `test/features/voice/voice_logic_test.dart` lock
/// the behaviour in so a future change to the voice layer fails loudly rather
/// than in a live call.
library;

import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;

/// Converts a 0–200% volume preference into a WebRTC gain multiplier (0.0–2.0),
/// clamping out-of-range input. LiveKit has no per-track volume, so gain is
/// applied via `Helper.setVolume`; 100% is unity.
double voiceGain(num volumePercent) =>
    (volumePercent / 100).clamp(0.0, 2.0).toDouble();

/// Normalises a selected audio/video device id: a null or empty id means
/// "system default" and is represented as null (what the capture options
/// expect).
String? normalizeDeviceId(String? deviceId) =>
    (deviceId == null || deviceId.isEmpty) ? null : deviceId;

/// Frame rate used for a screen share when the caller doesn't pass one (the
/// settings-derived value normally does). Matches
/// `AccordSettings.defaultScreenShareFps`: an unspecified rate means "the
/// motion-friendly default", never LiveKit's 15 fps slideshow preset.
const int defaultScreenShareFps = 60;

/// Send-bitrate ceiling used for a screen share when the caller doesn't pass
/// one. Matches `AccordSettings.screenShareBitrate` at its 720p60 default.
const int defaultScreenShareBitrate = 3000000;

/// Whether a `RoomDisconnected` should be treated as an *unintentional* drop
/// (so the controller proactively reconnects), versus an intentional teardown
/// (leave / channel-swap / dispose) which must NOT auto-reconnect.
///
/// [intentional] is the session's own `_intentionalDisconnect` flag (set around
/// every deliberate teardown); [clientInitiated] is LiveKit's
/// `DisconnectReason.clientInitiated`. A drop is unintentional only when neither
/// holds.
bool isUnintentionalDisconnect({
  required bool intentional,
  required bool clientInitiated,
}) => !intentional && !clientInitiated;

/// Whether the controller should attempt an auto-reconnect after a session
/// disconnect: only for an unintentional drop while we still believe we're
/// connected, and only once per drop (the one-shot guard, re-checked on the
/// serialized queue by `_reconnectLocked`).
bool shouldAutoReconnect({
  required bool intentional,
  required bool stillConnected,
  required bool alreadyAttempted,
}) => !intentional && stillConnected && !alreadyAttempted;

/// Whether a session state transition from [current] to [next] should fire the
/// `onStateChanged` callback — i.e. only on an actual change.
bool shouldEmitStateChange(VoiceSessionState current, VoiceSessionState next) =>
    current != next;

/// Whether a connection state counts as "live" for the purposes of the
/// reconnect/credential-refresh path (a token refresh / SFU move only reconnects
/// when the session has actually dropped).
bool needsReconnect(VoiceSessionState state) =>
    state == VoiceSessionState.disconnected ||
    state == VoiceSessionState.failed ||
    state == VoiceSessionState.reconnecting;

/// How long after a click on a voice channel row a second click still counts as
/// a double-click (Discord's fast path: double-click joins). Deliberately a
/// touch longer than Material's 300ms so the gesture is forgiving — it's the
/// only join affordance that costs no extra pointer travel.
const Duration voiceDoubleTapWindow = Duration(milliseconds: 400);

/// Whether a click at [now] following a previous click at [lastTapAt] on the
/// same row should be treated as the join gesture.
///
/// The channel row detects this itself instead of adding an `onDoubleTap` to its
/// `InkWell`: with a double-tap recognizer in the arena Flutter delays every
/// single tap until the double-tap timer expires, which would make simply
/// *selecting* a channel feel laggy. Selection stays instant; the second click
/// joins.
bool isVoiceDoubleTap(DateTime? lastTapAt, DateTime now) =>
    lastTapAt != null &&
    !now.isBefore(lastTapAt) &&
    now.difference(lastTapAt) <= voiceDoubleTapWindow;
