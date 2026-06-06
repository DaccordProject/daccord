/// Pure decision logic for the voice stack, extracted so it can be unit-tested
/// without a native LiveKit `Room`. These mirror the hard-won workarounds in
/// `VoiceSession`/`VoiceController`; the tests in
/// `test/features/voice/voice_logic_test.dart` lock the behaviour in so a future
/// change to the voice layer fails loudly rather than in a live call.
library;

import 'package:bonfire/features/voice/services/voice_session.dart'
    show VoiceSessionState;

/// Converts a 0–200% volume preference into a WebRTC gain multiplier (0.0–2.0),
/// clamping out-of-range input. LiveKit has no per-track volume, so gain is
/// applied via `Helper.setVolume`; 100% is unity. Mirrors
/// `voice_session.dart`'s `(volume / 100).clamp(0, 2)`.
double voiceGain(num volumePercent) =>
    (volumePercent / 100).clamp(0.0, 2.0).toDouble();

/// Normalises a selected audio/video device id: a null or empty id means
/// "system default" and is represented as null (what the capture options
/// expect). Mirrors the `(deviceId != null && deviceId.isNotEmpty) ? … : null`
/// guard in `voice_session.dart`.
String? normalizeDeviceId(String? deviceId) =>
    (deviceId == null || deviceId.isEmpty) ? null : deviceId;

/// Whether a `RoomDisconnected` should be treated as an *unintentional* drop
/// (so the controller proactively reconnects), versus an intentional teardown
/// (leave / channel-swap / dispose) which must NOT auto-reconnect.
///
/// [intentional] is the session's own `_intentionalDisconnect` flag (set around
/// every deliberate teardown); [clientInitiated] is LiveKit's
/// `DisconnectReason.clientInitiated`. A drop is unintentional only when neither
/// holds. Mirrors `voice_session.dart`'s disconnect classification.
bool isUnintentionalDisconnect({
  required bool intentional,
  required bool clientInitiated,
}) => !intentional && !clientInitiated;

/// Whether the controller should attempt an auto-reconnect after a session
/// disconnect: only for an unintentional drop while we still believe we're
/// connected, and only once per drop (the one-shot guard). Mirrors
/// `voice.dart`'s `_onSessionDisconnected` gate.
bool shouldAutoReconnect({
  required bool intentional,
  required bool stillConnected,
  required bool alreadyAttempted,
}) => !intentional && stillConnected && !alreadyAttempted;

/// Whether a session state transition from [current] to [next] should fire the
/// `onStateChanged` callback — i.e. only on an actual change. Mirrors
/// `voice_session.dart`'s `_setState` guard (`if (_state == next) return`).
bool shouldEmitStateChange(VoiceSessionState current, VoiceSessionState next) =>
    current != next;

/// Whether a connection state counts as "live" for the purposes of the
/// reconnect/credential-refresh path (a token refresh / SFU move only reconnects
/// when the session has actually dropped). Mirrors the `needsReconnect` set in
/// `voice.dart`'s `handleServerUpdate`.
bool needsReconnect(VoiceSessionState state) =>
    state == VoiceSessionState.disconnected ||
    state == VoiceSessionState.failed ||
    state == VoiceSessionState.reconnecting;
