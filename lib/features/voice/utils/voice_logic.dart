/// Pure decision logic for the voice stack, extracted so it can be unit-tested
/// without a native LiveKit `Room`.
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

/// Frame rate used for a screen share when the caller doesn't pass one.
/// Matches `AccordSettings.defaultScreenShareFps`.
const int defaultScreenShareFps = 60;

/// Send-bitrate ceiling used for a screen share when the caller doesn't pass
/// one. Matches `AccordSettings.screenShareBitrate` at its 720p60 default.
const int defaultScreenShareBitrate = 3000000;

/// Whether the controller should attempt an auto-reconnect after a session
/// disconnect: only for an unintentional drop while we still believe we're
/// connected, and only once per drop (the one-shot guard, re-checked on the
/// serialized queue by `_reconnectLocked`).
bool shouldAutoReconnect({
  required bool intentional,
  required bool stillConnected,
  required bool alreadyAttempted,
}) => !intentional && stillConnected && !alreadyAttempted;

/// Whether fresh credentials (token refresh / SFU move) should reconnect a
/// session in [state]: only once it has dropped, failed or is reconnecting, so
/// a healthy or still-connecting session isn't churned.
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

/// The voice-bar message shown when the microphone could not be captured
/// because the OS denied (or has not granted) microphone access.
const String micPermissionDeniedMessage =
    'Microphone access is unavailable — enable it in Settings';

/// Whether a failed microphone capture/publish was a *permission* failure, as
/// opposed to a device/transport problem.
///
/// The error surfaces differently per platform: iOS and web reject
/// `getUserMedia` with a DOMException named `NotAllowedError`
/// (`FlutterRTCMediaStream.m`, "step 10 Permission Failure"), Android's
/// `GetUserMediaImpl` fails with a `PermissionDenied`-style message, and
/// flutter_webrtc's Dart layer wraps both in a plain
/// `'Unable to getUserMedia: …'` string — so this matches on the message text
/// rather than on a type.
bool isMicPermissionError(Object error) {
  final text = '$error'.toLowerCase();
  return text.contains('notallowederror') ||
      text.contains('permissiondenied') ||
      text.contains('permission');
}

/// The user-facing message for a microphone that could not be published at
/// join/unmute time. A permission failure gets the actionable Settings hint;
/// anything else keeps the platform's reason so the voice bar says *why*.
String describeMicFailure(Object error) {
  if (isMicPermissionError(error)) return micPermissionDeniedMessage;
  final reason = '$error'.replaceFirst('Unable to getUserMedia: ', '').trim();
  return reason.isEmpty
      ? 'Microphone unavailable'
      : 'Microphone unavailable: $reason';
}
